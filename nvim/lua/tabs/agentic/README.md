# tabs/agentic

Agentic tab package: a `nui.nvim` agent tree, the `AgentCreate` panel, read/write buffers per agent, and the
`Agent*` commands. `tabs/system_agentic` reuses this package with a fixed root and the cross-project tree.
No plugin is added: `nui.nvim`, `nvim-ufo`, `nvim-cmp`, and `obsidian.nvim` come from `tabs/shared`.

## Layout

| Pane | Content |
| --- | --- |
| Left, ~30% | Agent tree (`agentic://tree/<tab>`). Project tab: `$HOME/agentic/<project>/<branch>/`, grouped by manager. System Agentic: every running agent, grouped by project, branch, manager. Below: MCP status and notices. |
| Right, top | Read buffer of the selected agent (`agentic://<id>/read`). |
| Right, bottom, 20% | Write buffer: `<vault>/.agentic/notes/<agent_id>.md` (`draft.md` before an agent exists). `<leader>ae` expands it to the full right side and collapses it back. |

Entering an Agentic tab closes nvim-tree in that tab and builds the layout. Entering a Standard tab closes this tree.
Selecting another agent swaps both panes. A second read buffer opens only with `v` / `:AgentReadSplit`.
The project tree re-reads the git branch every 3 s; a new branch switches the directory it lists.

Agent nodes show alive/stopped, name, status, tokens/context window, and mode. Expanding an agent (`l`) shows
created and modified time, token usage and source, context window, model, mode, manager, project root, id,
parent, and handoff target.

The MCP section comes from `agentic-client mcp --root <tab root>`: server name, status (`connect`, `inactive`,
`unsupported`, `missing`), reason, and the `mcp.json` parse error. Each server row starts with `[x]` or `[ ]`.
`<CR>` or `o` on that row writes `mcp_servers[].isActive` in this tab's `.nvim_project.json` and leaves the rest
of the file unchanged. A new agent reads that flag. URLs are not shown and not written anywhere.
`tree` events from running agents (`mcp_error`, `mcp_catalog` errors, `mcp_status`, `handoff`) and LSP bridge
errors appear under Notices. `<CR>` or `o` on a notice, or on the Notices heading, opens those messages in a
read-only panel (`:AgentNotices`, tree `N`, `<leader>an`). `q` or Escape closes it.

## Read buffer

- History is `transcript.md`; live output streams from `agentic-client events <id> --offset N`, starting at the
  turn in progress (or the end of `events.jsonl`).
- Thoughts, tool/API calls (Cursor `*ToolCall` and supervisor tool events), tool results, logs, LSP requests, and
  error tracebacks are blocks between the explicit markers `{{{agentic` / `}}}agentic`. A JSON object in one of
  those blocks, including a JSON string nested inside a result, is shown as markdown labels and lists. Call ids
  and timestamps are left out. The window uses
  `foldmarker={{{agentic,}}}agentic` and `foldlevel=0`; nvim-ufo's `marker` provider folds these buffers
  (the shared ufo `provider_selector` returns `marker` when `b:agentic_read` is set), so they start collapsed.
  The answer (`## Assistant`) and user messages are never inside a fold.
- File changes render as fenced `diff` hunks: a live edit diffs the file before and after the tool call; on replay,
  `old_string`/`new_string` or the written content from the tool arguments are used; a `git apply` patch argument is
  shown as is.
- The buffer is `nomodifiable`; insert/change keys report that it is read-only. `gw` copies the current block
  (fence, fold body, or paragraph) or the visual selection into the write buffer; `gn` seeds a new agent with it.
- Closing the window or wiping the buffer never stops the agent (wiping only stops following and detaches Neovim).
- On a `tree`/`handoff` event (`switch_buffer: false`) the old transcript gets a read-only note, the tree gets a
  notice, and the visible buffer stays where it is. Select the child in the tree to continue.

## Write buffer

A Markdown note in the tab vault (project root; `$COMMON_SCRIPT` for System Agentic), so `obsidian.nvim` renders
it on Neovim 0.11+. `<vault>/.agentic/.gitignore` ignores the notes. nvim-cmp's markdown sources apply: `path`,
`$ENV` variables, and keys of the tab's `.nvim_project.json` (`tabs.shared.cmp_project`). `<C-s>` submits the
note to the running agent (`agentic-client send`, text on stdin), echoes it in the read buffer, and clears it.
A stopped or read-only agent keeps the text and reports why.

## LSP requests

When the supervisor emits `lsp_request`, `lsp_bridge` answers with a client Neovim already runs and sends
`agentic-client lsp-result`. For the four `lsp_*` tools `function` is the method (`textDocument/hover`,
`definition`, `references`, `rename`). For the ten language-server entries `function` is the client name and the
first argument names the method. Positions are `file:line:column` (1-based) or `file line column`, resolved
against the agent's `meta.json` root. A file that is not open is loaded with `noautocmd`, and an already-running
client that covers it is attached, so no server is ever started. With no attached server the reply says so.
Rename applies the workspace edit and writes the changed buffers. Only requests newer than 60 s are answered.

## Python client

