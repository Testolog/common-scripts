-- Read context: one scratch buffer per agent. History comes from transcript.md, live output from
-- `agentic-client events`. Thoughts, tool/API calls, scripts, and logs are folds between explicit
-- markers (collapsed by default, nvim-ufo marker provider); the answer and file hunks stay expanded.
local client = require("tabs.agentic.client")
local store = require("tabs.agentic.store")
local state = require("tabs.agentic.state")

local M = {}

M.FOLD_OPEN = "{{{agentic"
M.FOLD_CLOSE = "}}}agentic"
M.FOLDMARKER = M.FOLD_OPEN .. "," .. M.FOLD_CLOSE
M.MAX_FOLD_LINES = 200
M.LSP_WINDOW = 60

-- [agent_id] = { buf, meta, job, offset, block, status, tokens, limit, read_only, snapshots, pending, answered }
local sessions = {}

local function ufo_loaded()
  return package.loaded["ufo"] ~= nil
end

local function windows_of(buf)
  return vim.fn.win_findbuf(buf)
end

local function set_lines(buf, first, last, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, first, last, false, lines)
  vim.bo[buf].modifiable = false
end

-- Append raw text, continuing the last line. Windows whose cursor was on the last line follow.
local function put(s, text)
  local buf = s.buf
  if not vim.api.nvim_buf_is_valid(buf) or text == nil or text == "" then
    return
  end
  local n = vim.api.nvim_buf_line_count(buf)
  local follow = {}
  for _, win in ipairs(windows_of(buf)) do
    if vim.api.nvim_win_get_cursor(win)[1] >= n then
      follow[#follow + 1] = win
    end
  end
  local last = vim.api.nvim_buf_get_lines(buf, n - 1, n, false)[1] or ""
  set_lines(buf, n - 1, n, vim.split(last .. text, "\n", { plain = true }))
  local count = vim.api.nvim_buf_line_count(buf)
  for _, win in ipairs(follow) do
    pcall(vim.api.nvim_win_set_cursor, win, { count, 0 })
  end
end

local function at_line_start(s)
  local n = vim.api.nvim_buf_line_count(s.buf)
  return (vim.api.nvim_buf_get_lines(s.buf, n - 1, n, false)[1] or "") == ""
end

local function lines(s, list)
  if not at_line_start(s) then
    put(s, "\n")
  end
  put(s, table.concat(list, "\n") .. "\n")
end

-- Apply nvim-ufo's marker folds now instead of waiting for its debounced update.
local function apply_ufo(buf)
  if not ufo_loaded() or #windows_of(buf) == 0 then
    return
  end
  pcall(function ()
    local ufo = require("ufo")
    local ranges = ufo.getFolds(buf, "marker")
    if type(ranges) == "table" then
      ufo.applyFolds(buf, ranges)
    end
  end)
end

local function close_new_fold(s, start)
  if not ufo_loaded() then
    return
  end
  vim.defer_fn(function ()
    if not vim.api.nvim_buf_is_valid(s.buf) then
      return
    end
    apply_ufo(s.buf)
    for _, win in ipairs(windows_of(s.buf)) do
      vim.api.nvim_win_call(win, function ()
        if vim.fn.foldclosed(start) == -1 and vim.fn.foldlevel(start) > 0 then
          pcall(vim.cmd, "silent! " .. start .. "foldclose")
        end
      end)
    end
  end, 300)
end

local function end_block(s)
  local block = s.block
  s.block = nil
  if not block then
    return
  end
  if block.fold then
    lines(s, { M.FOLD_CLOSE })
    close_new_fold(s, block.start)
  elseif not at_line_start(s) then
    put(s, "\n")
  end
end

-- A plain "---" is a Markdown rule and conceallevel hides it. Keep the dashes, with
-- box-drawing around them so the break between answers stays on screen.
M.RULE = "─────────── --- ───────────"

local function has_answer(s)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(s.buf, 0, -1, false)) do
    if line:match("^## Assistant") then
      return true
    end
  end
  return false
end

