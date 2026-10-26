#!/usr/bin/env python3
"""Check what the Standard tab needs: Neovim 0.11+ and ripgrep.

Usage: python3 scripts/standard/install.py [--strict]

Nothing is installed. Neovim older than 0.11 still runs the Standard tab; only obsidian.nvim
(Markdown writing and rendering) stays disabled until Neovim is upgraded. Missing ripgrep
breaks obsidian.nvim search and Telescope live grep.

Exit status is 0 unless ``--strict`` is given and a requirement is missing.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys

MIN_NVIM = (0, 11)


def nvim_version() -> tuple[tuple[int, int, int] | None, str]:
    path = shutil.which("nvim")
    if not path:
        return None, "nvim not on PATH"
    try:
        out = subprocess.run([path, "--version"], capture_output=True, text=True, timeout=20).stdout
    except (OSError, subprocess.SubprocessError) as exc:
        return None, f"cannot run {path} --version: {exc}"
    match = re.search(r"NVIM v(\d+)\.(\d+)\.(\d+)", out)
    if not match:
        return None, f"cannot parse `{path} --version`"
    return (int(match[1]), int(match[2]), int(match[3])), path


def check_nvim() -> bool:
    version, detail = nvim_version()
    if version is None:
        print(f"[missing] neovim: {detail}")
        return False
    text = ".".join(map(str, version))
    if version[:2] >= MIN_NVIM:
        print(f"[ok]      neovim {text}: {detail}")
        return True
    print(
        f"[warn]    neovim {text}: obsidian.nvim needs Neovim {MIN_NVIM[0]}.{MIN_NVIM[1]}+ and stays disabled. "
        "The Standard tab works without it; Markdown falls back to the markdown ftplugin."
    )
    return False


def check_ripgrep() -> bool:
    path = shutil.which("rg")
    if path:
        print(f"[ok]      ripgrep: {path}")
        return True
    print("[missing] ripgrep (rg): needed by obsidian.nvim and Telescope live grep (brew install ripgrep)")
    return False


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--strict", action="store_true", help="exit 1 when a requirement is missing")
    args = parser.parse_args(argv)
    ok = check_nvim()
    ok = check_ripgrep() and ok
    return 1 if args.strict and not ok else 0


if __name__ == "__main__":
    sys.exit(main())
