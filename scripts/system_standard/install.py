#!/usr/bin/env python3
"""System Standard tab: the Standard tab checks, plus where the system project lives.

Usage: python3 scripts/system_standard/install.py [--strict]

Delegates to scripts/standard/install.py (Neovim 0.11+ and ripgrep) and reports whether
``$COMMON_SCRIPT/system_project`` exists. Nothing is installed or created; ``:SystemProjectInit``
(or opening ``:TabSystemStandard``) creates the system project.
"""

from __future__ import annotations

import importlib.util
import os
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent


def load(package: str):
    path = SCRIPTS / package / "install.py"
    spec = importlib.util.spec_from_file_location(f"{package}_install", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def report_system_project() -> None:
    common = os.environ.get("COMMON_SCRIPT") or str(SCRIPTS.parent)
    source = "COMMON_SCRIPT" if os.environ.get("COMMON_SCRIPT") else "this checkout (COMMON_SCRIPT unset)"
    root = Path(common) / "system_project"
    if (root / ".nvim_project.json").is_file():
        print(f"[ok]      system project: {root} (from {source})")
    else:
        print(f"[info]    system project: {root} has no template yet; run :SystemProjectInit (from {source})")


def main(argv: list[str] | None = None) -> int:
    status = load("standard").main(argv)
    report_system_project()
    return status


if __name__ == "__main__":
    sys.exit(main())
