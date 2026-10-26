# tabs/shared

Plugins and helpers used by every tab mode, plus the tab runtime they plug into.
`nvim/init.lua` imports `tabs.shared.plugins`, `tabs.standard.plugins`, and `tabs.agentic.plugins` into one `lazy.nvim` setup.

## Plugins (`plugins/init.lua`)

`plenary.nvim`, `nui.nvim`, `which-key.nvim`, `telescope.nvim`, `nvim-treesitter`, `catppuccin` (colorscheme),
`snacks.nvim`, `nvim-ufo`, `LuaSnip`, `friendly-snippets`, `nvim-cmp` with `cmp-cmdline`, `cmp-buffer`, `cmp-path`,
`cmp-nvim-lua`, `cmp-nvim-lsp`, `cmp_luasnip`, `nvim-autopairs`, and `obsidian.nvim`.

`nvim-ufo` uses its `marker` provider for agentic read buffers (`b:agentic_read`), so blocks between
`{{{agentic` and `}}}agentic` fold; every other buffer keeps `treesitter` then `indent`.

`obsidian.nvim` is enabled only on Neovim 0.11 or newer and needs `ripgrep`. It uses Telescope as the picker.
Note and tag completion come from its built-in LSP server (reached through the `nvim_lsp` cmp source).
`render-markdown.nvim` is commented out in `tabs/standard/plugins/ui.lua` and is not loaded.

## Commands

None. The `*Tab` commands are registered by the runtime below.

## Public functions

### `tabs.shared.obsidian`

- `vault()`: vault for the current tab (`tabs.runtime.vault()`, else cwd).
- `sync()`: switch `obsidian.nvim` to the current tab's vault, adding a workspace for it when needed. No-op until the plugin is loaded. Called on every `TabEnter`.

### `tabs.shared.cmp_project`

- `register()`: register the `nvim_project` nvim-cmp source. It completes `$ENV` variables after `$`
  and dotted keys of the current tab's `.nvim_project.json`. It is enabled for `markdown` buffers.

## Tab runtime (`nvim/lua/tabs/runtime.lua`)

Each tabpage stores `vim.t.mode` (`standard`, `agentic`, `system_standard`, `system_agentic`) and `vim.t.root`.
Startup binds the first tab to Standard for the project `main.lua` resolves, without `tcd`, so the startup cwd is unchanged.
A tab opened with a command does `tcd` to its root. A tab opened another way (`:tabnew`) inherits the mode and root of the tab it came from.
`gt`, `gT`, and `{count}gt` are the native motions. `TabEnter` installs the package's keymaps; `TabLeave` deletes them and restores any map they replaced.

### Commands

| Command | Effect |
| --- | --- |
| `:EditTab [dir]` | New Edit tab for the project containing `dir` (default: current tab root). |
| `:AgenticTab [dir]` | New Agentic tab for the project containing `dir` (default: current tab root). |
| `:SystemEditTab` | New Edit tab at `$COMMON_SCRIPT/system_project`, whatever the cwd. |
| `:SystemAgenticTab` | New Agentic tab at `$COMMON_SCRIPT/system_project`, whatever the cwd. |

The project root is the nearest ancestor with `.nvim_project.json`; when none exists the file is written in `dir` from the system-project template.

### Public functions

- `setup(project)`: install `TabEnter`/`TabLeave`/`TabClosed` autocmds and the `*Tab` commands, bind the current tab to Standard.
- `open(mode, dir?, opts?)`: open a tab in `mode` and `tcd` to its root; `opts.reuse` switches to an existing tab with the same mode and root. Returns the tabpage handle.
- `find(mode, root?)`: first tabpage bound to `mode` (and `root`), or nil.
- `enter()`, `leave()`: the `TabEnter` / `TabLeave` handlers.
- `state(tab?)`, `mode(tab?)`, `root(tab?)`, `project(tab?)`, `vault(tab?)`: per-tab state (`project` is the parsed `.nvim_project.json`).
- `is_mode(modes, tab?)`: whether the tab's mode is in `modes`.
- `guard(modes, name)`: true when the current tab is in `modes`, otherwise warns and returns false.
- `guard_commands(modes, register, exempt?)`: run `register`, wrapping every Lua user command it creates so the body only runs in `modes`.
- `apply_keymaps(specs)`, `clear_keymaps()`: install / remove which-key style specs (`{ lhs, rhs, mode =, desc =, expr =, nowait =, remap =, silent = }`).
- `package(mode)`: the package module for a mode.
- Fields: `packages` (mode → module name), `commands` (`*Tab` command → mode), `default_mode` (`"standard"`).

A package module may export `keymaps()`, `on_enter(state)`, `on_leave(state)`, `root(dir)` (fixed root), and `vault(state)`.
