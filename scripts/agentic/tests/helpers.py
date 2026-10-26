from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


def git(cwd: Path, *args: str) -> None:
    subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", *args],
        cwd=cwd,
        check=True,
        capture_output=True,
    )


class TempHomeCase(unittest.TestCase):
    """Isolates ``$HOME/agentic`` and ``~/.cursor/mcp.json`` inside a temp dir."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name).resolve()
        self.home = self.tmp / "agentic"
        self._env = {k: os.environ.get(k) for k in ("AGENTIC_HOME", "AGENTIC_MCP_JSON")}
        os.environ["AGENTIC_HOME"] = str(self.home)
        os.environ["AGENTIC_MCP_JSON"] = str(self.tmp / "mcp.json")

    def tearDown(self) -> None:
        for key, value in self._env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        for path in self.tmp.rglob("*"):
            try:
                path.chmod(0o755 if path.is_dir() else 0o644)
            except OSError:
                pass
        self._tmp.cleanup()

    def make_project(self, name: str | None = "demo", data: dict | None = None) -> Path:
        root = self.tmp / "proj"
        root.mkdir(exist_ok=True)
        body = dict(data or {})
        if name:
            body["name"] = name
        (root / ".nvim_project.json").write_text(json.dumps(body))
        return root
