"""Per-agent Serena MCP server, scoped to the agent's project root.

The command is ``serena start-mcp-server --project <root> --agent-interface tools``
with the dashboard left closed. ``tools`` lists one operation per tool. The REPL
interface only lists the startup tools.
Override with ``AGENTIC_SERENA_CMD`` (a shell-style string; ``{root}`` is
replaced by the project root) if the installed CLI differs.
"""

from __future__ import annotations

import os
import shlex
import shutil
from pathlib import Path

SERENA_SERVER = "serena"


def serena_command(project_root: Path) -> list[str]:
    override = os.environ.get("AGENTIC_SERENA_CMD")
    if override:
        return [part.replace("{root}", str(project_root)) for part in shlex.split(override)]
    # tools: one MCP tool per operation. The REPL interface only exposes the startup tools
    # (activate_project, initial_instructions, serena_repl). Do not open the dashboard; an unset
    # web_dashboard_open_on_launch opens a window every time an agent starts.
    return [
        "serena", "start-mcp-server",
        "--project", str(project_root),
        "--agent-interface", "tools",
        "--open-web-dashboard", "false",
    ]


def serena_available() -> bool:
    cmd = serena_command(Path("."))
    return bool(cmd) and shutil.which(cmd[0]) is not None
