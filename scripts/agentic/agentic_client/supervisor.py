"""Detached per-agent supervisor.

Started with ``start_new_session=True`` so it outlives the caller (Neovim). It
writes ``supervisor.pid``, appends every event to ``events.jsonl``, and reads
commands from ``inbox.jsonl`` (JSON lines), so any client can reattach by agent
id after a restart:

    {"cmd": "send", "text": "..."}
    {"cmd": "pause"} | {"cmd": "resume"} | {"cmd": "stop"}
    {"cmd": "attach", "pid": <nvim pid>} | {"cmd": "detach"}
    {"cmd": "lsp_result", "id": "<request id>", "text": "..."}

SIGTERM is treated as stop; SIGKILL to the process group is AgentKill.
"""

from __future__ import annotations

import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
import traceback
import uuid
from pathlib import Path
from typing import Any

from . import project as proj
from .adapters import make_adapter
from .adapters.base import Adapter, TurnResult
from .context import at_limit, handoff, update_tokens
from .mcp_catalog import load_catalog
from .state import (
    INBOX,
    LOG,
    MCP_LOG,
    PID,
    TRANSCRIPT,
    Agent,
    append_event,
    append_transcript,
    branch_dir,
    pid_alive,
    read_meta,
    write_json_atomic,
)
from .tools import NO_LSP_ATTACHED, ToolRunner

MESSAGES = "messages.json"
INBOX_OFFSET = "inbox.offset"
QUEUE = "queue.json"
# A lone "---" is concealed as a Markdown rule in the read buffer.
ANSWER_RULE = "─────────── --- ───────────"
POLL_SECONDS = 0.2
LSP_TIMEOUT = 60.0
MAX_TOOL_ROUNDS = 8
TOOL_BLOCK = re.compile(r"```tool\s*\n(.*?)\n```", re.S)


def pending_tool_calls(text: str) -> list[str]:
    """Tool fences the model is waiting on.

    A fence is a call only when the answer ends with it. Prose after the last
    fence means the model already finished, so those fences are not run again.
    """
    if not text:
        return []
    matches = list(TOOL_BLOCK.finditer(text))
    if not matches or text[matches[-1].end():].strip():
        return []
    return [match.group(1) for match in matches]

TOOL_PROTOCOL = """\
## Tools

The prompt and skill text above is already loaded. Do not read those files to learn your instructions.

To call a tool, answer with one fenced block per call and nothing after it:

```tool
{"name": "<tool name>", "arguments": <list of argv words, or an object>}
```

The client runs the tool from the project root and replies with its output.
Do not use Grep, Glob, Read, Shell, find, or fzf for this project. Use the tools listed below
(`fsearch`, `sd`, `dasel`, `ast-grep`, `git apply`, `lsp_*`, `agent_create`, `agent_rename`, and the rest).
`agent_rename` renames one agent of this project per call. Pass `{"agent": "<agent id>", "name": "<new name>"}`.
To rename yourself, use the agent id in the system message. It does not edit the project.
When an MCP server requires authorization, the client runs the login and then continues this same task.
Do not call mcp_auth, and do not keep trying that server while it is logging in. A server that answers
HTTP 400 or 500 three times is stopped for this agent.
"""


def package_parent() -> Path:
    return Path(__file__).resolve().parent.parent


LAUNCHER = """\
import subprocess, sys
log = open(sys.argv[2], "a")
proc = subprocess.Popen(
    [sys.executable, "-m", "agentic_client", "supervise", sys.argv[1]],
    stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True, close_fds=True,
)
print(proc.pid)
"""


def spawn_supervisor(agent: Agent) -> int:
    """Start a detached supervisor for ``agent`` and record its pid.

    A short-lived launcher starts the supervisor in a new session and exits, so the
    supervisor is reparented to init and is never a zombie of the caller.
    """
    env = dict(os.environ)
    env["PYTHONPATH"] = os.pathsep.join(filter(None, [str(package_parent()), env.get("PYTHONPATH")]))
    # Template tools and prompts reference $COMMON_SCRIPT; default it to the checkout this client ships in.
    checkout = package_parent().parent.parent
    if not env.get("COMMON_SCRIPT") and (checkout / "system_project").is_dir():
        env["COMMON_SCRIPT"] = str(checkout)
    out = subprocess.run(
        [sys.executable, "-c", LAUNCHER, str(agent.dir), str(agent.path(LOG))],
        cwd=str(agent.project_root),
        env=env,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        check=True,
    )
    pid = int(out.stdout.strip())
    agent.path(PID).write_text(f"{pid}\n")
    return pid