All calls go through `tabs.agentic.client`, which runs the `agentic-client` CLI (`agentic-client` on PATH, else
`~/agentic/.venv/bin/python -m agentic_client`, else `python3 -m agentic_client`, with `PYTHONPATH` set to
`$COMMON_SCRIPT/scripts/agentic`; override with `vim.g.agentic_client_cmd = { ... }`). The CLI also gets
`COMMON_SCRIPT` (the value `system_project.common_script()` resolves), so the template's
`$COMMON_SCRIPT/system_project/...` tool and prompt paths work in the detached supervisor. Install the client with
`scripts/agentic/install.py` (or `scripts/system_agentic/install.py`, which delegates to it). Subcommands used: `start`,
`events`, `send`, `pause`, `resume`, `stop`, `restart`, `kill`, `delete`, `rename`, `move`, `attach-nvim`, `detach-nvim`,
`lsp-result`, `list`, `models`, `mcp`. Tool policy (Ask/Edit, `mutates`, shell wrappers, MCP, Serena) stays in
Python. The tree reads `meta.json` and `supervisor.pid` directly (walking for `meta.json`) and never writes them.

## Commands

Bodies run only in Agentic and System Agentic tabs (other tabs get a warning), except `AgentSend`, which runs
only in Standard and System Standard tabs. `[id]` defaults to the agent under the tree cursor, else the selected agent.

| Command | Effect |
| --- | --- |
| `:AgentCreate [name]` | Open the create panel: Name, Manager, Mode (Ask/Edit), Model, Prompts and Skills (all selected by default). Models: project `models`, the Cursor catalog stored in `system_project/cursor_models.json`, and each local `base_url`'s `/models`; a local server that is not listening is reported. `:CursorUpdateModelList` is the only command that asks the Cursor CLI for models. Create starts the agent and opens it in the panes; draft text moves into its write buffer. |
| `:AgentStart [id]` | Start the supervisor again for an agent that already exists. A running agent is left as it is. A read-only agent after handoff is not started. |
| `:AgentStop [id]` | Ask the supervisor to finish. |
| `:AgentKill [id]` | Terminate the supervisor now. The transcript stays until delete. |
| `:AgentDelete [id]` | Confirm, then kill and remove the agent directory. |
| `:AgentRename [id] [name]` | Rename (prompts when no name). |
| `:AgentMove [id] [manager]` | Change the manager folder (prompts when no manager); the event stream follows the move. |
| `:AgentPause [id]`, `:AgentResume [id]`, `:AgentPauseToggle [id]` | Pause / resume. |
| `:AgentSubmit` | Send the write buffer to the selected agent. |
| `:AgentWriteToggle` | Expand the write buffer to the right side or collapse it to 20%. |
| `:AgentWriteFocus` | Focus the write buffer. |
| `:AgentReadSplit [id]` | Open a second read buffer (picker without id). |
| `:AgentMcpLog [id]` | Open that agent's MCP client log (`mcp.log`) in a read-only split. `q` closes it. |
| `:AgentNotices` | Open the Notices messages in a read-only panel. `q` or Escape closes it. |
| `:AgentTree` | Toggle the tree. |
| `:AgentRefresh` | Re-read the branch, agents, and MCP status. |
| `:[range]AgentCopyToWrite` | Copy the selection or the current read block into the write buffer. |
| `:[range]AgentSeed` | Put the selection or current read block in the draft and open `AgentCreate`. |
| `:'<,'>AgentSend` | Standard / System Standard only. No selection: reports that nothing is selected. Otherwise opens (or reuses) the Agentic tab for the same project (System Agentic for System Standard), asks create-or-pick among that project and branch's agents, and writes the selection with its source path and line range into that write buffer. Never submits. Create opens `AgentCreate` with the text already in the draft. |

## Keymaps

Tab maps (installed on `TabEnter`, removed on `TabLeave`): `<leader>at` tree, `<leader>ac` create, `<leader>aS` start, `<leader>as` stop,
`<leader>aK` kill, `<leader>ad` delete, `<leader>ar` rename, `<leader>am` move, `<leader>ap` pause/resume,
`<leader>ae` expand/collapse write, `<leader>aw` focus write, `<leader>av` second read, `<leader>al` MCP log, `<leader>an` notices, `<leader>aR` refresh.

Tree buffer: `<CR>`/`o` open agent, turn the MCP row on or off for this project, or toggle folder, `l`/`h` expand/collapse, `<Tab>` toggle, `a` create (manager
under cursor), `S` start an existing agent, `s` stop, `X` kill, `d` delete, `r` rename, `m` move, `p` pause/resume, `v` second read, `L` MCP log, `N` notices, `R` refresh,
`q` close, `?` help.

Read buffer: `gw` copy block/selection to write, `gn` seed a new agent; `i a o c s R x p d u ...` are blocked.
Write buffer: `<C-s>` submit (normal and insert).
Standard tab (visual): `<leader>A` runs `:AgentSend`.

## Public functions

### `tabs.agentic`

