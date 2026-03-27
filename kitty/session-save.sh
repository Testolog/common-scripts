#!/usr/bin/env bash
# Save current kitty layout to a session file (run from inside kitty).
# Edit the file to add cwd|cmd per pane (e.g. /home/you/proj|nvim), then restore with session-restore.sh.
set -e
SESSION_FILE="${1:-${KITTY_SESSION_FILE:-kitty-session.txt}}"

if ! command -v jq &>/dev/null; then
  echo "session-save: jq is required. Install with: brew install jq" >&2
  exit 1
fi

OUTPUT="$(kitty @ ls 2>/dev/null)" || {
  echo "session-save: run this script from inside kitty (kitty @ ls failed)" >&2
  exit 1
}

{
  # Session format: TAB = new tab; each other line = window as cwd|cmd (empty = just layout)
  count_tabs=$(echo "$OUTPUT" | jq '.[0].tabs | length')
  if [[ "$count_tabs" -eq 0 ]]; then
    count_tabs=1
    echo "TAB"
    echo "|"
  else
    for idx in $(seq 0 $((count_tabs - 1))); do
      echo "TAB"
      count_wins=$(echo "$OUTPUT" | jq ".[0].tabs[$idx].windows | length")
      for _ in $(seq 1 "$count_wins"); do
        echo "|"
      done
    done
  fi
} > "$SESSION_FILE"
echo "Saved session to $SESSION_FILE (${count_tabs:-1} tab(s); edit lines as cwd|cmd after TAB)"
