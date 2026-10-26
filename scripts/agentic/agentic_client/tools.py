"""Tool policy and dispatch.

* ``kind`` defaults to ``shell``: ``function`` runs through ``/bin/sh -c`` with the
  project root from ``meta.json`` as cwd; agent arguments are shell-quoted and appended.
* ``kind: lsp``: a request the supervisor hands to Neovim (no language server is started).
* ``kind: mcp``: an MCP tool call.
* Ask mode refuses any tool whose ``mutates`` is true or missing.
"""

from __future__ import annotations

import shlex
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Sequence

from .project import Tool
from .sandbox import check_arguments

ASK = "ask"
EDIT = "edit"
NO_LSP_ATTACHED = "No language server is attached: Neovim is not attached to this agent."

LspCallback = Callable[[Tool, list[str]], str]
McpCallback = Callable[[Tool, dict[str, Any]], str]


@dataclass
class ToolResult:
    ok: bool
    text: str
    refused: bool = False


def tool_allowed(tool: Tool, mode: str) -> bool:
    if mode.lower() == EDIT:
        return True
    return not tool.is_mutating


def refusal_text(tool: Tool) -> str:
    why = "mutates files" if tool.mutates is True else "does not declare mutates (treated as mutating)"
    return (
        f"Refused: tool '{tool.name}' {why} and this agent is in Ask mode. "
        "Describe the change as a suggestion; the user can start an Edit agent to apply it."
    )


def build_shell_command(function: str, args: Sequence[str]) -> str:
    """``function`` is used verbatim (it may reference env vars); args are quoted and appended."""
    quoted = " ".join(shlex.quote(str(a)) for a in args)
    return f"{function} {quoted}".strip()


def fsearch_args(pattern: str, paths: Sequence[str] = (), content: bool = False) -> list[str]:
    """Arguments for the fsearch wrapper: ``find <pattern> [paths...]`` or ``find <pattern> -f``."""
    if content:
        return ["find", pattern, "-f"]
    return ["find", pattern, *paths]


def sd_args(file: str, old: str, new: str) -> list[str]:
    """Arguments for the sd wrapper, in ``<file> <old> <new>`` order.

    The wrapper runs ``sd -F`` and refuses an ambiguous match; this only orders
    the agent's values so literal text reaches it as three separate words.
    """
    if not old:
        raise ValueError("sd: old text must not be empty")
    return [file, old, new]


def normalize_args(tool: Tool, arguments: Any) -> list[str]:
    """Accept a list, a string, or a dict from the model and return argv words."""
    if arguments is None:
        return []
    if isinstance(arguments, str):
        return shlex.split(arguments)
    if isinstance(arguments, (list, tuple)):
        return [str(a) for a in arguments]
    if isinstance(arguments, dict):
        if tool.name == "fsearch" and "pattern" in arguments:
            return fsearch_args(arguments["pattern"], arguments.get("paths") or (), bool(arguments.get("content")))
        if tool.name == "sd" and {"file", "old", "new"} <= arguments.keys():
            return sd_args(arguments["file"], arguments["old"], arguments["new"])
        if tool.name == "agent_rename" and arguments.get("name") and (arguments.get("agent") or arguments.get("agent_id")):
            return ["--agent", str(arguments.get("agent") or arguments.get("agent_id")), "--name", str(arguments["name"])]
        if "args" in arguments:
            return normalize_args(tool, arguments["args"])
    raise ValueError(f"cannot turn arguments for {tool.name!r} into argv: {arguments!r}")


def run_shell(tool: Tool, args: Sequence[str], cwd: Path, timeout: float = 300) -> ToolResult:
    command = build_shell_command(tool.function, args)
    try:
        proc = subprocess.run(
            ["/bin/sh", "-c", command], cwd=str(cwd), capture_output=True, text=True, timeout=timeout
        )
    except subprocess.TimeoutExpired:
        return ToolResult(False, f"{tool.name}: timed out after {timeout}s")
    out = proc.stdout
    if proc.stderr:
        out += ("\n" if out else "") + proc.stderr
    return ToolResult(proc.returncode == 0, out.strip() or f"(exit {proc.returncode})")


class ToolRunner:
    def __init__(
        self,
        tools: Sequence[Tool],
        mode: str,
        project_root: Path,
        lsp: LspCallback | None = None,
        mcp: McpCallback | None = None,
        read_roots: Callable[[], Sequence[Path]] | None = None,
    ):
        self.tools = {t.name: t for t in tools}
        self.mode = mode.lower()
        self.project_root = Path(project_root)
        self.lsp = lsp
        self.mcp = mcp
        self.read_roots = read_roots or (lambda: [self.project_root])

    def describe(self) -> str:
        lines = []
        for t in self.tools.values():
            flag = "read-only" if not t.is_mutating else "mutating"
            note = "" if tool_allowed(t, self.mode) else " (refused in Ask mode)"
            lines.append(f"- {t.name} [{t.kind}, {flag}]{note}: {t.description}")
        return "\n".join(lines)

    def _confine(self, tool: Tool, args: Sequence[str]) -> ToolResult | None:
        reason = check_arguments(
            list(args),
            self.project_root,
            write_root=self.project_root,
            read_roots=list(self.read_roots()),
            mutating=tool.is_mutating,
        )
        if reason:
            return ToolResult(False, reason, refused=True)
        return None

    def call(self, name: str, arguments: Any = None) -> ToolResult:
        tool = self.tools.get(name)
        if tool is None:
            return ToolResult(False, f"Unknown tool {name!r}.")
        if not tool_allowed(tool, self.mode):
            return ToolResult(False, refusal_text(tool), refused=True)
        try:
            if tool.kind == "shell":
                args = normalize_args(tool, arguments)
                refused = self._confine(tool, args)
                if refused:
                    return refused
                return run_shell(tool, args, self.project_root)
            if tool.kind == "lsp":
                args = normalize_args(tool, arguments)
                refused = self._confine(tool, args)
                if refused:
                    return refused
                if self.lsp is None:
                    return ToolResult(False, NO_LSP_ATTACHED)
                return ToolResult(True, self.lsp(tool, args))
            if tool.kind == "mcp":
                if self.mcp is None:
                    return ToolResult(False, f"MCP is not available for tool {name!r}.")
                payload = arguments if isinstance(arguments, dict) else {"args": normalize_args(tool, arguments)}
                return ToolResult(True, self.mcp(tool, payload))
        except Exception as exc:  # tool errors go back to the model as text
            return ToolResult(False, f"{name}: {exc}")
        return ToolResult(False, f"Unsupported tool kind {tool.kind!r} for {name!r}.")
