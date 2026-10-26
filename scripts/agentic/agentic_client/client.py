"""Public client interface: start, stream events, pause, resume, stop (plus kill/delete/rename/move).

Every call is addressed by agent id and works from a fresh process, so Neovim can
reattach after a restart. Commands go through ``inbox.jsonl``; events come from
``events.jsonl``.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any, Iterator

from . import project as proj
from . import state
from .adapters import LocalServerNotRunning, load_cursor_catalog, list_local_models
from .adapters.base import AdapterError
from .mcp_catalog import load_catalog
from .state import INBOX, Agent
from .supervisor import spawn_supervisor


def _command(agent: Agent, cmd: dict[str, Any]) -> None:
    with agent.path(INBOX).open("a") as fh:
        fh.write(json.dumps(cmd) + "\n")


def resolve_model(project_root: Path, model: str | dict[str, Any]) -> dict[str, Any]:
    """A dict is validated as-is. A name is looked up in the project ``models``; otherwise it
    is treated as a Cursor CLI model with the default 200000 context limit."""
    if isinstance(model, dict):
        return proj.parse_model(model).to_dict()
    for m in proj.models(proj.load_project(project_root)):
        if m.name == model:
            return m.to_dict()
    return proj.parse_model({"name": model, "vendor": "cursor"}).to_dict()


def start(
    project_root: str | os.PathLike[str],
    *,
    name: str,
    mode: str = "ask",
    model: str | dict[str, Any] = "auto",
    manager: str = state.DEFAULT_MANAGER,
    prompts: list[str] | None = None,
    skills: list[str] | None = None,
    message: str | None = None,
) -> Agent:
    """Create the agent state and launch its detached supervisor. ``None`` selects all prompts/skills."""
    if mode.lower() not in ("ask", "edit"):
        raise ValueError("mode must be ask or edit")
    root = state.find_project_root(project_root)
    agent = state.create_agent(
        root,
        name=name,
        mode=mode,
        model=resolve_model(root, model),
        manager=manager,
        prompts=prompts,
        skills=skills,
    )
    if message:
        _command(agent, {"cmd": "send", "text": message})
    spawn_supervisor(agent)
    return agent


def attach(agent_id: str) -> Agent:
    """Reattach by agent id (walks ``$HOME/agentic`` for ``meta.json``)."""
    return state.find_agent(agent_id)


def events(agent_id: str, offset: int = 0, follow: bool = True, poll: float = 0.2) -> Iterator[dict[str, Any]]:
    """Yield events from ``offset``. With ``follow`` keep tailing while the supervisor lives."""
    agent = attach(agent_id)
    while True:
        batch, offset = state.read_events(agent, offset)
        for event in batch:
            event["_offset"] = offset
            yield event
        if not follow:
            return
        if not batch and not agent.is_alive():
            batch, offset = state.read_events(agent, offset)
            yield from batch
            return
        time.sleep(poll)


def send(agent_id: str, text: str) -> None:
    _command(attach(agent_id), {"cmd": "send", "text": text})


def pause(agent_id: str) -> None:
    _command(attach(agent_id), {"cmd": "pause"})


def resume(agent_id: str) -> None:
    _command(attach(agent_id), {"cmd": "resume"})


def stop(agent_id: str) -> None:
    """AgentStop: ask the supervisor to finish."""
    _command(attach(agent_id), {"cmd": "stop"})


def restart(agent_id: str) -> Agent:
    """AgentStart: launch the supervisor again for an agent that already exists."""
    agent = attach(agent_id)
    if agent.is_read_only():
        raise ValueError(f"agent {agent.id} is read-only after handoff")
    if agent.is_alive():
        return agent
    spawn_supervisor(agent)
    return agent


def kill(agent_id: str) -> bool:
    """AgentKill: terminate the supervisor immediately. The transcript stays."""
    return state.kill_agent(attach(agent_id))


def delete(agent_id: str) -> None:
    """AgentDelete: kill if needed and remove the agent's directory."""
    state.delete_agent(attach(agent_id))


def rename(agent_id: str, name: str) -> Agent:
    return state.rename_agent(attach(agent_id), name)


