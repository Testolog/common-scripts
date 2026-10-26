"""Cursor CLI adapter: one ``agent`` subprocess per turn, streaming ``stream-json``.

Flags confirmed from ``agent --help`` (CLI 2026.07.09-a3815c0) and kept only in
``cursor_command`` / ``list_cursor_models``:

* ``-p`` / ``--print``                 non-interactive
* ``--output-format stream-json``      newline-delimited JSON events
* ``--stream-partial-output``          text deltas (needs -p + stream-json)
* ``--model <model>``
* ``--mode ask``                       read-only, used for Ask agents
* ``--force``                          allow commands, used for Edit agents
* ``--trust``                          trust the workspace in headless mode
* ``--workspace <path>``               project root from meta.json
* ``--resume <chatId>``                continue the CLI session on later turns
* ``agent models`` / ``--list-models`` model catalog

Pause stops reading the stream and leaves the process running (it blocks on a
full pipe). Resume continues reading the same process. Stop terminates it;
kill sends SIGKILL.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import signal
import subprocess
import threading
import time
from pathlib import Path
from typing import Any

from .base import Adapter, AdapterError, EmitFn, TurnResult

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
EARLY_KILL_WINDOW = 5.0
EARLY_KILL_RETRY_DELAY = 1.0


class CursorCliError(AdapterError):
    pass


def cursor_binary() -> str:
    return os.environ.get("AGENTIC_CURSOR_BIN") or shutil.which("agent") or "agent"


def cursor_command(
    prompt: str,
    *,
    model: str | None,
    workspace: Path,
    mode: str,
    session_id: str | None = None,
    binary: str | None = None,
) -> list[str]:
    cmd = [binary or cursor_binary(), "-p", "--output-format", "stream-json", "--stream-partial-output", "--trust", "--approve-mcps"]
    cmd += ["--workspace", str(workspace), "--sandbox", "enabled"]
    # Bare "auto" leaves the CLI on its own default. A specific Auto mode is
    # auto-smart[optimize_for=balanced|intelligence|cost] and must be passed through.
    if model and model not in ("auto", "default"):
        cmd += ["--model", model]
    if mode.lower() == "ask":
        cmd += ["--mode", "ask"]
    else:
        cmd += ["--force"]
    if session_id:
        cmd += ["--resume", session_id]
    cmd.append(prompt)
    return cmd


# Cursor's three Auto modes are one model id with an optimize_for parameter.
# Confirmed from ~/.cursor/cli-config.json: auto-smart + optimize_for=balanced is "Auto Balance".
AUTO_VARIANTS = (
    {"id": "auto-smart[optimize_for=balanced]", "label": "Auto Balance"},
    {"id": "auto-smart[optimize_for=intelligence]", "label": "Auto Intelligence"},
    {"id": "auto-smart[optimize_for=cost]", "label": "Auto Cost"},
)
_BARE_AUTO = {"auto", "auto-smart", "default"}


def parse_model_listing(output: str) -> list[dict[str, str]]:
    """Models from ``agent models``. Each item is ``{"id", "label"}``.

    The CLI prints ``<id> - <display name>`` and may tag ``(current, default)``.
    ``auto`` and ``auto-smart`` are expanded into Auto Balance, Auto Intelligence, and Auto Cost.
    """
    found: list[dict[str, str]] = []
    seen: set[str] = set()
    for raw in output.splitlines():
        line = ANSI.sub("", raw).strip().lstrip("-*•> ").strip()
        if not line or line.endswith(":") or line.lower().startswith(("available", "error", "tip", "usage", "loading")):
            continue
        line = re.sub(r"\s+\((?:current|default)[^)]*\)\s*$", "", line).strip()
        if " - " in line:
            ident, label = line.split(" - ", 1)
        else:
            parts = re.split(r"\s{2,}|\t", line, maxsplit=1)
            ident, label = parts[0], parts[1] if len(parts) > 1 else ""
        ident = ident.strip()
        label = label.strip()
        if not ident or " " in ident or ident in seen:
            continue
        seen.add(ident)
        found.append({"id": ident, "label": label or ident})
    return _expand_auto(found)


def _expand_auto(models: list[dict[str, str]]) -> list[dict[str, str]]:
    ids = {m["id"] for m in models}
    out: list[dict[str, str]] = []
    replaced = False
    for model in models:
        if model["id"] in _BARE_AUTO:
            if not replaced:
                out.extend(_missing_auto(ids))
                replaced = True
            continue
        out.append(model)
    if not replaced:
        out = _missing_auto(ids) + out
    return out


def _missing_auto(ids: set[str]) -> list[dict[str, str]]:
    return [dict(item) for item in AUTO_VARIANTS if item["id"] not in ids]


def system_project_dir() -> Path:
    """Live system project when ``COMMON_SCRIPT`` is set, otherwise the one shipped with this checkout."""
    common = os.environ.get("COMMON_SCRIPT")
    if common:
        return Path(common) / "system_project"
    return Path(__file__).resolve().parents[3] / "system_project"


def catalog_path() -> Path:
    return system_project_dir() / "cursor_models.json"


def _shipped_catalog_path() -> Path:
    return Path(__file__).resolve().parents[3] / "system_project" / "cursor_models.json"


def _normalize_catalog(raw: Any) -> list[dict[str, str]]:
    items = raw.get("models") if isinstance(raw, dict) else raw
    if not isinstance(items, list):
        return []
    out: list[dict[str, str]] = []
    seen: set[str] = set()
    for item in items:
        if isinstance(item, str):
            ident, label = item, item
        elif isinstance(item, dict):
            ident = str(item.get("id") or item.get("name") or "")
            label = str(item.get("label") or ident)
        else:
            continue
        ident = ident.strip()
        if not ident or ident in seen:
            continue
        seen.add(ident)
        out.append({"id": ident, "label": label.strip() or ident})
    return out


def load_cursor_catalog() -> list[dict[str, str]]:
    """Cursor models stored in the system project. Does not run the Cursor CLI."""
    for path in (catalog_path(), _shipped_catalog_path()):
        if not path.is_file():
            continue
        try:
            models = _normalize_catalog(json.loads(path.read_text()))
        except (OSError, json.JSONDecodeError):
            continue
        if models:
            return models
    return [dict(item) for item in AUTO_VARIANTS]


def save_cursor_catalog(models: list[dict[str, str]]) -> Path:
    path = catalog_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"models": models}, indent=2) + "\n")
    return path


def update_cursor_catalog(binary: str | None = None, timeout: float = 30) -> dict[str, Any]:
    """Ask the Cursor CLI once and write the result into the system project catalog."""
    models = list_cursor_models(binary, timeout)
    path = save_cursor_catalog(models)
    return {"path": str(path), "models": models}


def list_cursor_models(binary: str | None = None, timeout: float = 30) -> list[dict[str, str]]:
    """Model names the Cursor CLI reports for this account."""
    exe = binary or cursor_binary()
    if not shutil.which(exe) and not Path(exe).is_file():
        raise CursorCliError("Cursor CLI 'agent' is not installed")
    last = ""
    for args in (["models"], ["--list-models"]):
        try:
            proc = subprocess.run([exe, *args], capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            last = f"agent {' '.join(args)} timed out"
            continue
        out = (proc.stdout or "") + (proc.stderr or "")
        if proc.returncode == 0 and "Authentication required" not in out:
            names = parse_model_listing(proc.stdout)
            if names:
                return names
        last = out.strip()
    raise CursorCliError(last or "agent reported no models")


def absorb_delta(previous: str, chunk: str) -> tuple[str, str]:
    """Append a stream chunk, dropping a snapshot that repeats text already shown.

    Returns ``(stored text, delta to display)``. The displayed delta is empty
    when the chunk is a duplicate of what is already stored.
    """
    if not chunk:
        return previous, ""
    if previous and chunk.startswith(previous):
        return chunk, chunk[len(previous):]
    if len(chunk) > 80 and (previous.endswith(chunk) or chunk in previous or (len(chunk) > 120 and chunk[:120] in previous)):
        return previous, ""
    return previous + chunk, chunk


def cursor_mcp_login(identifier: str, binary: str | None = None, timeout: float = 300) -> str:
    """Run ``agent mcp login`` so Cursor's own MCP session, not a side client, is authenticated."""
    proc = subprocess.run(
        [binary or cursor_binary(), "mcp", "login", identifier],
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )
    output = "\n".join(part.strip() for part in (proc.stdout, proc.stderr) if part and part.strip())
    if proc.returncode != 0:
        raise RuntimeError(output or f"agent mcp login {identifier} exited {proc.returncode}")
    return output


