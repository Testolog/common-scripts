# tabs/system_agentic

An Agentic tab whose root is always `$COMMON_SCRIPT/system_project`, also when `getcwd()` is elsewhere.
It reuses `tabs.agentic` (layout, panel, read/write buffers, commands, keymaps) and registers no plugins of its own.
Its Obsidian vault is `$COMMON_SCRIPT`, so write notes live in `$COMMON_SCRIPT/.agentic/notes/`.

## How it differs from a project Agentic tab

| | Project Agentic tab | System Agentic tab |
| --- | --- | --- |
| Root (`tcd`) | the project root | `$COMMON_SCRIPT/system_project` |
| Vault | the project root | `$COMMON_SCRIPT` |
| Tree | every agent (running or stopped) in `$HOME/agentic/<project>/<branch>/`, by manager; follows the git branch | every agent under `$HOME/agentic/` whose supervisor is alive, grouped by project name, then branch, then manager |
| Stopped / killed agents | listed with `○` | absent (they stay in their own project's tree) |
| `AgentCreate` | creates under this project and branch | creates under `$HOME/agentic/system_project/<branch>/` |
| MCP section | from this project's `.nvim_project.json` | from the system project's file |

Selecting an agent opens its read and write buffers. Stop, kill, delete, move, rename, pause, and resume are
addressed by agent id, so the Python client uses the project root recorded in that agent's `meta.json` for tools,
file changes, and Serena, and the LSP bridge resolves paths against that root, never against `$COMMON_SCRIPT`.
`AgentKill` terminates the selected supervisor immediately; the next refresh drops it from this list, and its
transcript stays until `AgentDelete`. Nothing is killed automatically. The tree refreshes every 3 s while visible.

`AgentSend` from a System Standard tab opens (or reuses) this tab and picks among the system project's agents for
the current branch.

## Commands

- `:SystemAgenticTab` (registered by `tabs/runtime.lua`): open this tab. Runs `SystemProjectInit` first when the template is missing.
- Every `Agent*` command from `tabs/agentic/README.md` works here with the behavior above.

## Install

`python3 scripts/system_agentic/install.py [--venv PATH] [--bin-dir PATH] [--check]` passes its arguments to
`scripts/agentic/install.py`; this tab uses the same client. Agent tools come from `scripts/system_project/install.py`.

## Public functions (`tabs.system_agentic`)

Everything from `tabs.agentic`, plus:

- `root(_)`: `$COMMON_SCRIPT/system_project` (via `system_project.ensure()`).
- `vault(_)`: `$COMMON_SCRIPT`.

The cross-project filter is `tabs.agentic.tree.agents(ui, st)`, which calls `tabs.agentic.store.running_agents()`
when `st.mode == "system_agentic"`.
