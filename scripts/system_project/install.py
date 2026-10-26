#!/usr/bin/env python3
"""Install the system-project tools that are missing from PATH.

Tools: fsearch, sd, dasel, ast-grep, and Serena. Already installed tools are left alone.
This does not install Ollama and does not download model weights.

Usage: install.py [--dry-run]
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys


def brew(formula: str) -> list[str] | None:
    return ["brew", "install", formula] if shutil.which("brew") else None


def cargo(*args: str) -> list[str] | None:
    return ["cargo", "install", *args] if shutil.which("cargo") else None


def go(module: str) -> list[str] | None:
    return ["go", "install", module] if shutil.which("go") else None


def uv(*args: str) -> list[str] | None:
    return ["uv", *args] if shutil.which("uv") else None


# (name, binaries that satisfy it, install command candidates in preference order)
TOOLS = [
    (
        "fsearch",
        ["fsearch"],
        [lambda: cargo("--git", "https://github.com/cumulus13/fsearch")],
    ),
    (
        "sd",
        ["sd"],
        [lambda: brew("sd"), lambda: cargo("sd")],
    ),
    (
        "dasel",
        ["dasel"],
        [lambda: brew("dasel"), lambda: go("github.com/tomwright/dasel/v2/cmd/dasel@latest")],
    ),
    (
        "ast-grep",
        ["ast-grep", "sg"],
        [lambda: brew("ast-grep"), lambda: cargo("ast-grep", "--locked")],
    ),
    (
        "serena",
        ["serena"],
        [lambda: uv("tool", "install", "-p", "3.13", "--upgrade", "serena-agent")],
    ),
]


def install(name: str, binaries: list[str], candidates, dry_run: bool) -> bool:
    found = next((shutil.which(b) for b in binaries if shutil.which(b)), None)
    if found:
        print(f"[ok]      {name}: {found}")
        return True
    for candidate in candidates:
        cmd = candidate()
        if cmd is None:
            continue
        print(f"[install] {name}: {' '.join(cmd)}")
        if dry_run:
            return True
        result = subprocess.run(cmd, check=False)
        if result.returncode == 0:
            return True
        print(f"[failed]  {name}: exit {result.returncode}", file=sys.stderr)
        return False
    print(f"[missing] {name}: no installer available (need brew, cargo, go, or uv)", file=sys.stderr)
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="print the install commands without running them")
    args = parser.parse_args()
    ok = True
    for name, binaries, candidates in TOOLS:
        ok = install(name, binaries, candidates, args.dry_run) and ok
    if not shutil.which("git"):
        print("[missing] git (git apply): install git", file=sys.stderr)
        ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
