"""Server-sent event parsing for OpenAI-compatible ``/chat/completions`` streams."""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Iterable, Iterator


@dataclass
class SseChunk:
    text: str = ""
    done: bool = False
    usage: dict[str, Any] | None = None
    error: str | None = None


def parse_sse_line(line: str | bytes) -> SseChunk | None:
    """Parse one SSE line. Returns None for blank lines, comments, and non-data fields."""
    if isinstance(line, bytes):
        line = line.decode("utf-8", errors="replace")
    line = line.rstrip("\r\n")
    if not line.startswith("data:"):
        return None
    payload = line[5:].strip()
    if not payload:
        return None
    if payload == "[DONE]":
        return SseChunk(done=True)
    try:
        obj = json.loads(payload)
    except ValueError:
        return SseChunk(error=f"unparseable SSE data: {payload[:200]}")
    if not isinstance(obj, dict):
        return None
    if "error" in obj:
        err = obj["error"]
        return SseChunk(error=err.get("message") if isinstance(err, dict) else str(err))
    text = ""
    for choice in obj.get("choices") or []:
        delta = choice.get("delta") or {}
        content = delta.get("content")
        if isinstance(content, str):
            text += content
    usage = obj.get("usage") if isinstance(obj.get("usage"), dict) else None
    return SseChunk(text=text, usage=usage)


def iter_sse(lines: Iterable[str | bytes]) -> Iterator[SseChunk]:
    """Yield parsed chunks and stop after ``data: [DONE]``."""
    for line in lines:
        chunk = parse_sse_line(line)
        if chunk is None:
            continue
        if chunk.done:
            return
        yield chunk


def iter_sse_deltas(lines: Iterable[str | bytes]) -> Iterator[str]:
    for chunk in iter_sse(lines):
        if chunk.text:
            yield chunk.text
