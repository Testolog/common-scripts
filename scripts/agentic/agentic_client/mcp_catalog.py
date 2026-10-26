"""Build the MCP connection plan from ``~/.cursor/mcp.json`` plus the project's activation flags.

Pure parsing: nothing here opens a connection or a browser.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

CONNECT = "connect"          # url entry, active in the project file
INACTIVE = "inactive"        # url entry, isActive false or missing, or absent from project file
UNSUPPORTED = "unsupported"  # command-only entry or unknown type; never spawned
MISSING = "missing"          # named in project file, absent from mcp.json

HTTP = "http"
SSE = "sse"


@dataclass
class McpServer:
    name: str
    status: str
    transport: str | None = None
    url: str | None = None
    headers: dict[str, str] = field(default_factory=dict)
    reason: str = ""
    active: bool = False

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "status": self.status,
            "transport": self.transport,
            "url": self.url,
            "reason": self.reason,
            "active": self.active,
        }


@dataclass
class McpCatalog:
    servers: list[McpServer] = field(default_factory=list)
    error: str | None = None
    path: str | None = None

    def to_connect(self) -> list[McpServer]:
        return [s for s in self.servers if s.status == CONNECT]

    def by_name(self, name: str) -> McpServer | None:
        return next((s for s in self.servers if s.name == name), None)


def default_mcp_json() -> Path:
    return Path(os.environ.get("AGENTIC_MCP_JSON") or Path.home() / ".cursor" / "mcp.json")


def classify(name: str, config: Any, active: bool) -> McpServer:
    if not isinstance(config, dict):
        return McpServer(name, UNSUPPORTED, reason="config is not an object", active=active)
    url = config.get("url")
    if not url:
        if config.get("command"):
            return McpServer(name, UNSUPPORTED, reason="command-only entry; stdio servers are not spawned", active=active)
        return McpServer(name, UNSUPPORTED, reason="no url", active=active)
    kind = config.get("type")
    if kind in (None, "", HTTP, "streamable-http", "streamableHttp"):
        transport = HTTP
    elif kind == SSE:
        transport = SSE
    else:
        return McpServer(name, UNSUPPORTED, url=url, reason=f"unsupported type {kind!r}", active=active)
    headers = {str(k): os.path.expandvars(str(v)) for k, v in (config.get("headers") or {}).items()}
    status = CONNECT if active else INACTIVE
    reason = "" if active else "isActive is false or missing in .nvim_project.json"
    return McpServer(name, status, transport, url, headers, reason, active)


def parse_catalog(text: str, activation: dict[str, bool]) -> McpCatalog:
    """Parse mcp.json text. A parse error connects nothing from that file."""
    try:
        data = json.loads(text)
    except ValueError as exc:
        return McpCatalog(error=f"mcp.json does not parse: {exc}")
    if not isinstance(data, dict) or not isinstance(data.get("mcpServers", {}), dict):
        return McpCatalog(error="mcp.json: mcpServers must be an object of name -> config")
    servers = [
        classify(name, config, activation.get(name) is True)
        for name, config in (data.get("mcpServers") or {}).items()
    ]
    known = {s.name for s in servers}
    servers += [
        McpServer(n, MISSING, reason="not declared in mcp.json", active=activation.get(n) is True)
        for n in activation
        if n not in known
    ]
    return McpCatalog(servers=servers)


def load_catalog(activation: dict[str, bool], path: Path | None = None) -> McpCatalog:
    path = path or default_mcp_json()
    try:
        text = path.read_text()
    except FileNotFoundError:
        return McpCatalog(
            path=str(path),
            servers=[McpServer(n, MISSING, reason="no mcp.json", active=activation.get(n) is True) for n in activation],
        )
    except OSError as exc:
        return McpCatalog(error=f"{path}: {exc}", path=str(path))
    catalog = parse_catalog(text, activation)
    catalog.path = str(path)
    if catalog.error:
        catalog.error = f"{path}: {catalog.error}"
    return catalog
