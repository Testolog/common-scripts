-- Read-only buffer for one agent's MCP client log (`mcp.log`).
local store = require("tabs.agentic.store")

local M = {}

M.FILE = store.MCP_LOG

local buffers = {}

local function shown(buf)
  local wins = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      wins[#wins + 1] = win
    end
  end
  return wins
end

local function write(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  local last = math.max(vim.api.nvim_buf_line_count(buf), 1)
  for _, win in ipairs(shown(buf)) do
    pcall(vim.api.nvim_win_set_cursor, win, { last, 0 })
  end
end

local function read_lines(dir)
  local path = vim.fs.joinpath(dir, M.FILE)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local lines = {}
  for line in f:lines() do
    lines[#lines + 1] = line
  end
  f:close()
  return lines
end

local function lock_buffer(buf)
  local blocked = function ()
    vim.notify("The MCP log is read-only.", vim.log.levels.INFO)
  end
  for _, key in ipairs({ "i", "I", "a", "A", "o", "O", "c", "C", "s", "S", "R", "x", "X", "p", "P", "d", "D", "u", "<C-r>" }) do
    vim.keymap.set("n", key, blocked, { buffer = buf, nowait = true, silent = true, desc = "read-only" })
  end
  vim.keymap.set("n", "q", function ()
    for _, win in ipairs(shown(buf)) do
      if vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end, { buffer = buf, nowait = true, silent = true, desc = "close MCP log" })
end

local function buffer_for(meta)
  local buf = buffers[meta.agent_id]
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "log"
  pcall(vim.api.nvim_buf_set_name, buf, "agentic://" .. meta.agent_id .. "/mcp.log")
  vim.b[buf].agentic_mcp_log = meta.agent_id
  lock_buffer(buf)
  buffers[meta.agent_id] = buf
  return buf
end

-- Open the selected agent's MCP log in a read-only split.
function M.open(meta)
  if not meta or not meta.agent_id or not meta.dir then
    return vim.notify("AgentMcpLog: select an agent first.", vim.log.levels.WARN)
  end
  local buf = buffer_for(meta)
  local lines = read_lines(meta.dir)
  if not lines or #lines == 0 then
    lines = { "No MCP log yet for " .. tostring(meta.name or meta.agent_id) .. "." }
  end
  write(buf, lines)
  local already
  for _, win in ipairs(shown(buf)) do
    already = win
    break
  end
  if already then
    vim.api.nvim_set_current_win(already)
  else
    vim.cmd("botright 12split")
    vim.api.nvim_win_set_buf(0, buf)
  end
  vim.wo.winbar = "%#Title# MCP log %* read-only · q closes"
  local last = vim.api.nvim_buf_line_count(buf)
  pcall(vim.api.nvim_win_set_cursor, 0, { last, 0 })
end

-- Append one live line when the log buffer is open.
function M.append(agent_id, text)
  local buf = buffers[agent_id]
  if not buf or not vim.api.nvim_buf_is_valid(buf) or text == nil or text == "" then
    return
  end
  local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if #current == 1 and current[1]:match("^No MCP log yet") then
    current = {}
  end
  current[#current + 1] = text
  write(buf, current)
end

return M
