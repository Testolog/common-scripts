#!/usr/bin/env bash
# Restore kitty layout from a session file. Run from inside kitty, or:
#   kitty sh -c 'path/to/session-restore.sh session.txt'
# Session format: TAB starts a tab; each other line is cwd|cmd (empty ok).
set -e
SESSION_FILE="${1:-${KITTY_SESSION_FILE:-kitty-session.txt}}"

if [[ ! -f "$SESSION_FILE" ]]; then
  echo "session-restore: file not found: $SESSION_FILE" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "session-restore: jq is required. Install with: brew install jq" >&2
  exit 1
fi

# Parse session file: build list of (cwd, cmd) per window in order
declare -a cwds cmds
current_tab=0
windows_per_tab=()
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == "TAB" ]]; then
    ((current_tab++))
    windows_per_tab+=(0)
    continue
  fi
  if [[ $current_tab -eq 0 ]]; then
    continue
  fi
  cwd="${line%%|*}"
  cmd="${line#*|}"
  cwds+=("$cwd")
  cmds+=("$cmd")
  ((windows_per_tab[current_tab - 1]++)) || true
done < "$SESSION_FILE"

total_windows=${#cwds[@]}
if [[ $total_windows -eq 0 ]]; then
  echo "session-restore: no windows in session file" >&2
  exit 1
fi

# Create layout: new tabs for 2nd tab onward; for each tab, new splits for 2nd window onward
num_tabs=${#windows_per_tab[@]}
for ((t = 1; t < num_tabs; t++)); do
  kitty @ new-window --cwd current 2>/dev/null || true
done
# Now we have the right number of tabs. Go back to first tab and create splits per tab.
for ((t = 0; t < num_tabs; t++)); do
  kitty @ focus-tab --match "index:$t" 2>/dev/null || true
  wins=${windows_per_tab[t]}
  for ((w = 1; w < wins; w++)); do
    kitty @ launch --location=vsplit --cwd current 2>/dev/null || true
  done
done

# Get window ids in order (tab order, then window order within each tab)
kitty @ focus-tab --match "index:0" 2>/dev/null || true
sleep 0.2
WINDOW_IDS=()
while read -r id; do
  WINDOW_IDS+=("$id")
done < <(jq -r '.[0].tabs[]?.windows[]?.id // empty' <<< "$(kitty @ ls 2>/dev/null)")

# Send cwd and cmd to each window (escape \ for kitty send-text)
escape_send() { printf '%s' "$1" | sed 's/\\/\\\\/g'; }
for ((i = 0; i < total_windows && i < ${#WINDOW_IDS[@]}; i++)); do
  wid=${WINDOW_IDS[i]}
  cwd="${cwds[i]}"
  cmd="${cmds[i]}"
  if [[ -n "$cwd" ]]; then
    safe_cwd=$(escape_send "$cwd")
    kitty @ send-text --match "id:$wid" "cd \"$safe_cwd\""$'\n' 2>/dev/null || true
  fi
  if [[ -n "$cmd" ]]; then
    safe_cmd=$(escape_send "$cmd")
    kitty @ send-text --match "id:$wid" "$safe_cmd"$'\n' 2>/dev/null || true
  fi
done
echo "Restored session from $SESSION_FILE ($total_windows windows)"