# tabs/system_standard

A Standard tab whose root is always `$COMMON_SCRIPT/system_project`, also when `getcwd()` is elsewhere.
It reuses `tabs.standard` (plugins, keymaps, guarded commands, LSP refresh) and registers no plugins of its own.
Its Obsidian vault is `$COMMON_SCRIPT`.

## Commands

- `:SystemEditTab` (registered by `tabs/runtime.lua`): open this tab. Runs `SystemProjectInit` first when the template is missing.
- `:'<,'>AgentSend`: as in Standard, but it opens the System Agentic tab and picks among the system project's agents.

## Install

`python3 scripts/system_standard/install.py [--strict]` runs the Standard checks (`scripts/standard/install.py`)
and reports whether `$COMMON_SCRIPT/system_project` has its template. It installs and creates nothing.

## Public functions (`tabs.system_standard`)

Everything from `tabs.standard`, plus:

- `root(_)`: `$COMMON_SCRIPT/system_project` (via `system_project.ensure()`).
- `vault(_)`: `$COMMON_SCRIPT`.
