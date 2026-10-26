#!/usr/bin/env bash
# Literal edit of one exact occurrence in a text file.
#   sd.sh <file> <old text> <new text>
# Refuses when the old text is missing or matches more than once.
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: sd.sh <file> <old text> <new text>" >&2
  exit 2
fi
file=$1
old=$2
new=$3

if ! command -v sd >/dev/null 2>&1; then
  echo "sd is not installed; run scripts/system_project/install.py" >&2
  exit 127
fi
if [ ! -f "$file" ]; then
  echo "not a file: $file" >&2
  exit 2
fi
if [ -z "$old" ]; then
  echo "old text is empty" >&2
  exit 2
fi

count=$(python3 - "$file" "$old" <<'PY'
import sys
with open(sys.argv[1], encoding="utf-8", errors="surrogateescape") as fh:
    print(fh.read().count(sys.argv[2]))
PY
)

if [ "$count" -eq 0 ]; then
  echo "old text not found in $file" >&2
  exit 1
fi
if [ "$count" -gt 1 ]; then
  echo "old text matches $count times in $file; refusing ambiguous edit (add surrounding context)" >&2
  exit 1
fi

sd -F -- "$old" "$new" "$file"
echo "replaced 1 occurrence in $file"
