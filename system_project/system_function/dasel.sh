#!/usr/bin/env bash
# Field edit for yaml, json, avsc, toml, xml, and csv (dasel v2 `put`, written in place).
#   dasel.sh <file> <selector> <value> [type]
# type: string (default), int, float, bool, json, yaml. Avsc files are read and written as JSON.
set -euo pipefail

if [ $# -lt 3 ] || [ $# -gt 4 ]; then
  echo "usage: dasel.sh <file> <selector> <value> [type]" >&2
  exit 2
fi
file=$1
selector=$2
value=$3
type=${4:-string}

if ! command -v dasel >/dev/null 2>&1; then
  echo "dasel is not installed; run scripts/system_project/install.py" >&2
  exit 127
fi
if ! dasel put --help >/dev/null 2>&1; then
  echo "this wrapper needs dasel v2 (dasel put)" >&2
  exit 127
fi
if [ ! -f "$file" ]; then
  echo "not a file: $file" >&2
  exit 2
fi

ext=$(printf '%s' "${file##*.}" | tr '[:upper:]' '[:lower:]')
case "$ext" in
  yml|yaml) format=yaml ;;
  json|avsc) format=json ;;
  toml) format=toml ;;
  xml) format=xml ;;
  csv) format=csv ;;
  *)
    echo "unsupported file type: .$ext (yaml, json, avsc, toml, xml, csv)" >&2
    exit 2
    ;;
esac

dasel put -f "$file" -r "$format" -w "$format" -t "$type" -v "$value" "$selector"
echo "set $selector in $file"
