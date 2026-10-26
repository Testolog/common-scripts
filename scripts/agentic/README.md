# agentic_client

Detached Python agent client for the Neovim Agentic tabs. One interface for
every vendor: **start, stream events, pause, resume, stop** (plus kill, delete,
rename, move).

## Install

```sh
python3 scripts/agentic/install.py          # venv at ~/agentic/.venv, links ~/.local/bin/agentic-client
python3 scripts/agentic/install.py --check  # only report whether `agent` and `serena` are on PATH
```

`scripts/system_agentic/install.py` passes its arguments to this installer unchanged.

Dependencies are pinned in `pyproject.toml` / `requirements.txt` (`mcp==1.29.1`,
the official MCP Python SDK). The installer does not install the Cursor CLI,
Serena, Ollama, or any model weights.

## Tests

```sh
cd scripts/agentic && PYTHONPATH=.:tests python3 -m unittest discover -s tests -v
```

No Cursor CLI, Ollama, or network is needed: the Cursor adapter runs against a
fake `agent` script and the local adapter against an in-process SSE server.

## State layout

```text
$HOME/agentic/<project_name>/<branch>/<manager>/<agent_id>/
  meta.json        absolute project root, branch, manager, agent id, model, mode, tokens, status
  transcript.md    read-only after a handoff; removed only by delete
  log              supervisor stdout/stderr
  mcp.log          MCP client log (connect, auth, tool calls). `:AgentMcpLog` opens it read-only
  supervisor.pid   present while the supervisor runs
  events.jsonl     event stream (reattach by reading from any offset)
  inbox.jsonl      commands for the supervisor
  messages.json    structured chat history used to re-send on resume
$HOME/agentic/<project_name>/<branch>/<manager>/handoff-<agent_id>.md
$HOME/agentic/mcp-auth/<server_name>/{tokens.json,client.json}
```

`<branch>` keeps `/` as nested directories; non-git is `nogit`, detached HEAD is
`detached`. Agents are found by walking for `meta.json`, never by depth.
`AGENTIC_HOME` overrides `$HOME/agentic` (used by tests).

## Python API (`import agentic_client`)

| Function | Purpose |
| --- | --- |
| `start(root, *, name, mode="ask", model="auto", manager="default", prompts=None, skills=None, message=None)` | Create state and launch the detached supervisor. `None` selects all prompts/skills. |
| `attach(agent_id)` | Reattach by id (returns `state.Agent`). |
| `events(agent_id, offset=0, follow=True)` | Yield event dicts; each carries `_offset` for resuming. |
| `send(agent_id, text)` | Queue a user message. |
| `pause(agent_id)` / `resume(agent_id)` | Cursor: stop/continue reading the live process. Local: abort the request / re-send the transcript. |
| `restart(agent_id)` | AgentStart: launch the supervisor again for an existing agent. Already running is a no-op. |
| `stop(agent_id)` | AgentStop: ask the supervisor to finish. |
| `kill(agent_id)` | AgentKill: SIGKILL the supervisor's process group. Transcript stays. |
| `delete(agent_id)` | AgentDelete: kill if alive and remove the directory. |
| `rename(agent_id, name)` / `move(agent_id, manager)` | AgentRename / AgentMove. |
| `attach_nvim(agent_id, pid)` / `detach_nvim(agent_id)` | Tell the supervisor Neovim can answer LSP requests. |
| `lsp_result(agent_id, request_id, text)` | Answer an `lsp_request` event. |
| `list_agents(root=None, running_only=False)` | One project+branch, or every agent. |
| `list_models(root)` | `{project, cursor, local, errors}` for the create panel. `cursor` is the stored system-project catalog, not a live CLI query. |
| `update_cursor_models()` | Ask the Cursor CLI and write `system_project/cursor_models.json`. |
| `mcp_status(root)` | MCP plan from `~/.cursor/mcp.json` + project `isActive`, without connecting. |

Lower-level modules: `state` (paths, discovery, meta), `project` (reads
`.nvim_project.json`), `tools` (policy and dispatch), `sse`, `adapters`
(`CursorAdapter`, `LocalAdapter`, `list_cursor_models`, `list_local_models`),
`mcp_catalog`, `mcp_client` (`McpManager`), `serena` (`serena_command`),
`context` (`estimate_tokens`, `open_tasks`, `handoff`), `supervisor`.

## CLI (`python -m agentic_client` or `agentic-client`)

Every command prints JSON. `start --root R --name N [--mode ask|edit] [--model M] [--manager P] [--prompts a,b] [--skills a,b] [--message T]`,
`events ID [--offset N] [--no-follow]`, `send ID [TEXT|stdin]`, `pause ID`,
`resume ID`, `stop ID`, `kill ID`, `delete ID`, `rename ID NAME`, `move ID MANAGER`,
`attach-nvim ID PID`, `detach-nvim ID`, `lsp-result ID REQUEST_ID [TEXT|stdin]`,
`list [--root R] [--running]`, `models --root R`, `update-cursor-models`, `mcp --root R`.
`supervise AGENT_DIR` is internal: `start` launches it detached.

