"""Read the project's ``.nvim_project.json`` as stored.

Prompts, skills, tools, models, and MCP activation come only from this file.
The system project file is never merged over it at runtime.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .state import PROJECT_FILE

DEFAULT_LOCAL_BASE_URL = "http://127.0.0.1:11434/v1"
CURSOR_DEFAULT_CONTEXT_LIMIT = 200000
VENDORS = ("cursor", "openai")


class ProjectError(ValueError):
    pass


@dataclass
class Entry:
    name: str
    path: Path
    source: str  # "system" | "project"


@dataclass
class Tool:
    name: str
    function: str
    description: str = ""
    kind: str = "shell"
    mutates: bool | None = None
    source: str = "project"

    @property
    def is_mutating(self) -> bool:
        """Missing ``mutates`` means mutating."""
        return self.mutates is not False


@dataclass
class Model:
    name: str
    vendor: str
    context_limit: int
    base_url: str | None = None
    api_key: str | None = None
    extra: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        out: dict[str, Any] = {"name": self.name, "vendor": self.vendor, "context_limit": self.context_limit}
        if self.base_url:
            out["base_url"] = self.base_url
        if self.api_key:
            out["api_key"] = self.api_key
        return out


def load_project(root: str | os.PathLike[str]) -> dict[str, Any]:
    path = Path(root) / PROJECT_FILE
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text())
    except ValueError as exc:
        raise ProjectError(f"{path}: {exc}") from exc
    if not isinstance(data, dict):
        raise ProjectError(f"{path}: top level must be an object")
    return data


def resolve_entry_path(raw: str, root: Path, source: str) -> Path:
    """Absolute paths (including copied ``$COMMON_SCRIPT/...`` paths) stay as stored.

    Relative paths added by the project resolve under the project root. A relative
    system entry resolves under ``$COMMON_SCRIPT`` when that file exists there.
    """
    expanded = os.path.expandvars(os.path.expanduser(raw))
    path = Path(expanded)
    if path.is_absolute():
        return path
    if source == "system":
        common = os.environ.get("COMMON_SCRIPT")
        if common and (Path(common) / path).exists():
            return Path(common) / path
    return root / path


def _entries(data: dict[str, Any], key: str, source: str, root: Path) -> list[Entry]:
    out: list[Entry] = []
    for item in data.get(key) or []:
        if isinstance(item, dict) and item.get("name") and item.get("path"):
            out.append(Entry(item["name"], resolve_entry_path(item["path"], root, source), source))
    return out


def prompt_entries(data: dict[str, Any], root: Path) -> list[Entry]:
    """``system_prompt`` then ``project_prompt``."""
    return _entries(data, "system_prompt", "system", root) + _entries(data, "project_prompt", "project", root)


def skill_entries(data: dict[str, Any], root: Path) -> list[Entry]:
    """``system_skills`` then ``project_skills``."""
    return _entries(data, "system_skills", "system", root) + _entries(data, "project_skills", "project", root)


def select(entries: list[Entry], names: list[str] | None) -> list[Entry]:
    """``None`` selects all, preserving file order."""
    if names is None:
        return list(entries)
    wanted = set(names)
    return [e for e in entries if e.name in wanted]


def read_entry_text(entry: Entry) -> str:
    """A file is read as-is. A folder contributes ``SKILL.md`` or else every ``*.md`` in order."""
    path = entry.path
    if path.is_file():
        return path.read_text()
    if path.is_dir():
        skill = path / "SKILL.md"
        files = [skill] if skill.is_file() else sorted(path.rglob("*.md"))
        return "\n\n".join(f.read_text() for f in files)
    return f"(missing: {path})"


def agent_create_tool() -> Tool:
    """Always available, including on project files written before this tool existed.

    ``mutates`` is false: it does not edit the project. Ask mode uses it to spawn an Edit agent.
    """
    script = Path(__file__).resolve().parents[3] / "system_project" / "system_function" / "agent_create.sh"
    return Tool(
        name="agent_create",
        function=str(script),
        description=(
            "Spawn another agent for this project. Does not edit the project. "
            "In Ask mode, call this instead of refusing a change or telling the user to switch mode. "
            "Arguments: --message <instruction> [--name <name>] [--mode edit|ask] [--model <model>] [--manager <manager>]. "
            "Default mode is edit. The new agent runs on its own; report its agent id."
        ),
        kind="shell",
        mutates=False,
        source="system",
    )


def agent_rename_tool() -> Tool:
    """Always available. One call renames one agent of this project; it does not edit the project."""
    script = Path(__file__).resolve().parents[3] / "system_project" / "system_function" / "agent_rename.sh"
    return Tool(
        name="agent_rename",
        function=str(script),
        description=(
            "Rename one agent of this project. Does not edit the project, so Ask mode may call it. "
            "One call renames one agent. Arguments: --agent <agent id or unique name> --name <new name>. "
            "Use the agent id from the system message to rename yourself. "
            "A name that matches more than one agent in this project is refused; pass the agent id."
        ),
        kind="shell",
        mutates=False,
        source="system",
    )


def tools(data: dict[str, Any]) -> list[Tool]:
    out: list[Tool] = []
    for key, source in (("system_tools", "system"), ("project_tools", "project")):
        for item in data.get(key) or []:
            if not isinstance(item, dict) or not item.get("name") or not item.get("function"):
                continue
            mutates = item.get("mutates")
            out.append(
                Tool(
                    name=item["name"],
                    function=item["function"],
                    description=item.get("description", ""),
                    kind=item.get("kind") or "shell",
                    mutates=mutates if isinstance(mutates, bool) else None,
                    source=source,
                )
            )
    for builtin in (agent_create_tool(), agent_rename_tool()):
        if not any(tool.name == builtin.name for tool in out):
            out.append(builtin)
    return out


def parse_model(item: dict[str, Any]) -> Model:
    name = item.get("name")
    vendor = item.get("vendor")
    if not name or vendor not in VENDORS:
        raise ProjectError(f"model needs name and vendor in {VENDORS}: {item!r}")
    base_url = item.get("base_url")
    if vendor == "openai" and not base_url:
        raise ProjectError(f"model {name!r}: base_url is required for vendor openai")
    if vendor == "cursor":
        base_url = None
    limit = item.get("context_limit") or (CURSOR_DEFAULT_CONTEXT_LIMIT if vendor == "cursor" else 0)
    extra = {k: v for k, v in item.items() if k not in ("name", "vendor", "context_limit", "base_url", "api_key")}
    return Model(name, vendor, int(limit), base_url, item.get("api_key"), extra)


def models(data: dict[str, Any]) -> list[Model]:
    out = []
    for item in data.get("models") or []:
        if isinstance(item, dict):
            try:
                out.append(parse_model(item))
            except ProjectError:
                continue
    return out


def mcp_activation(data: dict[str, Any]) -> dict[str, bool]:
    """``mcp_servers[]`` of ``{name, isActive}``. Missing or non-true isActive is off."""
    out: dict[str, bool] = {}
    for item in data.get("mcp_servers") or []:
        if isinstance(item, dict) and item.get("name"):
            out[item["name"]] = item.get("isActive") is True
    return out


def build_system_preamble(
    root: Path,
    data: dict[str, Any],
    prompt_names: list[str] | None,
    skill_names: list[str] | None,
    extra: str = "",
) -> str:
    parts: list[str] = []
    for entry in select(prompt_entries(data, root), prompt_names):
        parts.append(f"<!-- prompt: {entry.name} -->\n{read_entry_text(entry).strip()}")
    for entry in select(skill_entries(data, root), skill_names):
        parts.append(f"<!-- skill: {entry.name} -->\n{read_entry_text(entry).strip()}")
    if extra:
        parts.append(extra.strip())
    return "\n\n".join(parts)
