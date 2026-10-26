"""Agent state on disk.

Layout::

    $HOME/agentic/<project_name>/<branch>/<manager>/<agent_id>/
      meta.json  transcript.md  log  supervisor.pid
      events.jsonl  inbox.jsonl          (reattach channel)

Agents are discovered by walking for ``meta.json``; the directory depth carries
no meaning. ``meta.json`` is the source of truth for project root, branch,
manager, and agent id.
"""

from __future__ import annotations

import json
import os
import shutil
import signal
import stat
import subprocess
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator

PROJECT_FILE = ".nvim_project.json"
DEFAULT_MANAGER = "default"
NOGIT = "nogit"
DETACHED = "detached"
MCP_AUTH_DIR = "mcp-auth"

META = "meta.json"
TRANSCRIPT = "transcript.md"
LOG = "log"
MCP_LOG = "mcp.log"
PID = "supervisor.pid"
EVENTS = "events.jsonl"
INBOX = "inbox.jsonl"


def agentic_home() -> Path:
    override = os.environ.get("AGENTIC_HOME")
    if override:
        return Path(override).expanduser()
    return Path.home() / "agentic"


def find_project_root(start: str | os.PathLike[str]) -> Path:
    """Walk upward for ``.nvim_project.json``; fall back to ``start``."""
    start_path = Path(start).expanduser().resolve()
    for candidate in [start_path, *start_path.parents]:
        if (candidate / PROJECT_FILE).is_file():
            return candidate
    return start_path


def project_name(root: str | os.PathLike[str]) -> str:
    root_path = Path(root)
    try:
        data = json.loads((root_path / PROJECT_FILE).read_text())
        name = data.get("name") if isinstance(data, dict) else None
        if isinstance(name, str) and name.strip():
            return name.strip()
    except (OSError, ValueError):
        pass
    return root_path.resolve().name


def git_branch(root: str | os.PathLike[str]) -> str:
    """``git rev-parse --abbrev-ref HEAD``; ``nogit`` outside git, ``detached`` on detached HEAD."""
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=str(root),
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return NOGIT
    if proc.returncode != 0:
        return NOGIT
    branch = proc.stdout.strip()
    if not branch:
        return NOGIT
    if branch == "HEAD":
        return DETACHED
    return branch


def _segments(value: str) -> list[str]:
    return [s for s in value.replace("\\", "/").split("/") if s not in ("", ".", "..")]


def branch_dir(project: str, branch: str, home: Path | None = None) -> Path:
    """Directory for one project+branch. ``feature/foo`` nests as ``feature/foo``."""
    base = (home or agentic_home()) / project
    return base.joinpath(*(_segments(branch) or [NOGIT]))


def agent_dir(project: str, branch: str, manager: str, agent_id: str, home: Path | None = None) -> Path:
    return branch_dir(project, branch, home).joinpath(*(_segments(manager) or [DEFAULT_MANAGER]), agent_id)


def state_dir_for_root(root: str | os.PathLike[str], home: Path | None = None) -> Path:
    return branch_dir(project_name(root), git_branch(root), home)


def new_agent_id() -> str:
    return time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6]


def now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


@dataclass
class Agent:
    """One agent directory plus its parsed ``meta.json``."""

    dir: Path
    meta: dict[str, Any]

    @property
    def id(self) -> str:
        return self.meta["agent_id"]

    @property
    def project_root(self) -> Path:
        return Path(self.meta["project_root"])

    @property
    def manager_dir(self) -> Path:
        return self.dir.parent

    def path(self, name: str) -> Path:
        return self.dir / name

    def save(self) -> None:
        self.meta["updated_at"] = now_iso()
        write_json_atomic(self.path(META), self.meta)

    def reload(self) -> "Agent":
        self.meta = read_meta(self.dir)
        return self

    def pid(self) -> int | None:
        try:
            return int(self.path(PID).read_text().strip())
        except (OSError, ValueError):
            return None

    def is_alive(self) -> bool:
        return pid_alive(self.pid())

    def is_read_only(self) -> bool:
        return bool(self.meta.get("read_only"))


def write_json_atomic(path: Path, data: Any) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    os.replace(tmp, path)


def read_meta(directory: Path) -> dict[str, Any]:
    return json.loads((directory / META).read_text())


def pid_alive(pid: int | None) -> bool:
    if not pid or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def iter_agents(root: Path | None = None) -> Iterator[Agent]:
    """Yield every agent below ``root`` (default ``$HOME/agentic``), at any depth."""
    base = root or agentic_home()
    if not base.is_dir():
        return
    for dirpath, dirnames, filenames in os.walk(base):
        current = Path(dirpath)
        if current == base and MCP_AUTH_DIR in dirnames:
            dirnames.remove(MCP_AUTH_DIR)
        dirnames.sort()
        if META in filenames:
            try:
                yield Agent(current, read_meta(current))
            except (OSError, ValueError, KeyError):
                continue


def find_agent(agent_id: str, root: Path | None = None) -> Agent:
    for agent in iter_agents(root):
        if agent.meta.get("agent_id") == agent_id:
            return agent
    raise LookupError(f"agent {agent_id!r} not found under {root or agentic_home()}")


