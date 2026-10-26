#!/usr/bin/env python3
"""Install the agentic client into a private venv and expose ``agentic-client``.

Usage: python3 scripts/agentic/install.py [--venv PATH] [--bin-dir PATH] [--check]

* Creates ``$HOME/agentic/.venv`` (or ``--venv``) and pip-installs this package with
  its pinned dependencies.
* Links ``agentic-client`` into ``--bin-dir`` (default ``~/.local/bin``).
* Reports whether the Cursor CLI ``agent`` and ``serena`` are on PATH. It does not
  install them, does not install Ollama, and does not download model weights.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import venv
from pathlib import Path

HERE = Path(__file__).resolve().parent
MIN_PYTHON = (3, 10)


def run(cmd: list[str]) -> None:
    print("+", " ".join(cmd))
    subprocess.run(cmd, check=True)


def check_tools() -> int:
    missing = 0
    for name, hint in (
        ("agent", "Cursor CLI (curl https://cursor.com/install -fsS | bash)"),
        ("serena", "scripts/system_project/install.py installs serena-agent"),
    ):
        path = shutil.which(name)
        print(f"{name:8} {'ok  ' + path if path else 'missing: ' + hint}")
        missing += path is None
    return missing


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--venv", type=Path, default=Path.home() / "agentic" / ".venv")
    parser.add_argument("--bin-dir", type=Path, default=Path.home() / ".local" / "bin")
    parser.add_argument("--check", action="store_true", help="only report external tools")
    args = parser.parse_args()

    if sys.version_info < MIN_PYTHON:
        print(f"Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]}+ is required", file=sys.stderr)
        return 1
    if args.check:
        check_tools()
        return 0

    if not (args.venv / "bin" / "python").exists():
        print(f"creating venv {args.venv}")
        venv.EnvBuilder(with_pip=True).create(args.venv)
    py = str(args.venv / "bin" / "python")
    run([py, "-m", "pip", "install", "--upgrade", "pip"])
    run([py, "-m", "pip", "install", "-e", str(HERE)])

    args.bin_dir.mkdir(parents=True, exist_ok=True)
    target = args.venv / "bin" / "agentic-client"
    link = args.bin_dir / "agentic-client"
    if link.is_symlink() or link.exists():
        link.unlink()
    os.symlink(target, link)
    print(f"linked {link} -> {target}")
    check_tools()
    return 0


if __name__ == "__main__":
    sys.exit(main())
