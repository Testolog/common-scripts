#!/usr/bin/env bash
# File and content search for agents. Runs from the project root (the caller's cwd).
#   fsearch.sh <pattern> [paths...]       search file names
#   fsearch.sh <pattern> -f [paths...]    search inside files
# A leading `find` is accepted (`fsearch.sh find <pattern> ...`), so searching for the literal
# name "find" with more arguments needs it twice: `fsearch.sh find find src`.
# The fsearch CLI defaults to depth 1; FSEARCH_DEPTH (default 64) makes the search cover the project.
set -euo pipefail

if [ $# -ge 2 ] && [ "$1" = "find" ]; then
  shift
fi
if ! command -v fsearch >/dev/null 2>&1; then
  echo "fsearch is not installed; run scripts/system_project/install.py" >&2
  exit 127
fi
if [ $# -lt 1 ]; then
  echo "usage: fsearch.sh <pattern> [-f] [paths...]" >&2
  exit 2
fi

depth_args=()
if fsearch find --help 2>&1 | grep -q -- '--depth'; then
  depth_args=(--depth "${FSEARCH_DEPTH:-64}")
fi

exec fsearch find "$@" ${depth_args[@]+"${depth_args[@]}"}
