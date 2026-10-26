#!/usr/bin/env python3
"""System Agentic tab: install the agentic client through scripts/agentic/install.py.

Usage: python3 scripts/system_agentic/install.py [scripts/agentic/install.py options]
       python3 scripts/system_agentic/install.py --check

Every argument is passed to scripts/agentic/install.py unchanged (``--venv``, ``--bin-dir``,
``--check``). The System Agentic tab uses the same client as a project Agentic tab; only the tab
root (``$COMMON_SCRIPT/system_project``) and the cross-project tree differ, so nothing else is
installed here. The agents' tools (fsearch, sd, dasel, ast-grep, Serena) come from
scripts/system_project/install.py.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

AGENTIC_INSTALLER = Path(__file__).resolve().parent.parent / "agentic" / "install.py"


def load():
    spec = importlib.util.spec_from_file_location("agentic_install", AGENTIC_INSTALLER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if argv[:1] in (["-h"], ["--help"]):
        print(__doc__)
    installer = load()
    saved = sys.argv
    sys.argv = [str(AGENTIC_INSTALLER), *argv]
    try:
        return installer.main()
    finally:
        sys.argv = saved


if __name__ == "__main__":
    sys.exit(main())