class Supervisor:
    def __init__(self, agent_dir: Path):
        self.agent = Agent(Path(agent_dir), read_meta(Path(agent_dir)))
        self.root = self.agent.project_root
        self.data = proj.load_project(self.root)
        self.model = proj.parse_model(self.agent.meta["model"])
        self.mode = self.agent.meta["mode"]
        self.adapter: Adapter = make_adapter(self.model, self.root, self.mode)
        self.messages: list[dict[str, str]] = self._load_messages()
        self.queue: list[str] = []
        self._turn_open = False
        self.worker: threading.Thread | None = None
        self.paused = False
        self.stopping = False
        self.nvim_pid: int | None = None
        self.lsp_waiters: dict[str, dict[str, Any]] = {}
        self.lock = threading.Lock()
        self.mcp = None
        if hasattr(self.adapter, "on_authorization"):
            self.adapter.on_authorization = self._authorize_mcp
        self.runner = ToolRunner(
            proj.tools(self.data), self.mode, self.root, lsp=self._lsp_call, mcp=self._mcp_call, read_roots=self._read_roots
        )
        self.system = self._system_prompt()

    # ----- setup -------------------------------------------------------------

    def _system_prompt(self) -> str:
        extra = self.agent.meta.get("preamble") or ""
        mode_line = (
            "Mode: Ask (read-only for this project). Mutating tools are refused. "
            "When the user asks for a change, call agent_create to spawn an Edit agent with that "
            "instruction and report its agent id. Do not refuse the request, and do not tell the user to switch mode."
            if self.mode == "ask"
            else "Mode: Edit. You may read, write, delete, and execute inside the project root."
        )
        tools_text = self.runner.describe()
        identity = (
            f"This agent is {self.agent.meta.get('name') or self.agent.id} (agent id `{self.agent.id}`). "
            "To rename this agent, call agent_rename with this agent id. "
            "To rename another agent of this project, call agent_rename once with that agent's id."
        )
        tail = f"{identity}\n\n{mode_line}\n\n{self._boundary()}\n\n{TOOL_PROTOCOL}\n{tools_text}"
        return proj.build_system_preamble(
            self.root, self.data, self.agent.meta.get("prompts"), self.agent.meta.get("skills"), extra + "\n\n" + tail
        )

    def _read_roots(self) -> list[Path]:
        """Project root, this project+branch's agent logs (every manager), and user grants."""
        self.agent.reload()
        roots = [self.root.resolve()]
        meta = self.agent.meta
        logs = branch_dir(str(meta.get("project_name") or ""), str(meta.get("branch") or "nogit"))
        roots.append(logs.resolve())
        for raw in meta.get("extra_read_roots") or []:
            if isinstance(raw, str) and raw.strip():
                roots.append(Path(raw).expanduser().resolve())
        return roots

    def _boundary(self) -> str:
        self.agent.reload()
        logs = branch_dir(str(self.agent.meta.get("project_name") or ""), str(self.agent.meta.get("branch") or "nogit"))
        granted = [raw for raw in (self.agent.meta.get("extra_read_roots") or []) if isinstance(raw, str) and raw.strip()]
        lines = [
            "## Directory boundary",
            f"Project root: {self.root.resolve()}",
            "Read and write only inside that directory and the directories under it.",
            f"You may read agent logs under {logs.resolve()} for this project and branch, every manager. Do not write there.",
            "Do not read or write any other path. A path outside this boundary is refused.",
            "Only the user can grant another folder, with :AgentAllowRead. Do not grant one yourself.",
        ]
        if granted:
            lines.append("The user granted read access to: " + ", ".join(granted))
        return "\n".join(lines)

    def _load_messages(self) -> list[dict[str, str]]:
        try:
            return json.loads(self.agent.path(MESSAGES).read_text())
        except (OSError, ValueError):
            return []

    def _save_messages(self) -> None:
        write_json_atomic(self.agent.path(MESSAGES), self.messages)

    def _publish_preamble(self) -> None:
        """Write the loaded prompts and skills into the transcript as soon as the agent starts."""
        path = self.agent.path(TRANSCRIPT)
        try:
            current = path.read_text()
        except OSError:
            current = ""
        if "## System" in current:
            return
        body = self.system.strip()
        if not body:
            return
        append_transcript(self.agent, f"## System\n\n{body}\n\n")
        self.emit({"type": "preamble"})

    def emit(self, event: dict[str, Any]) -> None:
        append_event(self.agent, event)

    def set_status(self, status: str) -> None:
        self.agent.reload()
        self.agent.meta["status"] = status
        self.agent.save()
        self.emit({"type": "status", "status": status})

    def _start_mcp(self) -> None:
        catalog = load_catalog(proj.mcp_activation(self.data))
        self.emit(
            {
                "type": "tree",
                "action": "mcp_catalog",
                "error": catalog.error,
                "servers": [s.to_dict() for s in catalog.servers],
            }
        )
        from .serena import serena_available

        use_serena = serena_available()
        if catalog.error:
            self._mcp_log("mcp", catalog.error)
        for server in catalog.servers:
            if server.status != "connect":
                self._mcp_log(server.name, server.status + (f": {server.reason}" if server.reason else ""))
        if not use_serena:
            self.emit({"type": "tree", "action": "mcp_error", "server": "serena", "error": "serena is not on PATH"})
            self._mcp_log("serena", "serena is not on PATH")
        if not catalog.to_connect() and not use_serena:
            return
        try:
            from .mcp_client import McpManager

            self.mcp = McpManager(
                catalog,
                self.root,
                on_error=lambda name, msg: self.emit({"type": "tree", "action": "mcp_error", "server": name, "error": msg}),
                on_log=self._mcp_log,
                serena=use_serena,
            )
            status = self.mcp.connect_all()
            self.emit({"type": "tree", "action": "mcp_status", "status": status, "tools": self.mcp.tools})
        except Exception as exc:
            self._mcp_log("mcp", str(exc))
            self.emit({"type": "tree", "action": "mcp_error", "server": "mcp", "error": str(exc)})

    # ----- tool bridges ------------------------------------------------------

    def _lsp_call(self, tool: proj.Tool, args: list[str]) -> str:
        if not pid_alive(self.nvim_pid):
            return NO_LSP_ATTACHED
        request_id = uuid.uuid4().hex
        waiter: dict[str, Any] = {"event": threading.Event(), "text": None}
        with self.lock:
            self.lsp_waiters[request_id] = waiter
        self.emit({"type": "lsp_request", "id": request_id, "tool": tool.name, "function": tool.function, "arguments": args})
        answered = waiter["event"].wait(LSP_TIMEOUT)
        with self.lock:
            self.lsp_waiters.pop(request_id, None)
        if not answered:
            return f"Neovim did not answer the {tool.name} request within {LSP_TIMEOUT:.0f}s."
        return waiter["text"] or ""

    def _mcp_log(self, server: str, message: str) -> None:
        message = " ".join(str(message).split())
        line = time.strftime("%H:%M:%S") + f" {server}: {message}"
        try:
            with self.agent.path(MCP_LOG).open("a") as fh:
                fh.write(line + "\n")
        except OSError:
            pass
        self.emit({"type": "mcp_log", "text": line})

    def _authorize_mcp(self, name: str) -> None:
        """Cursor reported needsAuth. Log that server in with ``agent mcp login``, which is the session the agent calls."""
        from .adapters.cursor import cursor_mcp_login

        self.emit(
            {
                "type": "tree",
                "action": "mcp_error",
                "server": name,
                "error": "authorization required; running agent mcp login",
            }
        )
        self._mcp_log(name, "authorization required; running agent mcp login")
        try:
            cursor_mcp_login(name)
        except Exception as exc:
            self._mcp_log(name, f"Cursor MCP login failed: {exc}")
            raise
        self._mcp_log(name, "Cursor MCP login finished; continuing the task")
        self.emit(
            {
                "type": "tree",
                "action": "mcp_error",
                "server": name,
                "error": "Cursor MCP login finished; continuing the task",
            }
        )

    def _mcp_call(self, tool: proj.Tool, arguments: dict[str, Any]) -> str:
        from .mcp_client import split_mcp_call

        if self.mcp is None:
            return f"MCP server {tool.function!r} is not connected."
        server, name, args = split_mcp_call(tool.function, arguments)
        return self.mcp.call_tool(server, name, args)

    # ----- turns -------------------------------------------------------------

    def _record(self, role: str, text: str, note: str = "") -> None:
        self.messages.append({"role": role, "content": text})
        self._save_messages()
        header = {"user": "## User", "assistant": "## Assistant", "tool": "## Tool"}.get(role, f"## {role}")
        if role == "user" and note == "":
            self.emit({"type": "user", "text": text})
        prefix = ""
        if role == "assistant":
            try:
                current = self.agent.path(TRANSCRIPT).read_text()
            except OSError:
                current = ""
            if "\n## Assistant" in "\n" + current:
                prefix = ANSWER_RULE + "\n\n"
        append_transcript(self.agent, f"{prefix}{header}{note}\n\n{text}\n\n")

    def _turn(self) -> None:
        self.system = self._system_prompt()
        seen_calls: set[str] = set()
        continued_auth: set[str] = set()
        for _ in range(MAX_TOOL_ROUNDS + 1):
            self.set_status("running")
            result: TurnResult = self.adapter.run_turn(self.system, self.messages, self.emit)
            continued = (result.extra or {}).get("continue_after_auth")
            if result.text:
                note = " (interrupted)" if result.aborted and not continued else ""
                self._record("assistant", result.text, note)
            transcript = self.agent.path(TRANSCRIPT).read_text()
            self.agent.reload()
            update_tokens(self.agent, result.usage, transcript)
            self.agent.save()
            self.emit({"type": "tokens", "tokens": self.agent.meta["tokens"], "limit": self.agent.meta.get("context_limit")})
            if result.error:
                self.emit({"type": "error", "error": result.error})
                self.set_status("error")
                return
            if result.aborted:
                self.set_status("stopped" if self.stopping else "paused")
                return
            if continued:
                if continued in continued_auth:
                    break
                continued_auth.add(continued)
                self._record(
                    "user",
                    f"Authorization for MCP server {continued} finished. "
                    "Continue the same task now and use that server's tools. Do not call mcp_auth.",
                    " (mcp)",
                )
                continue
            if at_limit(self.agent):
                self._handoff()
                return
            calls = []
            for raw in pending_tool_calls(result.text or ""):
                key = raw.strip()
                if key and key not in seen_calls:
                    seen_calls.add(key)
                    calls.append(raw)
            if not calls:
                break
            for raw in calls:
                self._run_tool_block(raw)
        self.set_status("idle")

    def _run_tool_block(self, raw: str) -> None:
        try:
            call = json.loads(raw)
            name, arguments = call["name"], call.get("arguments")
        except (ValueError, KeyError, TypeError) as exc:
            self._record("user", f"Tool call could not be parsed: {exc}", " (tool)")
            return
        self.emit({"type": "tool", "subtype": "started", "name": name, "arguments": arguments})
        res = self.runner.call(name, arguments)
        if name == "agent_rename" and res.ok:
            self._note_rename(res.text)
        self.emit({"type": "tool", "subtype": "completed", "name": name, "ok": res.ok, "refused": res.refused})
        self._record("user", f"Result of tool `{name}`:\n\n```\n{res.text}\n```", " (tool)")

    def _note_rename(self, text: str) -> None:
        try:
            payload = json.loads(text)
        except ValueError:
            return
        renamed = payload.get("agent_id")
        new_name = payload.get("name")
        if not payload.get("ok") or not renamed or not new_name:
            return
        if renamed == self.agent.id:
            self.agent.reload()
        self.emit({"type": "tree", "action": "renamed", "agent_id": renamed, "name": new_name})

    def _handoff(self) -> None:
        child = handoff(self.agent)
        try:
            spawn_supervisor(child)
        except Exception as exc:
            self.emit({"type": "error", "error": f"could not start child supervisor: {exc}"})
        self.stopping = True

    def _start_turn(self, text: str | None) -> None:
        self._turn_open = True
        if text is not None:
            self._record("user", text)
        self.worker = threading.Thread(target=self._safe_turn, name="turn", daemon=True)
        self.worker.start()

    def _safe_turn(self) -> None:
        try:
            self._turn()
        except Exception:
            self.emit({"type": "error", "error": traceback.format_exc()})
            self.set_status("error")
        finally:
            self._turn_open = False

    def _busy(self) -> bool:
        return self._turn_open or (self.worker is not None and self.worker.is_alive())

    def _save_queue(self) -> None:
        write_json_atomic(self.agent.path(QUEUE), self.queue)

    def _load_queue(self) -> None:
        try:
            data = json.loads(self.agent.path(QUEUE).read_text())
        except (OSError, ValueError):
            return
        if isinstance(data, list):
            self.queue = [item for item in data if isinstance(item, str) and item.strip()]

    def _emit_queue(self) -> None:
        self._save_queue()
        self.emit({"type": "queue", "items": list(self.queue)})

    def _enqueue(self, text: str) -> None:
        self.queue.append(text)
        self._emit_queue()

    # ----- commands ----------------------------------------------------------

    def handle(self, cmd: dict[str, Any]) -> None:
        kind = cmd.get("cmd")
        if kind == "send":
            if self.agent.reload().is_read_only():
                self.emit({"type": "error", "error": "agent is read-only after handoff"})
            elif self._busy() or self.paused:
                self._enqueue(cmd.get("text", ""))
            else:
                self._start_turn(cmd.get("text", ""))
        elif kind == "pause":
            self.paused = True
            self.adapter.pause()
            if not self.adapter.resume_reissues:
                self.set_status("paused")
        elif kind == "resume":
            self.paused = False
            self.adapter.resume()
            if self.adapter.resume_reissues and not self._busy() and self.messages:
                self._start_turn(None)
            else:
                self.set_status("running" if self._busy() else "idle")
        elif kind == "stop":
            self.stop()
        elif kind == "attach":
            self.nvim_pid = int(cmd.get("pid") or 0) or None
            self.emit({"type": "status", "status": "attached", "nvim_pid": self.nvim_pid})
        elif kind == "detach":
            self.nvim_pid = None
        elif kind == "lsp_result":
            with self.lock:
                waiter = self.lsp_waiters.get(cmd.get("id", ""))
            if waiter:
                waiter["text"] = cmd.get("text", "")
                waiter["event"].set()

    def stop(self) -> None:
        self.stopping = True
        self.adapter.stop()

    def _read_inbox(self, offset: int) -> tuple[list[dict[str, Any]], int]:
        try:
            with self.agent.path(INBOX).open("rb") as fh:
                fh.seek(offset)
                data = fh.read()
        except FileNotFoundError:
            return [], offset
        end = data.rfind(b"\n") + 1
        cmds = []
        for line in data[:end].splitlines():
            try:
                cmds.append(json.loads(line))
            except ValueError:
                continue
        return cmds, offset + end

    def run(self) -> int:
        self.agent.path(PID).write_text(f"{os.getpid()}\n")
        signal.signal(signal.SIGTERM, lambda *_: self.stop())
        signal.signal(signal.SIGHUP, signal.SIG_IGN)
        self.set_status("idle")
        self._publish_preamble()
        self._load_queue()
        self._emit_queue()
        threading.Thread(target=self._start_mcp, name="mcp-start", daemon=True).start()
        offset_file = self.agent.path(INBOX_OFFSET)
        try:
            offset = int(offset_file.read_text())
        except (OSError, ValueError):
            offset = 0
        while True:
            cmds, offset = self._read_inbox(offset)
            if cmds:
                offset_file.write_text(str(offset))
            for cmd in cmds:
                self.handle(cmd)
            if self.stopping and not self._busy():
                break
            if self.queue and not self._busy() and not self.paused:
                nxt = self.queue.pop(0)
                self._emit_queue()
                self._start_turn(nxt)
            time.sleep(POLL_SECONDS)
        if self.agent.reload().meta.get("status") != "handed_off":
            self.set_status("stopped")
        if self.mcp is not None:
            self.mcp.close()
        try:
            self.agent.path(PID).unlink()
        except OSError:
            pass
        return 0


def main(agent_dir: str) -> int:
    return Supervisor(Path(agent_dir)).run()