def cursor_mcp_outcome(tool_call: dict) -> tuple[str | None, str | None]:
    """``(server, "auth"|"http")`` when a Cursor MCP tool needs login or got HTTP 400/500."""
    if not isinstance(tool_call, dict):
        return None, None
    server = None
    result = ""
    for value in tool_call.values():
        if not isinstance(value, dict):
            continue
        args = value.get("args") or {}
        if isinstance(args, dict) and args.get("server"):
            server = str(args["server"])
        if value.get("result") is not None:
            result = json.dumps(value["result"])
    if not server:
        return None, None
    lower = result.lower()
    if "needsauth" in lower or "requires authentication" in lower:
        return server, "auth"
    if re.search(r"\b(?:HTTP|status(?:\s+code)?|code)\s*[:=]?\s*(?:400|500)\b", result, re.I):
        return server, "http"
    return None, None


def choose_turn_text(streamed: str, final: str) -> str:
    """Prefer the streamed answer when the CLI result repeats it."""
    streamed = streamed or ""
    final = final or ""
    if not final:
        return streamed
    if not streamed:
        return final
    if streamed in final and len(final) > int(len(streamed) * 1.2):
        return streamed
    if "```tool" in streamed and "```tool" not in final:
        return streamed
    return final


def _content_text(message: Any, kind: str = "text") -> str:
    if not isinstance(message, dict):
        return ""
    content = message.get("content")
    if isinstance(content, str):
        return content if kind == "text" else ""
    out = ""
    for part in content or []:
        if isinstance(part, dict) and part.get("type") == kind:
            out += part.get(kind) or part.get("text") or ""
    return out


