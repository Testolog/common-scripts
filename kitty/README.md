# Kitty config (tmux-like, but better)

## Window manager & panels

- **Splits**: `Cmd+Enter` horizontal, `Cmd+Shift+Enter` vertical (same cwd as current)
- **Navigate panes**: `Ctrl+j/k/h/l` (down/up/left/right)
- **Layouts**: `Ctrl+Alt+Enter` splits, `Ctrl+Alt+s` stack, `Ctrl+Alt+g` grid
- **Tabs**: `Ctrl+Shift+t` new tab, `Ctrl+Shift+w` close tab, `Ctrl+Tab` / `Ctrl+Shift+Tab` next/prev
- **Go to tab**: `Ctrl+1` … `Ctrl+9`, `Ctrl+0` for tab 10
- **Tab picker**: `Ctrl+Shift+Space` (select tab by name)
- **Move tab**: `Ctrl+Alt+Tab` / `Ctrl+Alt+Shift+Tab`

## Search

- **Scrollback search**: `Ctrl+Shift+f` — opens scrollback pager; use `/` or `?` to search
- **Find on screen**: `Ctrl+f` — search backward in current view

## Session save & restore

Requires `jq` (e.g. `brew install jq`).

**Save** (run inside kitty):

```bash
/path/to/kitty/session-save.sh [session-file.txt]
# Default file: kitty-session.txt in cwd
```

**Restore** (run inside kitty or as `kitty sh -c '/path/to/session-restore.sh session-file.txt'`):

```bash
/path/to/kitty/session-restore.sh [session-file.txt]
```

**Session file format**: `TAB` starts a new tab; every other line is one pane as `cwd|cmd` (both optional). Example:

```
TAB
/home/you/proj|nvim
/home/you/proj|git status
TAB
/tmp|
```

After saving, edit the file to add `cwd|cmd` per pane; leave `|` for layout-only.
