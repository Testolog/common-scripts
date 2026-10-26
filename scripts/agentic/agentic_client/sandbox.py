"""Path boundary for agent tools.

An agent may read and write inside the project root (the directory that holds
``.nvim_project.json``) and every directory under it. It may also read the
agent logs for that same project and branch, whichever manager they belong to,
and any directory the user granted with ``:AgentAllowRead``. Nothing else.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

_LOCATION = re.compile(r":\d+(?::\d+)?$")
_DIFF_PATH = re.compile(r"(?m)^(?:\+\+\+|---)\s+(?:a/|b/)?(\S+)")


def looks_like_path(arg: str) -> bool:
    """A filesystem path, not a sentence or a flag.

    A value with whitespace is a message, not a path, unless it begins with an
    absolute path or ``..``.
    """
    if not arg or arg.startswith("-"):
        return False
    head = arg.split()[0] if any(ch.isspace() for ch in arg) else arg
    if head.startswith(("/", "~", "./", "../")):
        return True
    return not any(ch.isspace() for ch in arg) and "/" in arg


def resolve_in(cwd: Path, raw: str) -> Path:
    text = _LOCATION.sub("", raw.strip())
    expanded = Path(os.path.expanduser(os.path.expandvars(text)))
    if not expanded.is_absolute():
        expanded = Path(cwd) / expanded
    return expanded.resolve()


def inside(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(Path(root).resolve())
    except ValueError:
        return False
    return True


def check_arguments(
    args: list[str],
    cwd: Path,
    *,
    write_root: Path,
    read_roots: list[Path],
    mutating: bool,
) -> str | None:
    """Return a refusal when any path argument leaves the allowed directories."""
    allowed = [Path(write_root).resolve()] if mutating else [Path(root).resolve() for root in read_roots]
    if not allowed:
        allowed = [Path(write_root).resolve()]
    for arg in args:
        for raw in _path_candidates(arg):
            try:
                resolved = resolve_in(cwd, raw)
            except OSError as exc:
                return f"Refused path {raw!r}: {exc}"
            if not any(inside(resolved, root) for root in allowed):
                where = "the project root" if mutating else "the project root, this branch's agent logs, or a folder granted with :AgentAllowRead"
                return f"Refused: {raw} is outside {where}."
    return None


def _path_candidates(arg: str) -> list[str]:
    found: list[str] = []
    if looks_like_path(arg):
        found.append(arg.split()[0])
    for match in _DIFF_PATH.finditer(arg):
        path = match.group(1)
        if path != "/dev/null":
            found.append(path)
    return found
