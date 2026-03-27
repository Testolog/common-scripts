local M = {}

local entries = {}
local bufnr_log = nil
local winid_log = nil

local function timestamp()
  return os.date("%H:%M:%S")
end

local function capture_notify()
  local orig = vim.notify
  vim.notify = function(msg, level, opts)
    level = level or vim.log.levels.INFO
    if level == vim.log.levels.ERROR or level == vim.log.levels.WARN then
      local level_str = (level == vim.log.levels.ERROR) and "ERROR" or "WARN"
      table.insert(entries, string.format("[%s] [%s] %s", timestamp(), level_str, tostring(msg)))
    end
    return orig(msg, level, opts)
  end
end

local function ensure_buf()
  if bufnr_log and vim.api.nvim_buf_is_valid(bufnr_log) then
    return bufnr_log
  end
  bufnr_log = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr_log, "error-log://")
  vim.api.nvim_buf_set_option(bufnr_log, "bufhidden", "hide")
  vim.api.nvim_buf_set_option(bufnr_log, "filetype", "log")
  return bufnr_log
end

local function entries_to_lines()
  if #entries == 0 then
    return { "-- no errors captured yet --" }
  end
  local lines = {}
  for _, s in ipairs(entries) do
    for _, line in ipairs(vim.split(tostring(s), "\n", { plain = true })) do
      table.insert(lines, line)
    end
  end
  return lines
end

local function fill_buf()
  local buf = ensure_buf()
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  local lines = entries_to_lines()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

function M.append(msg, level)
  level = level or vim.log.levels.ERROR
  local level_str = (level == vim.log.levels.WARN) and "WARN" or "ERROR"
  table.insert(entries, string.format("[%s] [%s] %s", timestamp(), level_str, tostring(msg)))
  if bufnr_log and vim.api.nvim_buf_is_valid(bufnr_log) then
    vim.api.nvim_buf_set_option(bufnr_log, "modifiable", true)
    local new_lines = vim.split(tostring(entries[#entries]), "\n", { plain = true })
    vim.api.nvim_buf_set_lines(bufnr_log, -1, -1, false, new_lines)
    vim.api.nvim_buf_set_option(bufnr_log, "modifiable", false)
  end
end

function M.clear()
  entries = {}
  if bufnr_log and vim.api.nvim_buf_is_valid(bufnr_log) then
    vim.api.nvim_buf_set_option(bufnr_log, "modifiable", true)
    vim.api.nvim_buf_set_lines(bufnr_log, 0, -1, false, { "-- log cleared --" })
    vim.api.nvim_buf_set_option(bufnr_log, "modifiable", false)
  end
end

function M.toggle()
  if winid_log and vim.api.nvim_win_is_valid(winid_log) then
    vim.api.nvim_win_close(winid_log, true)
    winid_log = nil
    return
  end
  fill_buf()
  vim.cmd("tabnew")
  local win = vim.api.nvim_get_current_win()
  local tab_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_buf(win, ensure_buf())
  vim.api.nvim_buf_delete(tab_buf, { force = true })
  vim.api.nvim_win_set_option(win, "number", true)
  vim.api.nvim_win_set_option(win, "relativenumber", false)
  winid_log = win
end

function M.setup()
  capture_notify()
  vim.api.nvim_create_user_command("ErrorLogToggle", M.toggle, { desc = "Toggle error log tab" })
  vim.api.nvim_create_user_command("ErrorLogClear", M.clear, { desc = "Clear error log" })
end

return M