- `keymaps()`: the tab spec list (`keymaps.lua`).
- `on_enter(state)`: close nvim-tree, build the layout, refresh the tree, check the branch, start the refresh timer.
- `on_leave(state)`: no-op.
- `close_tree()`: close the agentic tree in the current tab (called on Standard `TabEnter`).
- `selected()`: fresh meta of the agent shown in the panes, or nil.
- `open_agent(agent_id)`: show an agent in the panes.
- `setup()`: register the commands above (called from `main.load`).
- Fields: `mode` (`"agentic"`), `modes` (where `Agent*` bodies run), `send_modes` (where `AgentSend` runs).

### `tabs.agentic.keymaps`

The list part is the tab spec list above. `tree_buffer(buf)`, `read_buffer(buf)`, `write_buffer(buf)` install the
buffer-local maps of the tree, read, and write buffers.

### `tabs.agentic.client` (Python CLI)

`command()`, `scripts_dir()`, `run(args, opts?, cb?)` (async with `cb(value, err)`, else sync),
`events(id, offset, on_event, on_exit?)` (job id), `start(spec, cb?)` (`spec`: root, name, mode, model string or
table, manager, prompts, skills, message), `send(id, text, cb?)`, `pause`, `resume`, `stop`, `kill`, `delete`
(`(id, cb?)`), `rename(id, name, cb?)`, `move(id, manager, cb?)`, `attach_nvim(id, cb?)`, `detach_nvim(id, cb?)`,
`lsp_result(id, request_id, text, cb?)`, `list_agents(root?, running?, cb?)`, `list_models(root, cb?)`,
`mcp_status(root, cb?)`.

### `tabs.agentic.store` (read-only state)

`home()`, `segments(path)`, `branch(root)`, `branch_async(root, cb)`, `project_name(project, root)`,
`branch_dir(project_name, branch)`, `read_file(path)`, `pid_alive(pid)`, `read(dir)`, `scan(base?)`,
`project_agents(project_name, branch)`, `running_agents()`, `find(agent_id)`, `forget(agent_id)`.
Constants: `META`, `PID`, `TRANSCRIPT`, `EVENTS` (file names in an agent directory).

### `tabs.agentic.state`

`tab()`, `get(tab?)` (UI state, runtime state), `is_agentic(st)`, `is_system(st)`, `valid_win(win, tab?)`,
`agentic_tabs()`, `notice(text, level?, agent_id?)`, `notices()`. Constant: `MAX_NOTICES`.

### `tabs.agentic.tree`

`agents(ui, st)`, `refresh(tab?)`, `refresh_all()`, `load_mcp(tab?)`, `check_branch(tab?)`, `start_timer()`,
`buffer()`, `configure_window(win)`, `cursor_node()`, `cursor_agent()`, `cursor_manager()`, `toggle(node?)`,
`expand(open)`, `activate()`, `help()`. Constants: `REFRESH_MS` (3000), `HELP` (help lines).

### `tabs.agentic.layout`

`ensure()`, `show(meta|nil, opts?)` (`opts.focus` = `"read"`/`"write"`), `toggle_write()`, `focus_write()`,
`open_second_read(meta)`, `close_tree()`, `toggle_tree()`. Constants: `TREE_WIDTH`, `WRITE_HEIGHT` (fractions).

### `tabs.agentic.read`

`session(meta)`, `get(agent_id)`, `configure_window(win, session)`, `winbar(session)`, `echo_user(id, text)`,
`restart(meta)`, `update_meta(meta)`, `wipe(id)`, `on_tree_event(session, event)`, `current_block(buf, lnum)`,
`fmt_tokens(n)`. Constants: `FOLD_OPEN`, `FOLD_CLOSE`, `FOLDMARKER`, `MAX_FOLD_LINES`, `LSP_WINDOW` (seconds an
`lsp_request` stays answerable).

### `tabs.agentic.write`

`notes_dir(vault)`, `note_path(vault, key)`, `buffer(key, vault?)`, `text(buf)`, `set_text(buf, text)`,
`append(buf, text)`, `adopt_draft(agent_id)`, `submit(buf?)`. Constants: `DIR` (`.agentic`, the folder under the vault),
`DRAFT` (`draft`, key of the note used before an agent exists).

### `tabs.agentic.create`

`open(opts?)` (`opts.manager`, `opts.name`, `opts.on_created`): the AgentCreate panel; returns the form.

### `tabs.agentic.actions`

`target(id?)`, `create(opts?)`, `stop(id?)`, `kill(id?)`, `delete(id?)`, `rename(id?, name?)`,
`move(id?, manager?)`, `pause(id?)`, `resume(id?)`, `toggle_pause(id?)`, `second_read(id?)`, `range_text(args)`,
`copy_to_write(args)`, `seed(args)`, `complete(lead)`.

### `tabs.agentic.send`

`run(args)` (the `AgentSend` body), `format(path, line1, line2, filetype, text)`. `TARGET` maps
`standard` → `agentic` and `system_standard` → `system_agentic`.

### `tabs.agentic.lsp_bridge`

`handle(meta, event)`: answer one `lsp_request` for the agent in `meta`. `SHORT` maps `hover`, `definition`,
`references`, `rename` to their `textDocument/*` methods.