class CursorAdapter(Adapter):
    resume_reissues = False

    def __init__(self, model: str | None, workspace: Path, mode: str, binary: str | None = None):
        self.model = model
        self.workspace = Path(workspace)
        self.mode = mode
        self.binary = binary
        self.session_id: str | None = None
        self._proc: subprocess.Popen[str] | None = None
        self.on_authorization = None
        self._reading = threading.Event()
        self._reading.set()
        self._stopped = threading.Event()

    def build_prompt(self, system: str, messages: list[dict[str, str]]) -> str:
        if self.session_id and messages:
            return messages[-1]["content"]
        parts = [f"<system>\n{system}\n</system>"] if system else []
        for m in messages:
            parts.append(f"<{m['role']}>\n{m['content']}\n</{m['role']}>")
        return "\n\n".join(parts)

    def handle_event(self, obj: dict[str, Any], emit: EmitFn, state: dict[str, Any]) -> None:
        if obj.get("session_id"):
            self.session_id = obj["session_id"]
        kind = obj.get("type")
        if kind == "assistant":
            text = _content_text(obj.get("message"))
            if text:
                stored, delta = absorb_delta(state["text"], text)
                state["text"] = stored
                if delta:
                    emit({"type": "delta", "text": delta})
            thought = _content_text(obj.get("message"), "thinking")
            if thought:
                emit({"type": "thought", "text": thought})
        elif kind == "thinking":
            emit({"type": "thought", "text": obj.get("text") or ""})
        elif kind == "tool_call":
            emit({"type": "tool", "subtype": obj.get("subtype"), "tool_call": obj.get("tool_call")})
            if obj.get("subtype") == "completed":
                self._mcp_guard(obj.get("tool_call") or {}, state)
        elif kind == "result":
            if isinstance(obj.get("result"), str):
                state["final"] = obj["result"]
            if isinstance(obj.get("usage"), dict):
                state["usage"] = obj["usage"]
                emit({"type": "usage", "usage": obj["usage"]})
            if obj.get("is_error"):
                state["error"] = state.get("final") or "cursor agent reported an error"
        elif kind == "system":
            emit({"type": "status", "status": "cursor:" + str(obj.get("subtype", "system")), "model": obj.get("model")})

    def _mcp_guard(self, tool_call: dict, state: dict[str, Any]) -> None:
        """Generate OAuth once when a server requires it, and stop after three HTTP 400/500 answers."""
        server, outcome = cursor_mcp_outcome(tool_call)
        if not server:
            return
        if outcome == "auth":
            started = state.setdefault("auth_for", set())
            if server in started:
                return
            started.add(server)
            failed = None
            if self.on_authorization:
                try:
                    self.on_authorization(server)
                except Exception as exc:
                    failed = exc
            if failed:
                state["text"] = (state.get("text") or "") + f"\n\nCursor MCP login for {server} failed: {failed}\n"
            else:
                state["continue_after_auth"] = server
                state["text"] = (state.get("text") or "") + (
                    f"\n\nCursor MCP login for {server} finished. Continue the task and use its tools now.\n"
                )
            self.stop()
            return
        counts = state.setdefault("http_fails", {})
        counts[server] = counts.get(server, 0) + 1
        if counts[server] >= 3:
            state["text"] = (state.get("text") or "") + (
                f"\n\nStopped connecting to {server} after 3 responses of 400 or 500.\n"
            )
            self.stop()

    def run_turn(self, system: str, messages: list[dict[str, str]], emit: EmitFn) -> TurnResult:
        result, early_kill = self._run_once(system, messages, emit)
        if early_kill:
            # macOS SIGKILLs a freshly self-updated CLI binary on its first exec while it is verified.
            emit({"type": "log", "text": "Cursor CLI was killed before producing output; retrying once"})
            time.sleep(EARLY_KILL_RETRY_DELAY)
            result, early_kill = self._run_once(system, messages, emit)
            if early_kill:
                result.error = (
                    "Cursor CLI was killed by SIGKILL before producing output. "
                    "Run `agent --version` in a terminal to check the CLI starts, then resend."
                )
        return result

    def _run_once(self, system: str, messages: list[dict[str, str]], emit: EmitFn) -> tuple[TurnResult, bool]:
        self._stopped.clear()
        started = time.monotonic()
        cmd = cursor_command(
            self.build_prompt(system, messages),
            model=self.model,
            workspace=self.workspace,
            mode=self.mode,
            session_id=self.session_id,
            binary=self.binary,
        )
        try:
            proc = subprocess.Popen(
                cmd, cwd=str(self.workspace), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1
            )
        except FileNotFoundError:
            return TurnResult(error="Cursor CLI 'agent' is not installed"), False
        self._proc = proc
        state: dict[str, Any] = {"text": "", "final": None, "usage": None, "error": None}
        produced = False
        assert proc.stdout is not None
        while True:
            self._reading.wait()
            if self._stopped.is_set():
                break
            line = proc.stdout.readline()
            if not line:
                break
            line = line.strip()
            if not line:
                continue
            produced = True
            try:
                obj = json.loads(line)
            except ValueError:
                emit({"type": "log", "text": line})
                continue
            if isinstance(obj, dict):
                self.handle_event(obj, emit, state)
        code = proc.wait()
        self._proc = None
        stderr = proc.stderr.read() if proc.stderr else ""
        for pipe in (proc.stdout, proc.stderr):
            if pipe is not None:
                pipe.close()
        # Keep a ```tool fence from the streamed text when the final result drops it.
        streamed = state["text"] or ""
        final = state["final"] if isinstance(state["final"], str) else ""
        text = choose_turn_text(streamed, final)
        if self._stopped.is_set():
            server = state.get("continue_after_auth")
            extra = {"continue_after_auth": server} if server else {}
            return TurnResult(text=state["text"], aborted=not server, usage=state["usage"], extra=extra), False
        early_kill = (
            code == -signal.SIGKILL
            and not produced
            and not stderr.strip()
            and time.monotonic() - started < EARLY_KILL_WINDOW
        )
        if code != 0 and not state["error"]:
            state["error"] = stderr.strip() or f"agent exited with {code}"
        result = TurnResult(text=text, error=state["error"], usage=state["usage"], extra={"session_id": self.session_id})
        return result, early_kill

    def pause(self) -> None:
        self._reading.clear()

    def resume(self) -> None:
        self._reading.set()

    def _signal(self, sig: int) -> None:
        self._stopped.set()
        proc = self._proc
        if proc is not None and proc.poll() is None:
            try:
                proc.send_signal(sig)
            except ProcessLookupError:
                pass
        self._reading.set()

    def stop(self) -> None:
        self._signal(signal.SIGTERM)

    def kill(self) -> None:
        self._signal(signal.SIGKILL)
