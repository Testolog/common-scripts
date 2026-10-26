"""OpenAI-compatible local HTTP adapter (Ollama, LM Studio, llama-server, ...).

``vendor: openai`` means this wire protocol, not platform.openai.com:

* ``POST {base_url}/chat/completions`` with ``{model, messages, stream: true}``
* ``GET {base_url}/models`` for names
* ``Authorization: Bearer`` only when ``api_key`` is set

Pause and stop abort the in-flight request; resume re-sends the transcript.
"""

from __future__ import annotations

import http.client
import json
import socket
import threading
from typing import Any
from urllib.parse import urlsplit

from ..project import DEFAULT_LOCAL_BASE_URL
from ..sse import parse_sse_line
from .base import Adapter, AdapterError, EmitFn, TurnResult


class LocalServerNotRunning(AdapterError):
    def __init__(self, base_url: str):
        super().__init__(f"local server is not running at {base_url}")
        self.base_url = base_url


def _connection(base_url: str, timeout: float) -> tuple[http.client.HTTPConnection, str]:
    parts = urlsplit(base_url)
    if parts.scheme not in ("http", "https") or not parts.hostname:
        raise AdapterError(f"invalid base_url {base_url!r}")
    cls = http.client.HTTPSConnection if parts.scheme == "https" else http.client.HTTPConnection
    conn = cls(parts.hostname, parts.port, timeout=timeout)
    return conn, parts.path.rstrip("/")


def _headers(api_key: str | None, stream: bool = False) -> dict[str, str]:
    headers = {"Content-Type": "application/json", "Accept": "text/event-stream" if stream else "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    return headers


def list_local_models(base_url: str = DEFAULT_LOCAL_BASE_URL, api_key: str | None = None, timeout: float = 5) -> list[str]:
    """``GET {base_url}/models`` -> model ids. Raises LocalServerNotRunning when nothing listens."""
    conn, prefix = _connection(base_url, timeout)
    try:
        conn.request("GET", f"{prefix}/models", headers=_headers(api_key))
        resp = conn.getresponse()
        body = resp.read()
    except (ConnectionRefusedError, socket.timeout, OSError) as exc:
        if isinstance(exc, (ConnectionRefusedError, socket.timeout)) or "refused" in str(exc).lower():
            raise LocalServerNotRunning(base_url) from exc
        raise AdapterError(f"{base_url}: {exc}") from exc
    finally:
        conn.close()
    if resp.status != 200:
        raise AdapterError(f"GET {base_url}/models -> HTTP {resp.status}: {body[:300]!r}")
    data = json.loads(body or b"{}")
    items = data.get("data") or data.get("models") or []
    names = []
    for item in items:
        if isinstance(item, dict):
            name = item.get("id") or item.get("name") or item.get("model")
            if name:
                names.append(name)
        elif isinstance(item, str):
            names.append(item)
    return names


class LocalAdapter(Adapter):
    resume_reissues = True

    def __init__(self, model: str, base_url: str = DEFAULT_LOCAL_BASE_URL, api_key: str | None = None, timeout: float = 600):
        self.model = model
        self.base_url = base_url
        self.api_key = api_key
        self.timeout = timeout
        self._conn: http.client.HTTPConnection | None = None
        self._aborted = threading.Event()
        self._lock = threading.Lock()

    def request_body(self, system: str, messages: list[dict[str, str]]) -> dict[str, Any]:
        full = ([{"role": "system", "content": system}] if system else []) + list(messages)
        return {"model": self.model, "messages": full, "stream": True}

    def run_turn(self, system: str, messages: list[dict[str, str]], emit: EmitFn) -> TurnResult:
        self._aborted.clear()
        conn, prefix = _connection(self.base_url, self.timeout)
        with self._lock:
            self._conn = conn
        text = ""
        usage = None
        try:
            body = json.dumps(self.request_body(system, messages))
            try:
                conn.request("POST", f"{prefix}/chat/completions", body=body, headers=_headers(self.api_key, True))
                resp = conn.getresponse()
            except ConnectionRefusedError as exc:
                raise LocalServerNotRunning(self.base_url) from exc
            if resp.status != 200:
                detail = resp.read()[:500].decode("utf-8", "replace")
                return TurnResult(error=f"HTTP {resp.status} from {self.base_url}: {detail}")
            while True:
                line = resp.readline()
                if not line:
                    break
                chunk = parse_sse_line(line)
                if chunk is None:
                    continue
                if chunk.done:
                    break
                if chunk.error:
                    return TurnResult(text=text, error=chunk.error, usage=usage)
                if chunk.usage:
                    usage = chunk.usage
                    emit({"type": "usage", "usage": usage})
                if chunk.text:
                    text += chunk.text
                    emit({"type": "delta", "text": chunk.text})
        except LocalServerNotRunning as exc:
            return TurnResult(error=str(exc))
        except (OSError, http.client.HTTPException, ValueError) as exc:
            if self._aborted.is_set():
                return TurnResult(text=text, aborted=True, usage=usage)
            return TurnResult(text=text, error=f"{type(exc).__name__}: {exc}", usage=usage)
        finally:
            with self._lock:
                self._conn = None
            conn.close()
        return TurnResult(text=text, aborted=self._aborted.is_set(), usage=usage)

    def _abort(self) -> None:
        self._aborted.set()
        with self._lock:
            conn = self._conn
        if conn is not None and conn.sock is not None:
            try:
                conn.sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            conn.close()

    def pause(self) -> None:
        self._abort()

    def resume(self) -> None:
        """Nothing to continue; the supervisor re-sends the transcript as a new request."""

    def stop(self) -> None:
        self._abort()
