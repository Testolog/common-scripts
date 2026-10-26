-- Write context: a Markdown note per agent inside the tab vault (<vault>/.agentic/notes/<agent_id>.md),
-- so obsidian.nvim (0.11+) renders it and nvim-cmp's markdown sources (path, $ENV, project keys) apply.
-- Submit sends the note to the running agent through the Python client and clears it.
local client = require("tabs.agentic.client")
local store = require("tabs.agentic.store")
local state = require("tabs.agentic.state")

local M = {}

M.DIR = ".agentic"
M.DRAFT = "draft"

function M.notes_dir(vault)
  return vim.fs.joinpath(vault, M.DIR, "notes")
end

local function ensure_dir(vault)
  local base = vim.fs.joinpath(vault, M.DIR)
  vim.fn.mkdir(M.notes_dir(vault), "p")
  local ignore = vim.fs.joinpath(base, ".gitignore")
  if not vim.uv.fs_stat(ignore) then
    local fh = io.open(ignore, "w")
    if fh then
      fh:write("*\n")
      fh:close()
    end
  end
end

function M.note_path(vault, key)
  return vim.fs.joinpath(M.notes_dir(vault), key .. ".md")
end

local function vault()
  return require("tabs.runtime").vault() or vim.fn.getcwd()
end

local function save(buf)
  if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified then
    vim.api.nvim_buf_call(buf, function ()
      vim.cmd("silent! update")
    end)
  end
end

local function is_obsidian_field(line)
  return line == "" or line:match("^id:") or line:match("^aliases:") or line:match("^tags:")
end

-- obsidian.nvim writes id/aliases/tags in front of a vault note. The write note is the
-- message itself, so that header is never part of the text. A header with no closing
-- "---" is dropped only when it contains nothing but those three fields.
local function strip_frontmatter(lines)
  if lines[1] ~= "---" then
    return lines
  end
  for i = 2, #lines do
    if lines[i] == "---" then
      return vim.list_slice(lines, i + 1)
    end
  end
  for i = 2, #lines do
    if not is_obsidian_field(lines[i]) then
      return lines
    end
  end
  return {}
end

-- Buffer of the note `key` (agent id or "draft") in the current tab vault.
function M.buffer(key, v)
  v = v or vault()
  ensure_dir(v)
  local path = M.note_path(v, key)
  if not vim.uv.fs_stat(path) then
    local fh = io.open(path, "w")
    if fh then
      fh:close()
    end
  end
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  vim.bo[buf].buflisted = false
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  if vim.bo[buf].filetype ~= "markdown" then
    vim.bo[buf].filetype = "markdown"
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local body = strip_frontmatter(lines)
  if #body ~= #lines then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, body)
    save(buf)
  end
  if not vim.b[buf].agentic_write then
    vim.b[buf].agentic_write = key
    require("tabs.agentic.keymaps").write_buffer(buf)
    vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "BufLeave" }, {
      buffer = buf,
      callback = function ()
        if vim.bo[buf].modified then
          vim.api.nvim_buf_call(buf, function ()
            vim.cmd("silent! update")
          end)
        end
      end,
    })
  end
  return buf
end

function M.text(buf)
  local lines = strip_frontmatter(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  return vim.trim(table.concat(lines, "\n"))
end

function M.set_text(buf, text)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text == "" and {} or vim.split(text, "\n", { plain = true }))
  save(buf)
end

-- Append `text` (separated by a blank line) without submitting.
function M.append(buf, text)
  local current = M.text(buf)
  local lines = vim.split(text, "\n", { plain = true })
  if current == "" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  else
    table.insert(lines, 1, "")
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
  end
  save(buf)
end

-- Move the draft note's text into the note of `agent_id` (used after AgentCreate).
function M.adopt_draft(agent_id)
  local draft = M.buffer(M.DRAFT)
  local text = M.text(draft)
  if text == "" then
    return
  end
  M.append(M.buffer(agent_id), text)
  M.set_text(draft, "")
end

-- A line that is exactly "---" separates requests. Each one is sent in order.
-- While this agent is answering, later requests wait and run when it is free.
local function requests(text)
  local parts, current = {}, {}
  local function flush()
    local chunk = vim.trim(table.concat(current, "\n"))
    if chunk ~= "" then
      parts[#parts + 1] = chunk
    end
    current = {}
  end
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    if line == "---" then
      flush()
    else
      current[#current + 1] = line
    end
  end
  flush()
  return parts
end

local function send_next(key, parts, index, buf, queued)
  if index > #parts then
    if vim.api.nvim_buf_is_valid(buf) then
      M.set_text(buf, "")
    end
    if queued then
      local msg = #parts == 1
        and "Queued 1 request. It runs on this agent after the current answer finishes."
        or string.format("Queued %d requests. They run on this agent after the current answer finishes.", #parts)
      vim.notify(msg, vim.log.levels.INFO)
    elseif #parts > 1 then
      vim.notify(
        string.format("The first request is running. %d more %s queued on this agent.",
          #parts - 1, #parts - 1 == 1 and "is" or "are"),
        vim.log.levels.INFO
      )
    end
    return
  end
  client.send(key, parts[index], function (_, err)
    if err then
      return vim.notify("AgentSubmit: " .. err, vim.log.levels.ERROR)
    end
    send_next(key, parts, index + 1, buf, queued)
  end)
end

-- Send the composer of the selected agent (or the note in `buf`).
function M.submit(buf)
  local u = state.get()
  buf = buf or vim.api.nvim_get_current_buf()
  local key = vim.b[buf].agentic_write
  if not key then
    key = u and u.agent_id
    buf = key and M.buffer(key) or nil
  end
  if not key or key == M.DRAFT or not buf then
    return vim.notify("No agent selected; create one with :AgentCreate first. The draft is kept.", vim.log.levels.WARN)
  end
  local meta = store.find(key)
  if not meta then
    return vim.notify("Agent " .. key .. " no longer exists.", vim.log.levels.WARN)
  end
  if meta.read_only then
    return vim.notify("Agent " .. (meta.name or key) .. " is read-only after a handoff; select " ..
      tostring(meta.handoff_to or "its child") .. " in the tree.", vim.log.levels.WARN)
  end
  if not meta.alive then
    return vim.notify("Agent " .. (meta.name or key) .. " is not running (status " .. tostring(meta.status) ..
      "). Start it with :AgentStart. The message stays in the write buffer.", vim.log.levels.WARN)
  end
  local text = M.text(buf)
  if text == "" then
    return vim.notify("The write buffer is empty.", vim.log.levels.INFO)
  end
  local parts = requests(text)
  if #parts == 0 then
    return vim.notify("The write buffer is empty.", vim.log.levels.INFO)
  end
  local busy = meta.status == "running" or meta.status == "paused"
  send_next(key, parts, 1, buf, busy)
end

return M
