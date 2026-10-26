from __future__ import annotations

from pathlib import Path

from ..project import DEFAULT_LOCAL_BASE_URL, Model
from .base import Adapter, AdapterError, TurnResult, total_tokens
from .cursor import (
    AUTO_VARIANTS,
    CursorAdapter,
    CursorCliError,
    absorb_delta,
    choose_turn_text,
    cursor_command,
    list_cursor_models,
    load_cursor_catalog,
    parse_model_listing,
    update_cursor_catalog,
)
from .local import LocalAdapter, LocalServerNotRunning, list_local_models


def make_adapter(model: Model, workspace: Path, mode: str) -> Adapter:
    if model.vendor == "cursor":
        return CursorAdapter(model.name, workspace, mode)
    if model.vendor == "openai":
        return LocalAdapter(model.name, model.base_url or DEFAULT_LOCAL_BASE_URL, model.api_key)
    raise AdapterError(f"unknown vendor {model.vendor!r}")


__all__ = [
    "Adapter",
    "AdapterError",
    "AUTO_VARIANTS",
    "CursorAdapter",
    "CursorCliError",
    "LocalAdapter",
    "LocalServerNotRunning",
    "TurnResult",
    "cursor_command",
    "list_cursor_models",
    "list_local_models",
    "load_cursor_catalog",
    "update_cursor_catalog",
    "make_adapter",
    "parse_model_listing",
    "total_tokens",
]
