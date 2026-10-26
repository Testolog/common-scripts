"""Live MCP connections through the official MCP Python SDK (pinned in pyproject).

* Streamable HTTP for ``type`` missing or ``http``; SSE for ``type: sse``.
* Only servers whose catalog status is ``connect`` (active in the project file) are opened.
* OAuth: when an active server answers 401, the SDK's ``OAuthClientProvider`` calls our
  redirect handler, which opens the system browser; a loopback listener receives the code.
  Tokens and the registered client live under ``$HOME/agentic/mcp-auth/<server_name>/``.
* Serena is a stdio subprocess started per agent, not taken from mcp.json.

The SDK is imported lazily so the rest of the client works without it.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import re
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any, Callable
from urllib.parse import parse_qs, urlsplit

from .mcp_catalog import CONNECT, SSE, McpCatalog, McpServer
from .serena import SERENA_SERVER, serena_command
from .state import MCP_AUTH_DIR, agentic_home

CALLBACK_HOST = "127.0.0.1"
CALLBACK_PORT = 33418
CALLBACK_PATH = "/callback"
# HTTP 400 or 500 ends the connection after this many answers. 401 generates OAuth instead.
CONNECT_LIMIT = 3
_HTTP_STATUS = re.compile(r"\b([45]\d{2})\b")

ErrorFn = Callable[[str, str], None]


def auth_dir(server_name: str) -> Path:
    safe = "".join(c if c.isalnum() or c in "-_." else "_" for c in server_name)
    path = agentic_home() / MCP_AUTH_DIR / safe
    path.mkdir(parents=True, exist_ok=True)
    return path


class FileTokenStorage:
    """``mcp.client.auth.TokenStorage`` backed by JSON files in the server's auth dir."""

    def __init__(self, server_name: str):
        self.dir = auth_dir(server_name)

    def _read(self, name: str) -> dict[str, Any] | None:
        try:
            return json.loads((self.dir / name).read_text())
        except (OSError, ValueError):
            return None

    def _write(self, name: str, data: dict[str, Any]) -> None:
        path = self.dir / name
        path.write_text(json.dumps(data, indent=2))
        path.chmod(0o600)

    async def get_tokens(self):
        from mcp.shared.auth import OAuthToken

        data = self._read("tokens.json")
        return OAuthToken.model_validate(data) if data else None

    async def set_tokens(self, tokens) -> None:
        self._write("tokens.json", tokens.model_dump(mode="json", exclude_none=True))

    async def get_client_info(self):
        from mcp.shared.auth import OAuthClientInformationFull

        data = self._read("client.json")
        return OAuthClientInformationFull.model_validate(data) if data else None

    async def set_client_info(self, client_info) -> None:
        self._write("client.json", client_info.model_dump(mode="json", exclude_none=True))


def _wait_for_callback(timeout: float = 300) -> tuple[str, str | None]:
    result: dict[str, Any] = {}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            parts = urlsplit(self.path)
            if parts.path != CALLBACK_PATH:
                self.send_response(404)
                self.end_headers()
                return
            query = parse_qs(parts.query)
            result["code"] = (query.get("code") or [None])[0]
            result["state"] = (query.get("state") or [None])[0]
            result["error"] = (query.get("error") or [None])[0]
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(b"<html><body>Login finished. You can close this tab.</body></html>")

        def log_message(self, *args):
            return

    server = HTTPServer((CALLBACK_HOST, CALLBACK_PORT), Handler)
    server.timeout = timeout
    try:
        server.handle_request()
    finally:
        server.server_close()
    if result.get("error") or not result.get("code"):
        raise RuntimeError(f"MCP login failed: {result.get('error') or 'no authorization code received'}")
    return result["code"], result.get("state")


def http_status(exc: BaseException) -> int | None:
    """Status code on an HTTP error, from ``status_code`` or a ``400``/``500`` in the message."""
    response = getattr(exc, "response", None)
    for obj in (exc, response):
        if obj is None:
            continue
        code = getattr(obj, "status_code", None)
        if isinstance(code, int):
            return code
    match = _HTTP_STATUS.search(str(exc))
    return int(match.group(1)) if match else None


def needs_authorization(exc: BaseException) -> bool:
    code = http_status(exc)
    if code in (401, 403):
        return True
    text = str(exc).lower()
    return "authoriz" in text or "unauthor" in text or "needsauth" in text or "authentication" in text


