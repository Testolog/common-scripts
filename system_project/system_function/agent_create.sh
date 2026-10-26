#!/usr/bin/env bash
# Spawn another agent for the current project. Does not edit the project.
#   agent_create.sh --message <instruction> [--name <name>] [--mode edit|ask] [--model <id>] [--manager <name>]
# Default mode is edit. Prints the new agent's JSON (including agent_id) on stdout.
set -euo pipefail

name=""
mode="edit"
model=""
manager=""
message=""

while [ $# -gt 0 ]; do
  case "$1" in
    --name) name="${2:-}"; shift 2 ;;
    --mode) mode="${2:-}"; shift 2 ;;
    --model) model="${2:-}"; shift 2 ;;
    --manager) manager="${2:-}"; shift 2 ;;
    --message) message="${2:-}"; shift 2 ;;
    *)
      echo "usage: agent_create.sh --message <instruction> [--name <name>] [--mode edit|ask] [--model <id>] [--manager <name>]" >&2
      exit 2
      ;;
  esac
done

if [ -z "$message" ]; then
  echo "agent_create: --message is required" >&2
  exit 2
fi
if [ "$mode" != "edit" ] && [ "$mode" != "ask" ]; then
  echo "agent_create: --mode must be edit or ask" >&2
  exit 2
fi
if [ -z "$name" ]; then
  name="agent-$(date +%H%M%S)"
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

args=(start --root "$PWD" --name "$name" --mode "$mode" --message "$message")
if [ -n "$model" ]; then
  args+=(--model "$model")
fi
if [ -n "$manager" ]; then
  args+=(--manager "$manager")
fi

exec "$py" -m agentic_client "${args[@]}"
