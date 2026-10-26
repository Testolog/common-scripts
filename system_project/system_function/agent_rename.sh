#!/usr/bin/env bash
# Rename one agent of the current project. Does not edit the project.
#   agent_rename.sh --agent <agent id or unique name> --name <new name>
# Prints {"ok": true, "agent_id", "name"} on stdout.
set -euo pipefail

agent=""
name=""

while [ $# -gt 0 ]; do
  case "$1" in
    --agent) agent="${2:-}"; shift 2 ;;
    --name) name="${2:-}"; shift 2 ;;
    *)
      echo "usage: agent_rename.sh --agent <agent id or unique name> --name <new name>" >&2
      exit 2
      ;;
  esac
done

if [ -z "$agent" ] || [ -z "$name" ]; then
  echo "agent_rename: --agent and --name are required" >&2
  exit 2
fi

py="${AGENTIC_PYTHON:-}"
if [ -z "$py" ]; then
  if [ -x "${HOME}/agentic/.venv/bin/python" ]; then
    py="${HOME}/agentic/.venv/bin/python"
  else
    py="python3"
  fi
fi

here="$(cd "$(dirname "$0")" && pwd)"
checkout="$(cd "$here/../.." && pwd)"
for dir in "${COMMON_SCRIPT:-}/scripts/agentic" "$checkout/scripts/agentic"; do
  if [ -n "$dir" ] && [ -d "$dir/agentic_client" ]; then
    PYTHONPATH="$dir${PYTHONPATH:+:$PYTHONPATH}"
    export PYTHONPATH
    break
  fi
done

"$py" -c '
import json, os, sys
from agentic_client.client import rename_project_agent
try:
    print(json.dumps(rename_project_agent(os.getcwd(), sys.argv[1], sys.argv[2])))
except Exception as exc:
    print(json.dumps({"ok": False, "error": str(exc)}))
    sys.exit(1)
' "$agent" "$name"