def connect_decision(exc: BaseException, failures: int, auth_generated: bool) -> str:
    """Next step after a failed MCP connect.

    ``authorize`` registers the OAuth client and opens the browser, once.
    ``retry`` is another attempt after HTTP 400 or 500.
    ``stop`` is the third 400 or 500; the server is not contacted again.
    ``fail`` raises the error.
    """
    code = http_status(exc)
    if code == 400 or (code is not None and 500 <= code <= 599):
        return "stop" if failures + 1 >= CONNECT_LIMIT else "retry"
    if needs_authorization(exc) and not auth_generated:
        return "authorize"
    return "fail"


def oauth_provider(server: McpServer):
    from mcp.client.auth import OAuthClientProvider
    from mcp.shared.auth import OAuthClientMetadata

    async def redirect_handler(url: str) -> None:
        webbrowser.open(url)

    async def callback_handler() -> tuple[str, str | None]:
        return await asyncio.to_thread(_wait_for_callback)

    metadata = OAuthClientMetadata(
        client_name="nvim-agentic",
        redirect_uris=[f"http://{CALLBACK_HOST}:{CALLBACK_PORT}{CALLBACK_PATH}"],
        grant_types=["authorization_code", "refresh_token"],
        response_types=["code"],
        token_endpoint_auth_method="none",
    )
    return OAuthClientProvider(
        server_url=server.url,
        client_metadata=metadata,
        storage=FileTokenStorage(server.name),
        redirect_handler=redirect_handler,
        callback_handler=callback_handler,
    )


def _result_text(result: Any) -> str:
    parts = []
    for item in getattr(result, "content", None) or []:
        text = getattr(item, "text", None)
        parts.append(text if text is not None else json.dumps(item.model_dump(mode="json")))
    text = "\n".join(parts)
    if getattr(result, "isError", False):
        return f"MCP tool error: {text}"
    return text


