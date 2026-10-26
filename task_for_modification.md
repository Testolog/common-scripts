# Neovim Agentic Tabs

Iteration 15. This prompt is the source of truth. The decisions from the previous rounds are locked below. No open requirement points remain.

Existing repo facts the prompt must respect:

* Neovim config root: `nvim/`
* Entry: `nvim/init.lua` loads `lazy.nvim` from `plugins/` and then `main.load()`
* Project file: `.nvim_project.json` (`nvim/lua/constants.lua` → `project_file_name`)
* Loader today: `nvim/lua/main.lua` walks upward for `.nvim_project.json`, fills built-in keys such as `name` and `lua`, and sets `project.root`. A missing file is created. That creation step must write the system-project defaults described below, and later reads use the local file as it is stored.
* Current project fields already in use include `name`, `lua`, `yaml`, `json`, `ssh_key`, `arduino`
* Plugins already present and preferred over new ones: `lazy.nvim`, `nvim-tree.lua`, `nui.nvim`, `telescope.nvim`, `nvim-cmp`, `nvim-ufo`, `edgy.nvim`, `snacks.nvim`, `which-key.nvim`, `mason.nvim`
* `render-markdown.nvim` is already installed. Leave its lazy spec commented out for now. Do not load it. Markdown rendering comes from `obsidian.nvim`.
* Markdown writing plugin to add: [`obsidian.nvim`](https://github.com/obsidian-nvim/obsidian.nvim). It needs Neovim 0.11 or newer and `ripgrep`. It does not need the Obsidian desktop app.
* `$COMMON_SCRIPT` is the shell location of this common-scripts checkout (see `init.sh`)

---

## Implementation prompt

Build a tab-scoped Neovim workspace on top of the current config. A tab is a Neovim tabpage bound to one mode and one folder root. A window is a Neovim window. A buffer is a Neovim buffer. A context is the LLM chat stored for one agent. A mode is a tab dedicated to one feature set. A command is a Neovim user command, also reachable from a UI panel. `nvim_project` is `.nvim_project.json`. An agent is the running chat: process, transcript, tools, and status.

Ship these modes:

1. **Agentic Tab** — control and watch agents for the tab's folder.
2. **Standard Tab** — the current editing workspace, moved behind a tab package without changing editing behavior.
3. **System Standard Tab** — Standard mode locked to `$COMMON_SCRIPT`.
4. **System Agentic Tab** — Agentic mode locked to `$COMMON_SCRIPT`.
5. **System project** — the global project at `$COMMON_SCRIPT`: the template for a new project's `.nvim_project.json` (prompts, skills, tools), and a view of every running agent across all projects. It is business logic, not a plugin loader.

Switch modes with the normal tab motions (`gt`, `gT`, `{count}gt`) and with user commands that open each mode. Each tab records its mode and its folder. Opening a file from a tab keeps that tab's folder as the scope. An Agentic tab shows the agentic tree, never the standard file tree. A Standard tab shows the standard file tree, never the agentic tree.

User commands:

`AgenticTab`, `EditTab`, `SystemEditTab`, `SystemAgenticTab`, `AgentCreate`, `AgentStop`, `AgentKill`, `AgentDelete`, `AgentRename`, `AgentMove`, `AgentSend`, `SystemProjectInit`.

### Packages, plugins, and keymaps

```text
nvim/lua/tabs/shared/          # overlapping dependencies, loaded by lazy.nvim
nvim/lua/tabs/agentic/         # Agentic Tab package + README.md
nvim/lua/tabs/standard/        # Standard Tab package + README.md
nvim/lua/tabs/system_standard/
nvim/lua/tabs/system_agentic/
nvim/lua/system_project/       # loader for $COMMON_SCRIPT/system_project
scripts/agentic/
scripts/standard/
scripts/system_standard/
scripts/system_agentic/
scripts/system_project/
nvim/schema/nvim_project.schema.json
```

* One Lua package per tab, with its own plugin list, keymap table, and `README.md` at the package root. The README lists every user command and every public function.
* Shared dependencies live in `nvim/lua/tabs/shared/`. `lazy.nvim` loads tab packages and the shared package together. Do not fork a second plugin manager.
* Register keymaps for the active tab only. On tab enter, apply that tab's maps. On tab leave, remove that tab's maps so another tab cannot trigger them.
* Filetype extras that belong to one tab load only while that tab is active. `obsidian.nvim` writes and renders Markdown for the Standard tab and the Agentic tab, including their system variants. The existing markdown ftplugin (wrap, linebreak, spell, `j`/`k` over wrapped lines) stays. `render-markdown.nvim` stays commented out.
* External tools install through Python scripts under `scripts/<tab_name>/`.
* Per-tab settings live in `.nvim_project.json`, keyed by tab name.
* Reuse an installed plugin when it already does the job.
* Search to new plugins which can do better job

Move the existing `nvim/lua/plugins/*` specs and the editing setup they configure into the Standard Tab package. Keep `init.lua` as the thin loader. Behavior of the current Standard editing session stays the same after the move. Move exists functionalty in most of the into standard tab or move into shared

### Agentic Tab

This tab manages agents for its folder. Its commands monitor and control agents: create, start, stop, pause, delete, move, rename. Configuration is that folder's `.nvim_project.json`. The agent reads this file and does not merge it with `$COMMON_SCRIPT` at runtime.

When a project is created, or when its `.nvim_project.json` does not exist yet, write that file with the defaults from the system project at `$COMMON_SCRIPT`. Copy every system prompt, every system skill, and every system tool into the new file. Also copy the system project's `models` and `mcp_servers` (`name` and `isActive` only). Paths in the copied prompt, skill, and tool entries point at the files under `$COMMON_SCRIPT/system_project/`. Copy `prompts/base.md` always. Copy `prompts/java.md` when `java` is one of the project's kinds. Copy `prompts/data.md` when the project contains yaml, avsc, json, or sql files. A project can have several kinds at once. `project_prompt`, `project_skills`, and `project_tools` start empty so the project can add its own later. Opening a project that already has `.nvim_project.json` leaves that file unchanged.

Persist every agent log and related file under the home directory, split by project name and git branch:

```text
$HOME/agentic/<project_name>/<branch>/<manager_path>/<agent_id>/
  meta.json          # includes the absolute project root and the branch
  transcript.md
  log
  supervisor.pid
```

`<project_name>` is the `name` field of `.nvim_project.json`, falling back to the directory basename. `<branch>` is `git rev-parse --abbrev-ref HEAD` in that project root, with `/` kept as nested directories (`feature/foo` is `.../feature/foo/`). A directory that is not a git checkout uses `nogit`. A detached HEAD uses `detached`. Two checkouts that share a project name and a branch share that directory. Agents survive Neovim exit: the Python client is a detached supervisor, and reopening Neovim attaches by agent id. Stop and delete are the only ways to end an agent. State lives outside the project tree, so it is not committed with the project. Switching git branches switches which agent directory the tree shows.

Find agents by `meta.json`, not by a fixed path depth. `meta.json` records the absolute project root, the branch, the manager path, and the agent id. A nested branch and a nested manager folder stay distinct because those fields, not the number of directories, define the tree.

Two adapters sit behind one Python client interface: start, stream events, pause, resume, stop. The supervisor process stays alive either way, so Neovim can reattach after it quits.

**Cursor.** The primary vendor. The adapter starts the Cursor CLI (`agent`) as a subprocess and reads its event stream. Pause stops consuming that stream. Resume continues the same process. Stop and kill end it.

**Local models.** A local model is a program on this machine that has already loaded the weights and is listening for HTTP. The Python adapter does not load weights itself. It sends a chat request to that program. `vendor: "openai"` means the OpenAI chat protocol, not the OpenAI company and not a key from platform.openai.com.

The request is `POST {base_url}/chat/completions` with JSON `{ "model", "messages", "stream": true }`. `messages` is the selected prompts, skills, and transcript. The response is a server-sent event stream: lines of `data: {"choices":[{"delta":{"content":"..."}}]}`, then `data: [DONE]`. If the model entry has `api_key`, send it as `Authorization: Bearer`. Ollama and most local servers accept a missing key. The create panel also calls `GET {base_url}/models` and shows those names next to the names stored in `.nvim_project.json`.

Ollama is the local program this refers to. Its OpenAI-compatible base URL is `http://127.0.0.1:11434/v1`. The same adapter works for any other server that implements that path, including LM Studio at `http://127.0.0.1:1234/v1` and `llama-server` at `http://127.0.0.1:8080/v1`. Changing `base_url` is how you switch them. No separate Ollama protocol is required.

For this adapter, pause and stop abort the in-flight HTTP request and keep the transcript. Resume sends the transcript again as a new request. There is no model process for the client to signal.

A model entry looks like this. `base_url` is required when `vendor` is `openai` and is omitted for `cursor`.

```json
{
  "name": "qwen2.5-coder:7b",
  "vendor": "openai",
  "context_limit": 32768,
  "base_url": "http://127.0.0.1:11434/v1"
}
```

Do not install Ollama and do not download model weights. If nothing is listening at `base_url`, the create panel says the local server is not running.

Default layout:

* Left: `agentic tree` (about 30% width). This is the status and control surface.
* Right: `agentic buffer`.
  * Upper: `read context`.
  * Lower: `write context`, 20% of the agentic buffer height, expandable to a full window and collapsible back to 20%.

One selected agent fills the read and write panes. Selecting another tree node swaps both panes. A second read buffer opens only when the user asks for it.

Each tab stores `mode` and `root`. The root is fixed when the tab opens (`tcd` to that root). New files and agent tools resolve against that root. Two Agentic tabs may point at two folders in one Neovim session.

#### Window: agentic tree

A file-tree style view of agents for the tab's project root. Build it on `nvim-tree` behavior, or a thin tree UI on `nui.nvim` if nvim-tree cannot show a virtual agent tree. Do not show the project file tree in this tab.

Requirements:

* List every agent stored under `$HOME/agentic/<project_name>/<branch>/` for this tab's project and branch. The system project is the exception: its tree lists every running agent under `$HOME/agentic/`, across all projects and branches (see System project).
* Navigate agents the way `nvim-tree` navigates files.
* Delete, stop, kill, move, and rename an agent.
* Show stats on the node or in a detail pane: creation time, last modified time, token usage, context window size.
* Group agents in sub-folders. A folder is a manager. Agents inside it are workers for that manager (actor style). Moving an agent changes its manager.
* Command `AgentCreate` (`create agent/context/chat`).

##### Command: create agent/context/chat

Open a panel (use `nui.nvim`, already installed) with:

* **Name** — text. The agent may rename itself later through a tool.
* **Prompts** — multi-select. Sources are `system_prompt` and `project_prompt` in this project's `.nvim_project.json`. Default selection is all of them. Those arrays were filled from the system project when the file was created.
* **Skills** — multi-select. Sources are `$.system_skills[]` and `$.project_skills[]`. Default selection includes the base skill folder.
* **Mode** — `Ask` or `Edit`.
* **Model** — one model from this project's `models` array. The Cursor adapter also offers models the CLI reports. The panel shows the union. Each catalog entry is `{ "name", "vendor", "context_limit" }` where `vendor` is `cursor` or `openai` (the OpenAI-compatible local endpoint).

Load prompt files in array order: all selected `system_prompt` entries, then all selected `project_prompt` entries, from this project's file. Skills load from the selected `system_skills`, then `project_skills`, from the same file. Each entry is `{ "name": string, "path": string }`. Copied system paths resolve under `$COMMON_SCRIPT`. Paths the project added later resolve relative to the project root.

Track context size and the model token limit (`context_limit`, Cursor default 200000). When the limit is reached, the client writes a handoff summary into the manager folder, creates a new agent context as a child of the same manager, copies the open task list and the summary into the new system preamble, notifies in the tree, and leaves the old transcript open and read-only. It does not switch the visible buffer until the user selects the new agent.

Modes:

* **Edit** — the agent may read, write, delete, and execute inside the tab's project root, using tools whose `mutates` flag is true and tools whose `mutates` flag is false.
* **Ask** — read-only. The client refuses every tool with `mutates: true`, and refuses a tool that omits `mutates` (treat missing as mutating). Results come back as text. If have any suggestion to write need to ask user to do, in that case will create a new agent with instruction and monitor him and review ensure there is all installed properly.

Tools come from `system_tools` and `project_tools` in this project's `.nvim_project.json`. Every system tool was copied into `system_tools` when the file was created, regardless of `project_type`. For `kind: "shell"`, `function` is a shell command run with the tab's project root as the working directory, and the agent arguments are appended. For `kind: "lsp"`, `function` is a Neovim LSP request. The language server is already attached in Neovim, so the agent client calls back into Neovim instead of running sed or awk. `name` is the tool name shown to the model. `description` is the model-facing help. `kind` defaults to `shell` when it is omitted.

Creating an agent opens it in the `agentic buffer`.

The agent process is a Python client, installed by `scripts/agentic/`. Closing the read buffer does not stop the process. Only an explicit stop, kill, or delete does. Quitting Neovim does not stop it either. `AgentStop` asks the supervisor to finish. `AgentKill` terminates the supervisor immediately. The transcript stays on disk until delete.

#### MCP

The first implementation includes a working MCP client. The connection catalog starts at `~/.cursor/mcp.json`. That file is a JSON object whose `mcpServers` value is a map of server name to config. A config may contain `url`, `headers`, and `type`. This client connects to entries that have `url`. `type` of `http`, or a missing `type`, uses MCP Streamable HTTP. `type` of `sse` uses MCP over SSE. An entry that only has `command` is shown in the tree as unsupported and is not spawned.

`isActive` is a boolean meaning "use this server". It is not written into `~/.cursor/mcp.json`, so Cursor can keep owning that file. The system project's `.nvim_project.json` holds the template `mcp_servers[]` of `{ "name", "isActive" }`. Creating a project copies that array into the new project's `.nvim_project.json`. The client reads `isActive` from the project file it is running in. It connects, lists tools, and calls tools only when that project's `isActive` is true. A server present in `~/.cursor/mcp.json` and absent from the project file, or present with `isActive` false, stays off. Startup does not open an authorization browser for every server. Changing the template later does not change existing project files until the system project's update command writes the new values into those files.

When an active server requires authorization, open the system browser, finish the MCP login, and store the resulting token under `$HOME/agentic/mcp-auth/<server_name>/`. Retry the connection after a successful login. Inactive servers never open a browser. If `~/.cursor/mcp.json` does not parse, report the error in the agentic tree and connect no servers from it. Connection and tool errors also show in the tree. Do not copy server URLs into each project's `.nvim_project.json`.

#### Schema to append

Add the fields below to `.nvim_project.json`. Keep every field that already exists (`name`, `lua`, `yaml`, `json`, `ssh_key`, `arduino`, and any other key). Write the merged schema to `nvim/schema/nvim_project.schema.json`.

`mutates` defaults to true when absent, so Ask mode stays read-only.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "nvim_project",
  "type": "object",
  "properties": {
    "project_type": {
      "type": "array",
      "items": { "type": "string" }
    },
    "system_prompt": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "path": { "type": "string" }
        },
        "required": ["name", "path"]
      }
    },
    "system_skills": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "path": { "type": "string" }
        },
        "required": ["name", "path"]
      }
    },
    "project_prompt": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "path": { "type": "string" }
        },
        "required": ["name", "path"]
      }
    },
    "project_skills": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "path": { "type": "string" }
        },
        "required": ["name", "path"]
      }
    },
    "system_tools": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "function": { "type": "string" },
          "description": { "type": "string" },
          "mutates": { "type": "boolean" },
          "kind": { "type": "string", "enum": ["shell", "lsp", "mcp"] }
        },
        "required": ["name", "function", "description"]
      }
    },
    "project_tools": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "function": { "type": "string" },
          "description": { "type": "string" },
          "mutates": { "type": "boolean" },
          "kind": { "type": "string", "enum": ["shell", "lsp", "mcp"] }
        },
        "required": ["name", "function", "description"]
      }
    },
    "models": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "vendor": { "type": "string", "enum": ["cursor", "openai"] },
          "context_limit": { "type": "integer" },
          "base_url": { "type": "string" },
          "api_key": { "type": "string" }
        },
        "required": ["name", "vendor", "context_limit"]
      }
    },
    "mcp_servers": {
      "type": "array",
      "description": "Activation overlay for servers declared in ~/.cursor/mcp.json. Connection url and headers come from that file.",
      "items": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "isActive": { "type": "boolean" }
        },
        "required": ["name", "isActive"]
      }
    }
  }
}
```

The system project file at `$COMMON_SCRIPT/system_project/.nvim_project.json` is the template. Its prompt, skill, and tool paths point at files under `$COMMON_SCRIPT/system_project`. A new project's `.nvim_project.json` is a copy of those defaults plus the project's own `name`, `lua`, and other existing keys. After that write, the project file stands alone. URLs for MCP stay in `~/.cursor/mcp.json`.

#### Window: agentic buffer

A normal Neovim buffer pair for one selected agent.

* **Read context** shows history, actions, and thoughts.
* **Write context** is the message composer under it.

Normal mode in the read buffer navigates and yanks. Insert mode in the write buffer composes the next user message. Submit sends that message to the running agent. Insert into read buffer is restricted. 

##### Buffer: read context

* Standard Neovim text motions and the tab's plugins work here.
* File changes render as inline hunks that match the file contents, in the Cursor style, inside the transcript.
* Thoughts, API calls, and temporary scripts render as separate collapsible blocks. They start collapsed. The main answer stays expanded and is not folded away. Use `nvim-ufo`, which is already installed, with an explicit fold marker for those blocks.
* Prefer a readable wrap and easy line yank over a dense status UI.
* Closing the window leaves the agent running.
* Write into read buffer restricted, if need to edit or build new agentic or append into context, selected text or current block could be used for start point to create agentic or use to modify input context 

##### Buffer: write context

* `obsidian.nvim` is the writing and rendering plugin for this buffer. The project root (the directory of `.nvim_project.json`) is the vault. The write buffer is a Markdown note inside that vault, so wiki links, tags, note search, backlinks, and `:Obsidian` commands work while composing a message. Rendering is the plugin's own display: concealed links, inline embeds, and checkboxes. Use Telescope as the picker.
* Note and tag completion comes from `obsidian.nvim` (`[[`, `#`). `nvim-cmp` still completes file paths, environment variables, and keys from this project's `.nvim_project.json`. A separate custom LSP is a later iteration, only if those sources are not enough.
* Do not load `render-markdown.nvim`. Comment out its existing lazy spec and leave a note that it is deferred. The Obsidian desktop app is not required.
* The window sits under read context, occupies 20% of the agentic buffer height, can expand to fill the agentic area, and can collapse back to 20%.
* The same vault and plugin are used when this tab is the System Agentic tab. That vault is `$COMMON_SCRIPT`.

### Standard Tab

The everyday Neovim workspace for every filetype. Move the current configuration into the Standard Tab package. After the move, opening Neovim with no mode command still lands in a Standard tab with the same plugins, keymaps, and LSP behavior as today.

`obsidian.nvim` is the main Markdown writing and rendering plugin in this tab. The open project's root is the vault. Markdown files there get wiki-link completion, `:Obsidian search`, `:Obsidian quick_switch`, follow-link, backlinks, tags, new-note commands, and the plugin's own rendered display. The System Standard tab uses the same plugin with `$COMMON_SCRIPT` as the vault. `render-markdown.nvim` stays commented out.

`AgentSend` works on any visual selection in this tab, for any filetype. It opens the Agentic tab for the same project and asks the user to create a new context or pick an existing one for that project and branch. The selection is placed in that context's write buffer, with the source file path and line range. It is not submitted until the user sends the message. Creating a context opens the `AgentCreate` panel with that text already in the write buffer. Picking an existing context switches the read and write panes to that agent and appends the text to the write buffer. The System Standard tab has the same command. A command with no visual selection reports that nothing is selected.

### System Standard Tab

A Standard tab whose folder is always `$COMMON_SCRIPT/system_project`, including when `getcwd()` is somewhere else. It uses the Standard package and the system project file.

### System Agentic Tab

An Agentic tab whose folder is always `$COMMON_SCRIPT/system_project`. It uses the Agentic package and the system project file. It does not follow the caller's cwd. Agents created here live in `$HOME/agentic/<system_project_name>/<branch>/`.

The tree in this tab is the cross-project view. It lists every running agent under `$HOME/agentic/`, grouped by project name, then branch, then manager. A running agent is one whose detached supervisor is alive. Stopped agents stay in their own project's tree and do not appear here. Selecting an agent opens its read and write buffers. Stop, kill, delete, move, and rename from this tree act on that agent. `AgentKill` is available here so any running agent, in any project, can be killed when you choose to. Nothing is killed automatically. Tool execution and file changes still use the project root recorded in that agent's `meta.json`, not `$COMMON_SCRIPT`.

### System project

The checkout at `$COMMON_SCRIPT` is the global project. `SystemProjectInit` creates this tree if it is missing. This tree is the template copied into `.nvim_project.json` when a project is created:

```text
$COMMON_SCRIPT/system_project/
  prompts/base.md            # always copied
  prompts/java.md            # example kind prompt, copied when java is detected
  prompts/data.md            # copied when the project has yaml, avsc, json, or sql files
  skills/base/               # base skill folder
  system_function/           # fsearch, sd, dasel, ast-grep wrappers
```

`project_type` is a list of kinds found in the folder. One Standard tab edits all of them. One Agentic tab talks to the agent. Do not add a tab per language or per file kind.

Detect kinds from the project root:

* `java` — `pom.xml`, `build.gradle`, `build.gradle.kts`, or `project_type` already contains `"java"`.
* `yaml` — any `*.yml` or `*.yaml`.
* `avsc` — any `*.avsc`.
* `json` — any `*.json` other than `.nvim_project.json`.
* `sql` — any `*.sql`.

* **One base system prompt** at `prompts/base.md`, referenced by `system_prompt`.
* **Base skills** in `skills/base/`, referenced by `system_skills`.
* **`prompts/data.md`.** yaml, avsc, json, and sql are project files. Edit them with `sd`, `dasel`, or `git apply`. Use LSP only when a server is attached to that buffer.
* **`prompts/java.md`.** Rename Java symbols with `lsp_rename`. Use `ast-grep` for a repeated syntactic rewrite. Use `sd` or `git apply` for a one-off text change.
* **All system tools are available to every project**, whatever kinds it has.
* **First system tools, in this order:**
  * `fsearch` (`kind: shell`, `mutates: false`). File and content search. Command form: `fsearch find <pattern> [paths…]` from the project root, and `fsearch find <pattern> -f` to search inside files. The wrapper sets depth so the search covers the project. The CLI's own default depth is 1. Do not use `find`. Do not use `fzf`. If the `fsearch` command is missing, `scripts/system_project/` installs the latest from `https://github.com/cumulus13/fsearch` with `cargo install --git https://github.com/cumulus13/fsearch`. The binary name is `fsearch`.
  * `sd` (`kind: shell`, `mutates: true`). Literal edit of any text file. The agent passes the file, the exact old text, and the new text. The wrapper uses `sd -F` and refuses the call when the old text matches more than once. Install with `scripts/system_project` when missing.
  * `dasel` (`kind: shell`, `mutates: true`). Field edit for yaml, json, avsc, toml, xml, and csv. The agent passes a selector and a value. Install when missing.
  * `ast-grep` (`kind: shell`, `mutates: true`). Structural rewrite for a repeated code or yaml or json pattern. Command form: `sg -p <pattern> -l <lang> -r <rewrite>`. No SQL. Avsc uses `dasel` or the JSON grammar. Install when missing.
  * `git apply` (`kind: shell`, `mutates: true`). Unified diff for a multi-hunk edit of any text file. Already installed. Use it when `sd` or `dasel` does not fit.
  * `lsp_hover`, `lsp_definition`, `lsp_references` (`kind: lsp`, `mutates: false`) and `lsp_rename` (`kind: lsp`, `mutates: true`). Call the language server already attached in Neovim. `lsp_rename` is how a code symbol is renamed. If no server is attached, or the server cannot rename, say so and use `sd`, `dasel`, or `git apply`. Do not start a second language server. Do not rename with sed or awk.
* **Serena.** Install the latest release with `uv tool install -p 3.13 --upgrade serena-agent` from `scripts/system_project`. Do not install it from an MCP marketplace. The `serena` command must be on `PATH`. Each agent starts Serena for that agent's project root, including a different root from the system project, and uses Serena to navigate and modify that project. `system_tools` includes `{ "name": "serena", "kind": "mcp", "function": "serena", "mutates": true }`.
* **Language servers already configured in Neovim** (`nvim/lua/languages.lua`) are entries in the system project's `system_tools`, so every new project file copies them. The agent uses these servers, through the `lsp_*` tools, together with Serena. Do not configure a parallel server for the same language.

  | `name` | Neovim client | Role |
  | --- | --- | --- |
  | `lua_ls` | `lua_ls` | Lua |
  | `yamlls` | `yamlls` | YAML |
  | `jsonls` | `jsonls` | JSON |
  | `taplo` | `taplo` | TOML |
  | `jdtls` | `jdtls` | Java, when `jenv javahome` returns a JDK |
  | `pyright` | `pyright` | Python types |
  | `ruff` | `ruff` | Python diagnostics and format; hover is disabled |
  | `rust_analyzer` | `rust_analyzer` | Rust |
  | `clangd` | `clangd` | C and C++ |
  | `arduino_language_server` | `arduino_language_server` | Arduino sketches |

  SQL is `sqlfluff` through none-ls (Spark dialect), for diagnostics and format. It is not a rename server. Each entry is `{ "name", "function", "description", "kind": "lsp", "mutates": false }` except the mutating calls, which stay on `lsp_rename`. `function` is the Neovim client name.

The system project also stores a catalog of known projects. An explicit update command writes template changes into each project's `.nvim_project.json`. It does not happen on read. Inside the system project, the agentic tree shows all running agents across all projects: walk `$HOME/agentic/`, read each `meta.json`, and keep the agents whose supervisor is alive. Group them by project name and branch. This view is part of the System Agentic tab. A normal Agentic tab still shows only the agents for its own project and branch. MCP connection details are read from `~/.cursor/mcp.json`. Each project file's copied `mcp_servers[].isActive` flags decide which of those servers that project uses. Wrappers are business logic on top of the tab framework. They do not load plugins. Jenkins and Kubernetes were examples in the first spec; they are not part of this iteration.

### Execution order

1. Tab runtime: mode id, folder root, lazy spec per tab, keymap apply/clear on `TabEnter` / `TabLeave`, commands to open each mode.
2. Move the current config into the Standard package and prove the editing session still works.
3. Schema, `SystemProjectInit`, and project creation that writes `.nvim_project.json` from the system-project template (base prompt, kind prompts, base skills, `fsearch`, `sd`, `dasel`, `ast-grep`, `git apply`, LSP tools, the Neovim language-server list, Serena, `mcp_servers` flags).
4. Python agent client (Cursor CLI, OpenAI-compatible local models, MCP from `~/.cursor/mcp.json`) and `scripts/agentic` installer. Detached supervisor. State under `$HOME/agentic/<project_name>/<branch>/`. Browser login for MCP servers that require it.
5. Agentic tree, create-agent panel, read buffer, write buffer, cmp sources.
6. System Standard tab and System Agentic tab bound to `$COMMON_SCRIPT`.

### Acceptance

* Two projects can be open in two tabs; each tab only sees its own folder, tree, and maps.
* Switching tabs swaps keymaps. A Standard-tab map does not fire in an Agentic tab, and the reverse.
* Creating an agent writes a transcript under `$HOME/agentic/<project_name>/<branch>/` and shows it in the tree and the read buffer. Another branch of the same project has its own directory.
* The agent is still running after the read buffer is closed and after Neovim quits. Stop and delete are explicit.
* Ask mode cannot run a mutating shell tool. Edit mode can.
* File search tools invoke `fsearch find`. A missing `fsearch` binary is installed from `https://github.com/cumulus13/fsearch`.
* `sd` changes one exact occurrence in any text file and refuses an ambiguous match. `dasel` edits yaml, json, avsc, toml, xml, and csv fields. `ast-grep` rewrites a repeated pattern. `git apply` applies a multi-hunk diff.
* `lsp_rename` renames through the language server already attached in Neovim. The agent does not rename with sed or awk, and the `lsp_*` tools do not start a second server.
* Serena is the latest `serena-agent` from uv. An agent uses Serena, scoped to its own project root, to navigate and modify that project.
* The system project's `system_tools` lists `lua_ls`, `yamlls`, `jsonls`, `taplo`, `jdtls`, `pyright`, `ruff`, `rust_analyzer`, `clangd`, and `arduino_language_server`. A new project file contains that list.
* A project of yaml, avsc, json, or sql files gets `prompts/data.md`. A Java project gets `prompts/java.md`. A project can receive both.
* Creating a project writes `.nvim_project.json` containing the system project's prompts, skills, and tools, including only the kind prompts that match the folder. An existing `.nvim_project.json` is not rewritten on open.
* Servers in `~/.cursor/mcp.json` appear in the tree. A server connects only when `isActive` is true in that project's `.nvim_project.json`. The client uses the server `url`, lists tools, and can call a tool. A server that needs login opens a browser and stores the token under `$HOME/agentic/mcp-auth/<server_name>/`.
* System Standard and System Agentic always use `$COMMON_SCRIPT`, even when launched from another cwd.
* The System Agentic tree lists every running agent under `$HOME/agentic/`, from every project and branch. From that tree, `AgentKill` terminates the selected agent's supervisor immediately. A killed agent leaves the cross-project list. Its transcript remains until delete. A stopped agent is absent there and still visible in its own project's Agentic tab. Opening one of those agents uses that agent's project root for tools.
* A tab's root stays the folder it was opened on.
* Reaching the model token limit opens a child context with a handoff summary and leaves the old transcript read-only.
* Each package has a root Markdown file of its commands and functions.
* Existing `.nvim_project.json` files still load. New keys are optional.
* Write-context completion offers paths, environment variables, and project JSON keys through `nvim-cmp`.
* In the Standard tab and the Agentic write buffer, `obsidian.nvim` writes and renders Markdown. Each project root is a vault. Wiki links, tags, embeds, and `:Obsidian search` work in both. `render-markdown.nvim` is commented out and not loaded. The Obsidian desktop app is not required.
* `AgentSend` on a visual selection in the Standard tab opens the Agentic tab, lets the user create a new context or choose an existing one, and puts the selected text in that context's write buffer with the source path and line range. The message is not submitted by the command.

---

## Locked

* **P1.** Packages live in this repo: `nvim/lua/tabs/<tab>/` and `scripts/<tab>/`.
* **P2.** Agents survive Neovim exit. The detached supervisor reconnects by agent id.
* **P3.** First cut talks to the Cursor CLI, a local OpenAI-compatible chat endpoint (Ollama at `http://127.0.0.1:11434/v1` by default), and live MCP servers.
* **P4.** Three panes: tree, read context, write context at 20% of the agentic buffer.
* **P5.** A tool `function` is a shell command run from the project root. Schema includes `mutates`. Missing `mutates` means mutating.
* **P6.** At the token limit, open a child context with a handoff summary. The old transcript stays read-only. The visible buffer does not switch by itself.
* **P7.** Write-context completion is `nvim-cmp` sources. A custom LSP is a later iteration.
* **P8.** `models[]` of `{ "name", "vendor", "context_limit", "base_url"?, "api_key"? }` in the project file. `vendor` is `cursor` or `openai`. `openai` means `POST {base_url}/chat/completions`. `base_url` is required for that vendor. The Cursor CLI's own model list is added in the create panel.
* **P9.** System project ships `prompts/base.md`, `prompts/java.md`, `prompts/data.md`, `skills/base/`, and `system_function/`. Search uses `fsearch`. `prompts/data.md` tells the agent to edit yaml, avsc, json, and sql with `sd`, `dasel`, or `git apply`. `prompts/java.md` tells the agent to rename symbols with `lsp_rename`, repeat a syntactic rewrite with `ast-grep`, and make a one-off text change with `sd` or `git apply`.
* **P10.** One selected agent fills the read and write panes.
* **P11.** Commands: `AgenticTab`, `EditTab`, `SystemEditTab`, `SystemAgenticTab`, `AgentCreate`, `AgentStop`, `AgentKill`, `AgentDelete`, `AgentRename`, `AgentMove`, `AgentSend`, `SystemProjectInit`.
* **P12.** Tab root is fixed at open via `tcd`.
* **P13.** State root is `$HOME/agentic/<project_name>/<branch>/`, outside the git tree. A branch keeps its `/` as nested directories. Non-git uses `nogit`. Detached HEAD uses `detached`. Agents are discovered from `meta.json`.
* **P14.** MCP catalog is `~/.cursor/mcp.json`. HTTP and SSE URL servers are supported. The system project holds the template `mcp_servers[]`. A new project file receives a copy. The client reads `isActive` from the project file. Missing `isActive` means off. Browser authorization stores tokens under `$HOME/agentic/mcp-auth/<server_name>/`.
* **P15.** `project_type` is a string array of kinds, for example `["java"]` or `["yaml", "avsc", "json", "sql"]`. Kinds do not create tabs. Every system tool is available to every project. The first tools, in order, are `fsearch`, `sd`, `dasel`, `ast-grep`, `git apply`, and the LSP tools.
* **P16.** `java` is one kind among others. It matches when any one signal is present: `pom.xml`, `build.gradle`, `build.gradle.kts`, or `project_type` contains `"java"`. That copies `prompts/java.md`. It does not filter tools and it does not exclude `prompts/data.md`.
* **P17.** The system project shows every running agent across all projects. The System Agentic tree walks `$HOME/agentic/`, groups by project name and branch, and lists agents whose supervisor is alive. `AgentKill` from that tree terminates the selected supervisor immediately, in any project, only when you run it. Actions on an agent use the project root in its `meta.json`.
* **P18.** A new project starts with its own `.nvim_project.json`, written from the system project at `$COMMON_SCRIPT`. The copy includes every system prompt, skill, and tool, plus the template `models` and `mcp_servers`. The Java prompt is included when the project is Java. Runtime does not merge the system file over the project file. An existing project file is left as stored. Template changes reach existing projects only through an explicit update command that writes their files.
* **P19.** The local-model adapter only connects. It does not install Ollama or download weights. The default `base_url` is `http://127.0.0.1:11434/v1`. A server that is not running is reported in the create panel.
* **P20.** [`obsidian.nvim`](https://github.com/obsidian-nvim/obsidian.nvim) writes and renders Markdown for the Standard tab and the Agentic write buffer. The vault is the project root, or `$COMMON_SCRIPT` for the system tabs. Telescope is the picker. Note and tag completion come from the plugin. `nvim-cmp` still completes paths, environment variables, and project JSON keys. `render-markdown.nvim` stays commented out and is not loaded. The Obsidian desktop app is not required.
* **P21.** First system tools, in order: `fsearch` (`fsearch find`, installed from `https://github.com/cumulus13/fsearch` when the command is missing), `sd` (`sd -F`, refuse when the old text matches more than once), `dasel`, `ast-grep` (`sg -p <pattern> -l <lang> -r <rewrite>`, no SQL), `git apply`, then `lsp_hover`, `lsp_definition`, `lsp_references`, and `lsp_rename`. The `lsp_*` tools call the Neovim client already attached. They do not start a second language server. If rename is unavailable, the agent uses `sd`, `dasel`, or `git apply`.
* **P22.** Serena is installed with `uv tool install -p 3.13 --upgrade serena-agent` and is not taken from an MCP marketplace. Each agent runs Serena against that agent's project root and uses it, with the Neovim LSP tools, to navigate and modify the project. The system project's `system_tools` lists the language servers already set up in `nvim/lua/languages.lua`: `lua_ls`, `yamlls`, `jsonls`, `taplo`, `jdtls`, `pyright`, `ruff`, `rust_analyzer`, `clangd`, and `arduino_language_server`. SQL diagnostics and format stay on `sqlfluff` through none-ls.
* **P23.** From the Standard tab, `AgentSend` takes any visual selection and moves to the Agentic tab for the same project. The user creates a new context or selects an existing one. The selection, source path, and line range are written into that context's write buffer and are not submitted until the user sends them.

## Iteration log

* Iteration 1: original spec (terminology, goals, four tab modes, system project, schema fragment).
* Iteration 2: spec rewritten as an implementation prompt. Open decisions were P1–P12.
* Iteration 3: P1, P2, P3, P5, P7, and P9 locked. Agent state was still `<project_root>/agentic/`. MCP was still stdio.
* Iteration 4: P4, P6, P8, P10, P11, P12, and P15 locked. Agent state was `$HOME/agentic/<project_key>/`. MCP was a hand-written HTTP list on the system project. All system tools are available to every project.
* Iteration 5: Agent state is `$HOME/agentic/<project_name>/<branch>/`. MCP connections are read from `~/.cursor/mcp.json`. `isActive` on the system project decides which servers every project uses. Servers that need login use the browser. Java is any one of the build-file or `project_type` signals.
* Iteration 6: Branch names nest on `/`. Missing `isActive` stays off. No open requirement points remain.
* Iteration 7: The system project lists every running agent across all projects. A project Agentic tab stays limited to its own project and branch. `AgentKill` from that cross-project tree terminates the selected supervisor on demand.
* Iteration 8: A new `.nvim_project.json` is created from the system-project template (prompts, skills, tools). Runtime no longer merges the system project over the local file.
* Iteration 9: Local models are an OpenAI chat-completions endpoint. Ollama's default base URL is `http://127.0.0.1:11434/v1`. `models[]` gains `base_url` and `api_key`. The client connects only; it does not install the server or the weights.
* Iteration 10: `obsidian.nvim` is the writing plugin for the Standard tab and the Agentic write buffer. Each project root is a vault.
* Iteration 11: `obsidian.nvim` also renders Markdown. `render-markdown.nvim` stays commented out and is not loaded.
* Iteration 12: Java is one project kind. yaml, avsc, json, and sql are kinds too, and they do not get their own tabs. First system tools were `fzf`, `edit_file`, and LSP rename, hover, definition, and references.
* Iteration 13: `edit_file` is removed. First tools are `fzf`, `sd`, `dasel`, `ast-grep`, `git apply`, and the Neovim LSP tools. Serena is the latest `serena-agent`, scoped to each agent's project. The system project `system_tools` lists the language servers already configured in Neovim.
* Iteration 14: File search is `fsearch` from `https://github.com/cumulus13/fsearch`, installed with `cargo install --git` when the `fsearch` command is missing. `fzf` is not the search tool.
* Iteration 15: `AgentSend` copies a Standard-tab visual selection into a new or existing Agentic context for the same project. The text waits in the write buffer.