def rename_project_agent(project_root: str | os.PathLike[str], ref: str, name: str) -> dict[str, Any]:
    """Rename one agent of this project. ``ref`` is that agent's id, or its name when unique here."""
    cleaned = " ".join(str(name).split())
    if not cleaned or "/" in cleaned or len(cleaned) > 200:
        raise ValueError("agent name must be one line, without '/', and at most 200 characters")
    root = Path(project_root).expanduser().resolve()
    needle = str(ref).strip()
    if not needle:
        raise ValueError("agent id or name is required")
    in_project: list[Agent] = []
    seen_elsewhere = False
    for agent in state.iter_agents():
        try:
            same = Path(agent.meta.get("project_root", "")).resolve() == root
        except OSError:
            same = False
        if agent.id == needle and not same:
            seen_elsewhere = True
        if same:
            in_project.append(agent)
    match = next((agent for agent in in_project if agent.id == needle), None)
    if match is None:
        named = [agent for agent in in_project if agent.meta.get("name") == needle]
        if len(named) == 1:
            match = named[0]
        elif len(named) > 1:
            ids = ", ".join(agent.id for agent in named)
            raise ValueError(f"more than one agent named {needle!r} in this project: {ids}")
        elif seen_elsewhere:
            raise ValueError(f"agent {needle!r} is not in this project")
        else:
            raise ValueError(f"no agent {needle!r} in this project")
    state.rename_agent(match, cleaned)
    return {"ok": True, "agent_id": match.id, "name": cleaned}


def move(agent_id: str, manager: str) -> Agent:
    return state.move_agent(attach(agent_id), manager)


def allow_read(agent_id: str, directory: str) -> dict[str, Any]:
    """Grant this agent read access to one extra directory. The user command is the only caller."""
    agent = attach(agent_id)
    path = Path(directory).expanduser().resolve()
    if not path.is_dir():
        raise ValueError(f"not a directory: {path}")
    agent.reload()
    roots = [item for item in (agent.meta.get("extra_read_roots") or []) if isinstance(item, str)]
    text = str(path)
    if text not in roots:
        roots.append(text)
    agent.meta["extra_read_roots"] = roots
    agent.save()
    return {"agent_id": agent.id, "extra_read_roots": roots}


def attach_nvim(agent_id: str, nvim_pid: int) -> None:
    """Tell the supervisor Neovim is attached and can answer ``lsp_request`` events."""
    _command(attach(agent_id), {"cmd": "attach", "pid": nvim_pid})


def detach_nvim(agent_id: str) -> None:
    _command(attach(agent_id), {"cmd": "detach"})


def lsp_result(agent_id: str, request_id: str, text: str) -> None:
    _command(attach(agent_id), {"cmd": "lsp_result", "id": request_id, "text": text})


def list_agents(project_root: str | os.PathLike[str] | None = None, running_only: bool = False) -> list[dict[str, Any]]:
    """Agents for one project+branch, or all agents when ``project_root`` is None."""
    root = state.find_project_root(project_root) if project_root else None
    out = []
    for agent in state.list_agents(root, running_only):
        out.append({**agent.meta, "dir": str(agent.dir), "alive": agent.is_alive()})
    return out


def list_models(project_root: str | os.PathLike[str]) -> dict[str, Any]:
    """Model names for a create panel: project file, the stored Cursor catalog, and each local base_url.

    The Cursor catalog is ``$COMMON_SCRIPT/system_project/cursor_models.json``. It is not refreshed here.
    """
    root = state.find_project_root(project_root)
    project_models = proj.models(proj.load_project(root))
    result: dict[str, Any] = {"project": [m.to_dict() for m in project_models], "cursor": [], "local": {}, "errors": {}}
    result["cursor"] = load_cursor_catalog()
    for m in project_models:
        if m.vendor != "openai" or not m.base_url or m.base_url in result["local"]:
            continue
        try:
            result["local"][m.base_url] = list_local_models(m.base_url, m.api_key)
        except LocalServerNotRunning as exc:
            result["local"][m.base_url] = []
            result["errors"][m.base_url] = str(exc)
        except AdapterError as exc:
            result["local"][m.base_url] = []
            result["errors"][m.base_url] = str(exc)
    return result


def update_cursor_models() -> dict[str, Any]:
    """Refresh ``cursor_models.json`` from the Cursor CLI. This is the only path that asks Cursor."""
    from .adapters import update_cursor_catalog

    return update_cursor_catalog()


def mcp_status(project_root: str | os.PathLike[str]) -> dict[str, Any]:
    """The MCP plan for this project, without connecting or opening a browser."""
    root = state.find_project_root(project_root)
    catalog = load_catalog(proj.mcp_activation(proj.load_project(root)))
    return {"path": catalog.path, "error": catalog.error, "servers": [s.to_dict() for s in catalog.servers]}