-- Switch to a streaming block of `kind` ("answer", "thought", "log"); same kind keeps appending.
local function begin_block(s, kind, title)
  if s.block and s.block.kind == kind then
    return
  end
  end_block(s)
  if kind == "answer" then
    local block = has_answer(s) and { "", M.RULE, "" } or {}
    vim.list_extend(block, { "", "## Assistant", "" })
    lines(s, block)
    s.block = { kind = kind }
  else
    lines(s, { "▸ " .. title .. " " .. M.FOLD_OPEN })
    s.block = { kind = kind, fold = true, start = vim.api.nvim_buf_line_count(s.buf) - 1 }
  end
end

local function truncate(list)
  if #list > M.MAX_FOLD_LINES then
    local out = vim.list_slice(list, 1, M.MAX_FOLD_LINES)
    out[#out + 1] = string.format("… %d more lines", #list - M.MAX_FOLD_LINES)
    return out
  end
  return list
end

-- A complete folded block.
local function fold(s, title, body)
  end_block(s)
  local list = { "▸ " .. title .. " " .. M.FOLD_OPEN }
  vim.list_extend(list, truncate(body))
  list[#list + 1] = M.FOLD_CLOSE
  lines(s, list)
  close_new_fold(s, vim.api.nvim_buf_line_count(s.buf) - #list)
end

-- Ids and clocks from the Cursor stream. They are not part of the thought.
local HIDDEN_KEYS = {
  toolCallId = true,
  hookAdditionalContexts = true,
  hookAdditionalContext = true,
  startedAtMs = true,
  completedAtMs = true,
}

local PREFERRED_KEYS = {
  mode = 1,
  namespace = 2,
  namespaceStatus = 3,
  namespaceError = 4,
  status = 5,
  error = 6,
  server = 7,
  name = 8,
  tools = 9,
  content = 10,
  message = 11,
  text = 12,
}

local function decode_json(text)
  if type(text) ~= "string" then
    return nil
  end
  local trimmed = vim.trim(text)
  local first, last = trimmed:sub(1, 1), trimmed:sub(-1)
  if not ((first == "{" and last == "}") or (first == "[" and last == "]")) then
    return nil
  end
  local ok, value = pcall(vim.json.decode, trimmed, { luanil = { object = true, array = true } })
  if ok and type(value) == "table" then
    return value
  end
end

local function unwrap(value)
  if type(value) == "string" then
    return decode_json(value) or value
  end
  if type(value) ~= "table" or vim.islist(value) then
    return value
  end
  local only
  for key in pairs(value) do
    if not HIDDEN_KEYS[key] then
      if only then
        return value
      end
      only = key
    end
  end
  if only == "success" or only == "content" or only == "result" then
    return unwrap(value[only])
  end
  return value
end

local function sorted_keys(tbl)
  local keys = {}
  for key in pairs(tbl) do
    if not HIDDEN_KEYS[key] then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys, function (a, b)
    local pa, pb = PREFERRED_KEYS[a] or 100, PREFERRED_KEYS[b] or 100
    if pa ~= pb then
      return pa < pb
    end
    return tostring(a) < tostring(b)
  end)
  return keys
end

local function markdown_lines(value, depth)
  depth = depth or 0
  if depth > 6 then
    return { "…" }
  end
  value = unwrap(value)
  if value == nil then
    return {}
  end
  if type(value) ~= "table" then
    local text = tostring(value)
    if text == "" then
      return { "_empty_" }
    end
    return vim.split(text, "\n", { plain = true })
  end
  if vim.islist(value) then
    if #value == 0 then
      return { "_none_" }
    end
    local out = {}
    for _, item in ipairs(value) do
      local parts = markdown_lines(item, depth + 1)
      out[#out + 1] = "- " .. (parts[1] or "")
      for i = 2, #parts do
        out[#out + 1] = "  " .. parts[i]
      end
    end
    return out
  end
  local keys = sorted_keys(value)
  if #keys == 0 then
    return { "_none_" }
  end
  local out = {}
  for _, key in ipairs(keys) do
    local parts = markdown_lines(value[key], depth + 1)
    local one = #parts == 1 and not parts[1]:find("\n", 1, true) and #parts[1] < 160
    if one and not parts[1]:match("^[#*-]") then
      out[#out + 1] = "**" .. tostring(key) .. "**  " .. parts[1]
    else
      out[#out + 1] = "**" .. tostring(key) .. "**"
      out[#out + 1] = ""
      for _, line in ipairs(parts) do
        out[#out + 1] = line
      end
      out[#out + 1] = ""
    end
  end
  while out[#out] == "" do
    out[#out] = nil
  end
  return out
end

local function text_lines(value)
  if value == nil then
    return {}
  end
  return markdown_lines(value, 0)
end

-- ---------------------------------------------------------------------------------------------
-- File hunks

local function abspath(s, path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if path:sub(1, 1) == "/" then
    return vim.fs.normalize(path)
  end
  return vim.fs.normalize(vim.fs.joinpath(s.meta.project_root or vim.fn.getcwd(), path))
end

local function relpath(s, path)
  local root = (s.meta.project_root or "") .. "/"
  if path:sub(1, #root) == root then
    return path:sub(#root + 1)
  end
  return path
end

local function hunk(s, path, old, new)
  old = old or ""
  new = new or ""
  if old ~= "" and old:sub(-1) ~= "\n" then
    old = old .. "\n"
  end
  if new ~= "" and new:sub(-1) ~= "\n" then
    new = new .. "\n"
  end
  local ok, diff = pcall(vim.diff, old, new, { result_type = "unified", ctxlen = 3 })
  if not ok or not diff or diff == "" then
    return false
  end
  end_block(s)
  local rel = relpath(s, path)
  local list = { "", "```diff", "--- a/" .. rel, "+++ b/" .. rel }
  local body = vim.split(diff, "\n", { plain = true, trimempty = true })
  vim.list_extend(list, truncate(body))
  vim.list_extend(list, { "```", "" })
  lines(s, list)
  return true
end

local function first_string(tbl, keys)
  if type(tbl) ~= "table" then
    return nil
  end
  for _, key in ipairs(keys) do
    if type(tbl[key]) == "string" then
      return tbl[key]
    end
  end
end

local PATH_KEYS = { "path", "file_path", "filePath", "target_file", "targetFile", "file" }
local OLD_KEYS = { "old_string", "oldString", "old_str", "oldText", "old" }
local NEW_KEYS = { "new_string", "newString", "new_str", "newText", "new" }
local CONTENT_KEYS = { "fileText", "contents", "content", "file_text" }

-- (name, args, result) of a tool event from either adapter.
local function tool_info(ev)
  if type(ev.tool_call) == "table" then
    for key, value in pairs(ev.tool_call) do
      if type(value) == "table" and key:match("ToolCall$") then
        return key:gsub("ToolCall$", ""), value.args or {}, value.result
      end
    end
    return "tool", ev.tool_call, nil
  end
  return ev.name or "tool", ev.arguments, nil
end

local function tool_file(name, args)
  if type(args) ~= "table" then
    return nil
  end
  if vim.islist(args) then
    if (name == "sd" or name == "dasel") and type(args[1]) == "string" then
      return args[1]
    end
    return nil
  end
  return first_string(args, PATH_KEYS)
end

local function inline_patch(args)
  local list = type(args) == "table" and args or { args }
  for _, value in pairs(list) do
    if type(value) == "string" and value:find("\n@@", 1, true) then
      return value
    end
  end
end

local function tool_summary(name, args)
  if type(args) == "table" then
    local summary = first_string(args, { "command", "cmd", "pattern", "query" }) or tool_file(name, args)
    if not summary and vim.islist(args) then
      summary = table.concat(vim.tbl_map(tostring, args), " ")
    end
    if summary then
      summary = summary:gsub("\n.*", " …")
      return name .. ": " .. (#summary > 80 and (summary:sub(1, 80) .. "…") or summary)
    end
  elseif type(args) == "string" then
    return name .. ": " .. args:gsub("\n.*", " …")
  end
  return name
end

local function on_tool(s, ev, live)
  local name, args, res = tool_info(ev)
  local key = name
  if ev.subtype == "started" then
    s.pending[key] = args
    local path = abspath(s, tool_file(name, args))
    if live and path then
      s.snapshots[path] = store.read_file(path) or ""
    end
    fold(s, "tool " .. tool_summary(name, args), text_lines(args))
    return
  end
  if ev.subtype ~= "completed" then
    fold(s, "tool " .. name .. " " .. tostring(ev.subtype or ""), text_lines(ev.tool_call or ev))
    return
  end
  if type(args) ~= "table" or next(args) == nil then
    args = s.pending[key] or args
  end
  s.pending[key] = nil
  if ev.ok ~= nil or ev.refused ~= nil then
    local verdict = ev.refused and "refused (Ask mode)" or (ev.ok and "ok" or "failed")
    end_block(s)
    lines(s, { "  ↳ " .. name .. ": " .. verdict })
  elseif res ~= nil then
    fold(s, "result " .. name, text_lines(res))
  end
  local patch = inline_patch(args)
  if patch then
    end_block(s)
    local list = { "", "```diff" }
    vim.list_extend(list, truncate(vim.split(patch, "\n", { plain = true, trimempty = true })))
    vim.list_extend(list, { "```", "" })
    lines(s, list)
    return
  end
  local path = abspath(s, tool_file(name, args))
  if not path then
    return
  end
  local snapshot = s.snapshots[path]
  s.snapshots[path] = nil
  if snapshot and hunk(s, path, snapshot, store.read_file(path) or "") then
    return
  end
  local old, new = first_string(args, OLD_KEYS), first_string(args, NEW_KEYS)
  if old or new then
    hunk(s, path, old, new)
    return
  end
  local content = first_string(args, CONTENT_KEYS)
  if content then
    hunk(s, path, "", content)
  end
end

-- ---------------------------------------------------------------------------------------------
-- Winbar

local function esc(text)
  return (tostring(text or ""):gsub("%%", "%%%%"))
end

local function fmt_tokens(n)
  n = tonumber(n)
  if not n then
    return "?"
  end
  if n >= 1000 then
    return string.format("%.1fk", n / 1000)
  end
  return tostring(n)
end
M.fmt_tokens = fmt_tokens

function M.winbar(s)
  local meta = s.meta
  local model = type(meta.model) == "table" and meta.model.name or meta.model
  local parts = {
    "%#Title# " .. esc(meta.name or meta.agent_id) .. " %*",
    esc(s.status or meta.status or "?"),
    fmt_tokens(s.tokens or meta.tokens) .. "/" .. fmt_tokens(s.limit or meta.context_limit),
    esc(meta.mode),
    esc(model),
  }
  if type(s.queue) == "table" and #s.queue > 0 then
    parts[#parts + 1] = "queue " .. #s.queue
  end
  if s.read_only or meta.read_only then
    parts[#parts + 1] = "%#WarningMsg#read-only%*"
  end
  return table.concat(parts, " · ")
end

local function refresh_winbar(s)
  local bar = M.winbar(s)
  for _, win in ipairs(windows_of(s.buf)) do
    vim.wo[win].winbar = bar
  end
end

local tree_pending = false
local function refresh_trees()
  if tree_pending then
    return
  end
  tree_pending = true
  vim.defer_fn(function ()
    tree_pending = false
    pcall(function ()
      require("tabs.agentic.tree").refresh_all()
    end)
  end, 500)
end

-- ---------------------------------------------------------------------------------------------
-- Events

local QUIET_STATUS = { running = true, idle = true, attached = true, created = true }
local render_transcript

local function on_event(s, ev, live)
  local kind = ev.type
  if kind == "user" then
    M.echo_user(s.meta.agent_id, ev.text or "")
  elseif kind == "queue" then
    s.queue = type(ev.items) == "table" and ev.items or {}
    refresh_winbar(s)
  elseif kind == "preamble" then
    end_block(s)
    render_transcript(s)
  elseif kind == "delta" then
    begin_block(s, "answer")
    put(s, ev.text or "")
  elseif kind == "thought" then
    begin_block(s, "thought", "thought")
    local text = ev.text or ""
    local decoded = decode_json(text)
    if decoded then
      put(s, table.concat(markdown_lines(decoded), "\n"))
    else
      put(s, text)
    end
  elseif kind == "log" then
    begin_block(s, "log", "log")
    put(s, (ev.text or "") .. "\n")
  elseif kind == "mcp_log" then
    require("tabs.agentic.mcp_log").append(s.meta.agent_id, ev.text or "")
  elseif kind == "tool" then
    on_tool(s, ev, live)
  elseif kind == "usage" then
    refresh_winbar(s)
  elseif kind == "tokens" then
    s.tokens, s.limit = ev.tokens, ev.limit
    refresh_winbar(s)
    refresh_trees()
  elseif kind == "status" then
    local status = tostring(ev.status or "")
    if not status:match("^cursor:") and status ~= "attached" then
      s.status = status
      if not QUIET_STATUS[status] then
        end_block(s)
        lines(s, { "", "_status: " .. status .. "_" })
      end
      if status ~= "running" and s.block and s.block.kind == "answer" then
        end_block(s)
      end
      refresh_winbar(s)
      refresh_trees()
    end
  elseif kind == "error" then
    local body = text_lines(ev.error)
    end_block(s)
    lines(s, { "", "> **error** " .. (body[1] or "") })
    if #body > 1 then
      fold(s, "error details", vim.list_slice(body, 2))
    end
  elseif kind == "lsp_request" then
    fold(s, "lsp " .. tostring(ev.tool) .. " (" .. tostring(ev["function"]) .. ")", text_lines(ev.arguments))
    if live and ev.id and not s.answered[ev.id] and (tonumber(ev.ts) or 0) >= os.time() - M.LSP_WINDOW then
      s.answered[ev.id] = true
      require("tabs.agentic.lsp_bridge").handle(s.meta, ev)
    end
  elseif kind == "tree" then
    M.on_tree_event(s, ev)
  end
end

function M.on_tree_event(s, ev)
  local name = s.meta.name or s.meta.agent_id
  local id = s.meta.agent_id
  local u_each = state.agentic_tabs()
  if ev.action == "handoff" then
    s.read_only = true
    s.meta.read_only = true
    end_block(s)
    lines(s, {
      "",
      "> **handoff**: context limit reached. Continued in agent `" .. tostring(ev.child_id) .. "`.",
      "> Summary: " .. tostring(ev.summary or "?") .. ". This transcript is read-only.",
    })
    refresh_winbar(s)
    -- switch_buffer is false: notify only, the visible buffer stays on this transcript.
    state.notice("handoff: " .. name .. " → " .. tostring(ev.child_id) .. " (old transcript read-only)", vim.log.levels.WARN, id)
    vim.notify("Agent " .. name .. " handed off to " .. tostring(ev.child_id) .. "; select it in the tree to continue.",
      vim.log.levels.WARN)
  elseif ev.action == "renamed" then
    M.update_meta({ agent_id = tostring(ev.agent_id or ""), name = ev.name })
    refresh_trees()
  elseif ev.action == "mcp_error" then
    for _, entry in ipairs(u_each) do
      entry.ui.mcp_errors[tostring(ev.server)] = tostring(ev.error)
    end
    state.notice("mcp " .. tostring(ev.server) .. ": " .. tostring(ev.error), vim.log.levels.WARN, id)
  elseif ev.action == "mcp_catalog" then
    if ev.error then
      state.notice("mcp.json: " .. tostring(ev.error), vim.log.levels.ERROR, id)
    end
  elseif ev.action == "mcp_status" then
    local summary = {}
    for server, status in pairs(type(ev.status) == "table" and ev.status or {}) do
      summary[#summary + 1] = server .. "=" .. (type(status) == "table" and vim.inspect(status) or tostring(status))
    end
    if #summary > 0 then
      state.notice("mcp " .. name .. ": " .. table.concat(summary, ", "), vim.log.levels.INFO, id)
    end
  end
end

-- ---------------------------------------------------------------------------------------------
-- History

-- transcript.md with "## Tool" / "## User (tool)" sections folded.
function render_transcript(s)
  local text = store.read_file(vim.fs.joinpath(s.meta.dir, store.TRANSCRIPT)) or ""
  local out, in_fold = {}, false
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    local header = line:match("^## (.+)$")
    if header then
      if in_fold then
        out[#out + 1] = M.FOLD_CLOSE
        in_fold = false
      end
      if header == "Tool" or header:match("%(tool%)$") then
        out[#out + 1] = "▸ " .. header:lower() .. " result " .. M.FOLD_OPEN
        in_fold = true
      else
        out[#out + 1] = line
      end
    elseif line == "---" then
      out[#out + 1] = M.RULE
    else
      out[#out + 1] = line
    end
  end
  if in_fold then
    out[#out + 1] = M.FOLD_CLOSE
  end
  if s.meta.read_only then
    vim.list_extend(out, {
      "",
      "> **handoff**: continued in agent `" .. tostring(s.meta.handoff_to or "?") .. "`. This transcript is read-only.",
    })
  end
  out[#out + 1] = ""
  set_lines(s.buf, 0, -1, out)
end

-- Byte offset to stream from: the start of the turn in progress, else the end of events.jsonl.
local SETTLED = { idle = true, paused = true, stopped = true, error = true, handed_off = true, killed = true, created = true }
local function resume_offset(s)
  local fh = io.open(vim.fs.joinpath(s.meta.dir, store.EVENTS), "rb")
  if not fh then
    return 0
  end
  local pos, turn_start = 0, nil
  for line in fh:lines() do
    local start = pos
    pos = pos + #line + 1
    if line:find('"status"', 1, true) then
      local ok, ev = pcall(vim.json.decode, line)
      if ok and type(ev) == "table" and ev.type == "status" then
        if ev.status == "running" then
          turn_start = turn_start or start
        elseif SETTLED[ev.status] then
          turn_start = nil
        end
      end
    end
  end
  fh:close()
  return turn_start or pos
end

local function start_stream(s)
  if s.job then
    pcall(vim.fn.jobstop, s.job)
    s.job = nil
  end
  local id = s.meta.agent_id
  s.job = client.events(id, s.offset, function (ev)
    if ev._offset then
      s.offset = ev._offset
    end
    if vim.api.nvim_buf_is_valid(s.buf) then
      on_event(s, ev, true)
    end
  end, function ()
    s.job = nil
    if vim.api.nvim_buf_is_valid(s.buf) then
      end_block(s)
      refresh_trees()
    end
  end)
end

local function setup_buffer(s)
  local buf = s.buf
  vim.b[buf].agentic_read = true
  vim.b[buf].agentic_agent_id = s.meta.agent_id
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  pcall(vim.api.nvim_buf_set_name, buf, "agentic://" .. s.meta.agent_id .. "/read")
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
  require("tabs.agentic.keymaps").read_buffer(buf)
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function ()
      local id = s.meta.agent_id
      if s.job then
        pcall(vim.fn.jobstop, s.job)
      end
      if s.attached then
        client.detach_nvim(id)
      end
      sessions[id] = nil
    end,
  })
end

-- Session for `meta`, creating its buffer, loading history, attaching Neovim, and following events.
function M.session(meta)
  local s = sessions[meta.agent_id]
  if s and vim.api.nvim_buf_is_valid(s.buf) then
    s.meta = vim.tbl_extend("force", s.meta, meta)
    return s
  end
  s = {
    buf = vim.api.nvim_create_buf(false, true),
    meta = meta,
    snapshots = {},
    pending = {},
    answered = {},
    status = meta.status,
    tokens = meta.tokens,
    limit = meta.context_limit,
    read_only = meta.read_only,
  }
  sessions[meta.agent_id] = s
  setup_buffer(s)
  local queued = store.read_file(vim.fs.joinpath(meta.dir, "queue.json"))
  if queued and queued ~= "" then
    local ok, items = pcall(vim.json.decode, queued)
    s.queue = ok and type(items) == "table" and items or {}
  end
  render_transcript(s)
  s.offset = resume_offset(s)
  if meta.alive then
    s.attached = true
    client.attach_nvim(meta.agent_id)
    start_stream(s)
  end
  return s
end

function M.get(agent_id)
  local s = sessions[agent_id]
  if s and vim.api.nvim_buf_is_valid(s.buf) then
    return s
  end
end

-- Window options for a window showing a read buffer.
function M.configure_window(win, s)
  local wo = vim.wo[win]
  wo.foldmarker = M.FOLDMARKER
  wo.foldmethod = ufo_loaded() and "manual" or "marker"
  wo.foldenable = true
  wo.foldlevel = 0
  wo.wrap = true
  wo.linebreak = true
  wo.spell = false
  wo.number = false
  wo.relativenumber = false
  wo.conceallevel = 2
  wo.winbar = M.winbar(s)
  vim.api.nvim_win_call(win, function ()
    if not vim.w.agentic_marker_match then
      vim.w.agentic_marker_match = vim.fn.matchadd("Conceal", [[\V{{{agentic\|}}}agentic]], 10, -1, { conceal = "" })
    end
    if not vim.w.agentic_rule_match then
      vim.api.nvim_set_hl(0, "AgenticRule", { link = "Title" })
      vim.w.agentic_rule_match = vim.fn.matchadd("AgenticRule", [[\V─────────── --- ───────────]])
    end
  end)
  vim.schedule(function ()
    if vim.api.nvim_buf_is_valid(s.buf) then
      apply_ufo(s.buf)
    end
  end)
end

-- Echo a submitted user message (the transcript gets it from the supervisor).
function M.echo_user(agent_id, text)
  local s = M.get(agent_id)
  if not s then
    return
  end
  end_block(s)
  local list = { "", "## User", "" }
  vim.list_extend(list, vim.split(text, "\n", { plain = true }))
  list[#list + 1] = ""
  lines(s, list)
end

-- Restart the event stream (after a move the agent directory changes).
function M.restart(meta)
  local s = M.get(meta.agent_id)
  if not s then
    return
  end
  s.meta = vim.tbl_extend("force", s.meta, meta)
  if meta.alive then
    start_stream(s)
  end
end

-- Update name/status from fresh meta without touching the content.
function M.update_meta(meta)
  local s = M.get(meta.agent_id)
  if s then
    s.meta = vim.tbl_extend("force", s.meta, meta)
    refresh_winbar(s)
  end
end

function M.wipe(agent_id)
  local s = sessions[agent_id]
  if s and vim.api.nvim_buf_is_valid(s.buf) then
    pcall(vim.api.nvim_buf_delete, s.buf, { force = true })
  end
  sessions[agent_id] = nil
end

-- Lines of the current block under the cursor: fenced code, fold body, or paragraph.
function M.current_block(buf, lnum)
  local all = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local function find_fence()
    local open
    for i = 1, #all do
      if all[i]:match("^```") then
        if open then
          if lnum > open and lnum < i then
            return vim.list_slice(all, open + 1, i - 1)
          end
          open = nil
        else
          open = i
        end
      end
    end
  end
  local fence = find_fence()
  if fence then
    return fence
  end
  local depth, start = 0, nil
  for i = lnum, 1, -1 do
    if all[i]:find(M.FOLD_CLOSE, 1, true) and i ~= lnum then
      depth = depth + 1
    elseif all[i]:find(M.FOLD_OPEN, 1, true) then
      if depth == 0 then
        start = i
        break
      end
      depth = depth - 1
    end
  end
  if start then
    for i = math.max(lnum, start + 1), #all do
      if all[i]:find(M.FOLD_CLOSE, 1, true) then
        return vim.list_slice(all, start + 1, i - 1)
      end
    end
  end
  local first, last = lnum, lnum
  while first > 1 and all[first - 1] ~= "" do
    first = first - 1
  end
  while last < #all and all[last + 1] ~= "" do
    last = last + 1
  end
  return vim.list_slice(all, first, last)
end

return M
