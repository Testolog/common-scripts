#!/usr/bin/env bash
# Structural rewrite of a repeated pattern, applied in place.
#   ast-grep.sh <pattern> <lang> <rewrite> [paths...]
# Runs `sg -p <pattern> -l <lang> -r <rewrite>` with --update-all. No SQL grammar; avsc uses the JSON grammar.
set -euo pipefail

if [ $# -lt 3 ]; then
  echo "usage: ast-grep.sh <pattern> <lang> <rewrite> [paths...]" >&2
  exit 2
fi
pattern=$1
lang=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
rewrite=$3
shift 3

case "$lang" in
  sql)
    echo "ast-grep has no SQL grammar; use sd or git apply" >&2
    exit 2
    ;;
  avsc) lang=json ;;
esac

if command -v ast-grep >/dev/null 2>&1; then
  bin=ast-grep
elif command -v sg >/dev/null 2>&1; then
  bin=sg
else
  echo "ast-grep is not installed; run scripts/system_project/install.py" >&2
  exit 127
fi

exec "$bin" -p "$pattern" -l "$lang" -r "$rewrite" --update-all "$@"