class McpManager:
    """Owns an asyncio loop on a background thread and keeps sessions open for the agent's life."""

    def __init__(
        self,
        catalog: McpCatalog,
        project_root: Path,
        on_error: ErrorFn | None = None,
        on_log: ErrorFn | None = None,
        serena: bool = True,
    ):
        self.catalog = catalog
        self.project_root = Path(project_root)
        self.on_error = on_error or (lambda name, msg: None)
        self.on_log = on_log or (lambda name, msg: None)
        self.serena = serena
        self.sessions: dict[str, Any] = {}
        self.tools: dict[str, list[dict[str, Any]]] = {}
        self.stopped: dict[str, str] = {}
        self._stack: contextlib.AsyncExitStack | None = None
        self._loop = asyncio.new_event_loop()
        self._thread = threading.Thread(target=self._loop.run_forever, name="mcp-loop", daemon=True)
        self._thread.start()

    def _run(self, coro, timeout: float | None = 600):
        return asyncio.run_coroutine_threadsafe(coro, self._loop).result(timeout)

    def _note(self, server: str, message: str) -> None:
        self.on_log(server, " ".join(str(message).split()))

    async def _open(self, name: str, transport_cm) -> None:
        from mcp import ClientSession

        assert self._stack is not None
        streams = await self._stack.enter_async_context(transport_cm)
        read, write = streams[0], streams[1]
        session = await self._stack.enter_async_context(ClientSession(read, write))
        await session.initialize()
        listed = await session.list_tools()
        self.sessions[name] = session
        self.tools[name] = [{"name": t.name, "description": t.description or ""} for t in listed.tools]

    async def _connect_url(self, server: McpServer) -> None:
        from mcp.client.sse import sse_client
        from mcp.client.streamable_http import streamablehttp_client

        if server.name in self.stopped:
            self._note(server.name, self.stopped[server.name])
            raise RuntimeError(self.stopped[server.name])
        failures = 0
        auth_generated = False
        self._note(server.name, "connecting")
        while True:
            auth = oauth_provider(server)
            if server.transport == SSE:
                cm = sse_client(server.url, headers=server.headers or None, auth=auth)
            else:
                cm = streamablehttp_client(server.url, headers=server.headers or None, auth=auth)
            try:
                await self._open(server.name, cm)
                tools = ", ".join(item["name"] for item in self.tools.get(server.name, [])) or "none"
                self._note(server.name, f"connected; tools: {tools}")
                return
            except Exception as exc:
                decision = connect_decision(exc, failures, auth_generated)
                if decision == "authorize":
                    auth_generated = True
                    message = "authorization required; generating the OAuth client and opening the browser"
                    self._note(server.name, message)
                    self.on_error(server.name, message)
                    continue
                if decision == "retry":
                    failures += 1
                    self._note(server.name, f"HTTP 400 or 500, attempt {failures} of {CONNECT_LIMIT}: {exc}")
                    continue
                if decision == "stop":
                    message = f"stopped connecting after {CONNECT_LIMIT} responses of 400 or 500: {exc}"
                    self.stopped[server.name] = message
                    self._note(server.name, message)
                    raise RuntimeError(message) from exc
                self._note(server.name, f"connect failed: {exc}")
                raise

    async def _connect_serena(self) -> None:
        from mcp.client.stdio import StdioServerParameters, stdio_client

        cmd = serena_command(self.project_root)
        params = StdioServerParameters(command=cmd[0], args=cmd[1:], cwd=str(self.project_root))
        self._note(SERENA_SERVER, "connecting")
        await self._open(SERENA_SERVER, stdio_client(params))
        tools = ", ".join(item["name"] for item in self.tools.get(SERENA_SERVER, [])) or "none"
        self._note(SERENA_SERVER, f"connected; tools: {tools}")

    async def _connect_all(self) -> dict[str, str]:
        self._stack = contextlib.AsyncExitStack()
        status: dict[str, str] = {}
        for server in self.catalog.servers:
            if server.status != CONNECT:
                status[server.name] = server.status
                continue
            try:
                await self._connect_url(server)
                status[server.name] = "connected"
            except Exception as exc:
                status[server.name] = f"error: {exc}"
                self.on_error(server.name, str(exc))
        if self.serena:
            try:
                await self._connect_serena()
                status[SERENA_SERVER] = "connected"
            except Exception as exc:
                status[SERENA_SERVER] = f"error: {exc}"
                self._note(SERENA_SERVER, f"connect failed: {exc}")
                self.on_error(SERENA_SERVER, str(exc))
        return status

    def connect_all(self) -> dict[str, str]:
        """Connect active url servers and Serena. Returns name -> status text."""
        try:
            import mcp  # noqa: F401
        except Exception as exc:
            message = f"MCP SDK unavailable: {exc}"
            self._note("mcp", message)
            return {"mcp": message}
        return self._run(self._connect_all())

    async def _call(self, server: str, tool: str, arguments: dict[str, Any]) -> str:
        session = self.sessions.get(server)
        if session is None:
            return f"MCP server {server!r} is not connected."
        return _result_text(await session.call_tool(tool, arguments))

    def call_tool(self, server: str, tool: str, arguments: dict[str, Any]) -> str:
        if server in self.stopped:
            self._note(server, self.stopped[server])
            return self.stopped[server]
        self._note(server, f"call {tool}")
        try:
            text = self._run(self._call(server, tool, arguments))
        except Exception as exc:
            self.on_error(server, str(exc))
            self._note(server, f"call {tool} failed: {exc}")
            return f"MCP tool {server}/{tool} failed: {exc}"
        shown = text if len(text) <= 500 else text[:500] + "…"
        self._note(server, f"call {tool} result: {shown}")
        return text

    def close(self) -> None:
        if self._stack is not None:
            with contextlib.suppress(Exception):
                self._run(self._stack.aclose(), timeout=10)
        self._loop.call_soon_threadsafe(self._loop.stop)


def authorize(server: McpServer, project_root: Path, on_error: ErrorFn | None = None) -> str:
    """Generate the OAuth client for `server` and open the browser. Returns the connect status."""
    from .mcp_catalog import HTTP, McpCatalog

    forced = McpServer(
        server.name,
        CONNECT,
        server.transport or HTTP,
        server.url,
        dict(server.headers),
        "",
        True,
    )
    manager = McpManager(McpCatalog(servers=[forced]), project_root, on_error=on_error, serena=False)
    try:
        return manager.connect_all().get(server.name, "")
    finally:
        manager.close()


def split_mcp_call(function: str, arguments: dict[str, Any]) -> tuple[str, str, dict[str, Any]]:
    """Project tool ``function`` is ``server`` or ``server/tool``.

    With bare ``server`` the model passes ``{"tool": name, "arguments": {...}}``.
    """
    if "/" in function:
        server, tool = function.split("/", 1)
        return server, tool, arguments
    tool = arguments.get("tool")
    if not tool:
        raise ValueError(f"MCP call to {function!r} needs a 'tool' name")
    return function, tool, dict(arguments.get("arguments") or {})