def list_agents(
    project_root: str | os.PathLike[str] | None = None,
    running_only: bool = False,
    home: Path | None = None,
) -> list[Agent]:
    """Agents for one project+branch, or every agent when ``project_root`` is None."""
    base = state_dir_for_root(project_root, home) if project_root else (home or agentic_home())
    agents = [a for a in iter_agents(base) if not running_only or a.is_alive()]
    if project_root:
        branch = git_branch(project_root)
        agents = [a for a in agents if a.meta.get("branch") == branch]
    return agents


def create_agent(
    project_root: str | os.PathLike[str],
    *,
    name: str,
    mode: str,
    model: dict[str, Any],
    manager: str = DEFAULT_MANAGER,
    prompts: list[str] | None = None,
    skills: list[str] | None = None,
    preamble: str = "",
    parent: str | None = None,
    home: Path | None = None,
    branch: str | None = None,
    project: str | None = None,
) -> Agent:
    root = Path(project_root).expanduser().resolve()
    project = project or project_name(root)
    branch = branch or git_branch(root)
    agent_id = new_agent_id()
    directory = agent_dir(project, branch, manager, agent_id, home)
    directory.mkdir(parents=True, exist_ok=False)
    meta: dict[str, Any] = {
        "agent_id": agent_id,
        "name": name or agent_id,
        "project_root": str(root),
        "project_name": project,
        "branch": branch,
        "manager": "/".join(_segments(manager)) or DEFAULT_MANAGER,
        "mode": mode.lower(),
        "model": model,
        "context_limit": int(model.get("context_limit") or 0) or None,
        "prompts": prompts,
        "skills": skills,
        "preamble": preamble,
        "parent": parent,
        "children": [],
        "status": "created",
        "tokens": 0,
        "tokens_source": "estimate",
        "read_only": False,
        "created_at": now_iso(),
        "updated_at": now_iso(),
    }
    write_json_atomic(directory / META, meta)
    (directory / TRANSCRIPT).write_text(f"# {meta['name']}\n\n")
    (directory / LOG).touch()
    (directory / MCP_LOG).touch()
    (directory / EVENTS).touch()
    (directory / INBOX).touch()
    return Agent(directory, meta)


def append_event(agent: Agent, event: dict[str, Any]) -> dict[str, Any]:
    event = {"ts": time.time(), "agent_id": agent.meta.get("agent_id"), **event}
    with agent.path(EVENTS).open("a") as fh:
        fh.write(json.dumps(event) + "\n")
    return event


def read_events(agent: Agent, offset: int = 0) -> tuple[list[dict[str, Any]], int]:
    """Read events from byte ``offset``; returns (events, new_offset). Partial lines are left for later."""
    path = agent.path(EVENTS)
    try:
        with path.open("rb") as fh:
            fh.seek(offset)
            data = fh.read()
    except FileNotFoundError:
        return [], offset
    end = data.rfind(b"\n") + 1
    events = []
    for line in data[:end].splitlines():
        try:
            events.append(json.loads(line))
        except ValueError:
            continue
    return events, offset + end


def mark_read_only(path: Path) -> None:
    mode = path.stat().st_mode
    path.chmod(mode & ~(stat.S_IWUSR | stat.S_IWGRP | stat.S_IWOTH))


def append_transcript(agent: Agent, text: str) -> None:
    if agent.is_read_only():
        raise PermissionError(f"transcript of {agent.id} is read-only")
    with agent.path(TRANSCRIPT).open("a") as fh:
        fh.write(text)


def rename_agent(agent: Agent, name: str) -> Agent:
    agent.meta["name"] = name
    agent.save()
    return agent


def move_agent(agent: Agent, manager: str) -> Agent:
    """Change the manager. The supervisor keeps running; it re-reads its dir from meta on demand."""
    target = agent_dir(agent.meta["project_name"], agent.meta["branch"], manager, agent.id, agentic_home_of(agent))
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(agent.dir), str(target))
    moved = Agent(target, read_meta(target))
    moved.meta["manager"] = "/".join(_segments(manager)) or DEFAULT_MANAGER
    moved.save()
    return moved


def agentic_home_of(agent: Agent) -> Path:
    """Recover the agentic home from the agent's own dir, independent of depth."""
    parts = 1 + len(_segments(agent.meta["branch"]) or [NOGIT]) + len(_segments(agent.meta["manager"]) or [DEFAULT_MANAGER]) + 1
    return agent.dir.parents[parts - 1]


def kill_agent(agent: Agent) -> bool:
    """AgentKill: terminate the supervisor's process group immediately."""
    pid = agent.pid()
    if not pid_alive(pid):
        return False
    try:
        os.killpg(os.getpgid(pid), signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            return False
    agent.meta["status"] = "killed"
    agent.save()
    return True


def delete_agent(agent: Agent) -> None:
    """AgentDelete: kill if alive, then remove the agent directory (transcript included)."""
    kill_agent(agent)
    for path in agent.dir.rglob("*"):
        try:
            path.chmod(path.stat().st_mode | stat.S_IWUSR)
        except OSError:
            pass
    shutil.rmtree(agent.dir)