The supervisor inherits the caller's environment. When `COMMON_SCRIPT` is unset it is set to the
checkout this client ships in (if that checkout has `system_project/`), so the template's
`$COMMON_SCRIPT/system_project/system_function/*.sh` tools and relative system prompt paths resolve.

## Events

`status`, `delta`, `thought`, `tool`, `usage`, `tokens`, `error`, `log`,
`lsp_request` (`id`, `tool`, `function` = Neovim client name, `arguments`), and
`tree` (`action`: `mcp_catalog`, `mcp_status`, `mcp_error`, `handoff` with
`child_id` and `switch_buffer: false`).

## Adapters

**Cursor** (`vendor: cursor`). Flags confirmed from `agent --help` (CLI
2026.07.09) and kept only in `adapters/cursor.py:cursor_command`:
`-p --output-format stream-json --stream-partial-output --trust --workspace <root>`,
`--model <m>` (omitted for `auto`), `--mode ask` for Ask agents, `--force` for
Edit agents, `--resume <chatId>` on later turns. The create panel reads
`system_project/cursor_models.json` and does not call the CLI. `update-cursor-models`
(`:CursorUpdateModelList`) runs `agent models` (fallback `agent --list-models`) and
rewrites that file. `AGENTIC_CURSOR_BIN` overrides the binary.

**Local** (`vendor: openai`, the OpenAI-compatible wire protocol, not
platform.openai.com). `POST {base_url}/chat/completions` with
`{model, messages, stream: true}`, SSE until `data: [DONE]`, `Authorization:
Bearer` only with `api_key`, `GET {base_url}/models`. Default base URL
`http://127.0.0.1:11434/v1`. Nothing listening raises `LocalServerNotRunning`
("local server is not running at ..."). Local models call project tools with a
fenced ```` ```tool {"name", "arguments"} ``` ```` block that the supervisor runs.

## Prompts, skills, tools

Read only from the project's `.nvim_project.json`: selected `system_prompt`
then `project_prompt`, selected `system_skills` then `project_skills`.
Absolute paths (copied `$COMMON_SCRIPT/...`) are used as stored; relative
project paths resolve under the project root. A skill folder contributes
`SKILL.md`, or every `*.md` inside it.

Tools: `kind` defaults to `shell` (`/bin/sh -c "<function> <quoted args>"`,
cwd = `meta.json` project root). `lsp` emits an `lsp_request` for Neovim; with
no Neovim attached it returns "No language server is attached". `mcp` calls
`function` as `server` (arguments `{tool, arguments}`) or `server/tool`.
Missing `mutates` means mutating; Ask mode refuses those and returns text.
`agent_rename` is always available and does not edit the project. One call renames one agent of this
project (`{"agent": "<agent id>", "name": "<new name>"}`). The base prompt shows that call.
Helpers: `tools.fsearch_args` (`find <pattern> [paths...]` / `find <pattern> -f`),
`tools.sd_args` (`<file> <old> <new>`; the wrapper owns the ambiguity check).

## MCP

`~/.cursor/mcp.json` (`AGENTIC_MCP_JSON` overrides) `mcpServers`: `url` with
missing/`http` type uses Streamable HTTP, `type: sse` uses SSE, command-only
entries are reported `unsupported` and never spawned, a parse error connects
nothing. Only servers with `isActive: true` in the project's `mcp_servers`
connect. When Cursor's own tool result says `needsAuth`, the supervisor runs
`agent mcp login <server>` and then continues the same task, so the agent is not left paused.
The model must not call `mcp_auth`. A direct URL connection from this client still uses the
SDK OAuth flow (browser callback on `http://127.0.0.1:33418/callback`,
tokens under `$HOME/agentic/mcp-auth/<server_name>/`) and can report
`connected` on its own. That does not clear Cursor's `needsAuth`.
HTTP 400 or 500 is tried at most three times; the server is then not contacted
again for that agent. Each of those steps is appended to the agent's `mcp.log`.
`:AgentMcpLog` opens that file in a read-only buffer.
Serena is started with `--agent-interface tools` and `--open-web-dashboard false`, so the agent
gets one tool per operation and Serena does not open a window on its own.

**Serena** is started per agent as a stdio MCP subprocess scoped to the
`meta.json` project root. The binary was not installed when this was written,
so the command is isolated in `serena.py:serena_command`:
`serena start-mcp-server --project <root>` (override with `AGENTIC_SERENA_CMD`,
`{root}` is substituted).

## Context handoff

Tokens come from stream usage when present, else `ceil(chars/4)` of the
transcript. Cursor's default `context_limit` is 200000. At the limit the
supervisor writes `handoff-<id>.md` in the manager folder, creates a child
agent under the same manager with the open `- [ ]` tasks and the summary in its
preamble, marks the old transcript read-only, emits a `tree`/`handoff` event,
starts the child's supervisor, and exits. No buffer is switched.
