# tabs/standard

The everyday editing workspace, moved here from `nvim/lua/plugins/` and `nvim/lua/keymapping.lua` without changing its behavior.
`nvim/lua/languages.lua`, `nvim/lua/system.lua`, `arduino.lua`, `idf.lua`, `c_run.lua`, and `format_selection.lua` stay where they are and are set up by this package.

## Plugins (`plugins/`)

- `ui.lua`: navbuddy, harpoon, undotree, devicons, airline, aerial, trouble, rose-pine, tiny-code-action, tiny-inline-diagnostic, heirline, noice (disabled), edgy, zen-mode. `render-markdown.nvim` is commented out (deferred; Markdown is rendered by `obsidian.nvim`).
- `tools.lua`: maven, mason, mason-lspconfig, nvim-lspconfig, lazygit, flatten, gitsigns, vim-tmux-navigator, `nvim-tree` (Standard only), nvim-dap, vim-dadbod-ui.
- `langs.lua`: lazydev, neoconf, nvim-java, rustaceanvim.
- `utility.lua`: treesitter playground, presenting, fidget, quicker, nvim-surround, escape, schemastore, nvim-lint, none-ls, persistence.

Shared plugins (cmp, telescope, treesitter, ufo, snacks, which-key, colorscheme, obsidian) are in `tabs/shared`.

## Keymaps (`keymaps.lua`)

The former `keymapping.lua` table, returned as which-key style specs. It is installed on `TabEnter` of a Standard or System Standard tab and removed on `TabLeave`.
Some keys share a prefix with the Agentic tab (`<leader>ac` is Arduino compile here and create-agent there); only the active tab's map is installed.

## Install

`python3 scripts/standard/install.py [--strict]` checks Neovim 0.11+ and `ripgrep`. It installs nothing.
On Neovim 0.10 it warns that `obsidian.nvim` stays disabled and still exits 0; `--strict` exits 1 when a requirement is missing.

## Commands

Registered once at startup. Bodies run only in `standard` / `system_standard` tabs; elsewhere they warn and do nothing.

- `system.lua`: `JsonFormat`, `SQLFormat`, `Escape`, `UnEscape`, `SSHKeyLoad`, `FormatSelection` (range), `AppendPy`.
- `arduino.lua`: `ArduinoCompile`, `ArduinoUpload`, `ArduinoMonitor`, `ArduinoUploadAndMonitor`, `ArduinoPort`, `ArduinoChip`, `ArduinoMonitorStop`, `ArduinoLibInstall`, `ArduinoLibSearch`, `ArduinoLibAdd`, `ArduinoSyncSketchYaml`.
- `idf.lua`: `IDFBuild`, `IDFFlash`, `IDFMonitor`, `IDFFlashAndMonitor`, `IDFMonitorStop`, `IDFPort`.
- `c_run.lua`: `CRun`.

Available in every tab: `Quit`, `ReloadConfig`, `ErrorLogToggle`, `ErrorLogClear`.

`:'<,'>AgentSend` (visual map `<leader>A`) runs only in Standard and System Standard tabs. It is registered by
`tabs.agentic.setup()`; see `tabs/agentic/README.md`. With no selection it reports that nothing is selected.
Otherwise it opens the Agentic tab for the same project, asks create-or-pick, and puts the selection with its
path and line range into that agent's write buffer without submitting.

## Public functions (`tabs.standard`)

- `setup(project)`: register the commands above (guarded), autocmds, filetypes, and `languages.setup(project)`.
- `keymaps()`: the spec list from `keymaps.lua`.
- `on_enter(state)`: close the agentic tree when `tabs.agentic.close_tree` exists, restore this tab's nvim-tree root, and call `languages.refresh(state.project)`.
- `on_leave(state)`: remember this tab's nvim-tree root.
- `close_tree()`: close nvim-tree in the current tab (used when entering an Agentic tab).
- Fields: `mode` (`"standard"`), `modes` (where the guarded commands run), `global_commands` (names left unguarded).

## LSP refresh (`languages.refresh(project)`)

On Standard `TabEnter`, the tab's `.nvim_project.json` becomes the source for project-sensitive pieces when its root differs from the startup project:
the `lua_ls` runtime paths for its `lua.version`, YAML and JSON schemas, and the `jenv javahome` JDK from that root.
Clients started later under that root get them through `on_new_config`; running `yamlls` / `jsonls` clients under that root get `workspace/didChangeConfiguration`.
The startup project's clients and config are not changed, so a single Standard tab behaves as before.
