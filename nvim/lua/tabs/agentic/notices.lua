-- Read-only panel for the Notices section of the agentic tree.
local Popup = require("nui.popup")
local state = require("tabs.agentic.state")

local M = {}

local open_popup

local LEVEL = {
  [vim.log.levels.ERROR] = "ERROR",
  [vim.log.levels.WARN] = "WARN",
  [vim.log.levels.INFO] = "INFO",
  [vim.log.levels.DEBUG] = "DEBUG",
  [vim.log.levels.TRACE] = "TRACE",
}

-- Notices this tab's tree shows.
function M.listed()
  local u, st = state.get()
  local visible
  if u and st then
    visible = {}
    for _, meta in ipairs(require("tabs.agentic.tree").agents(u, st)) do
      visible[meta.agent_id] = true
    end
  end
  local items = {}
  for _, n in ipairs(state.notices()) do
    if not visible or not n.agent_id or visible[n.agent_id] then
      items[#items + 1] = n
    end
  end
  return items
end

local function lines_for(items, focus)
  if #items == 0 then
    return { "No notices." }, 1
  end
  local lines, cursor = {}, 1
  for i, n in ipairs(items) do
    local head = string.format("%s  %s", n.time or "", LEVEL[n.level] or "INFO")
    if n.agent_id then
      head = head .. "  " .. n.agent_id
    end
    lines[#lines + 1] = head
    if focus and n == focus then
      cursor = #lines
    end
    local body = vim.split(tostring(n.text or ""), "\n", { plain = true })
    if #body == 0 then
      body = { "" }
    end
    for _, line in ipairs(body) do
      lines[#lines + 1] = "  " .. line
    end
    if i < #items then
      lines[#lines + 1] = ""
    end
  end
  return lines, cursor
end

-- Open the notices for this tab. `focus` is the notice under the tree cursor, when there is one.
function M.open(focus)
  if open_popup then
    pcall(function ()
      open_popup:unmount()
    end)
    open_popup = nil
  end
  local items = M.listed()
  local lines, cursor = lines_for(items, focus)
  local width = math.min(88, math.max(48, math.floor(vim.o.columns * 0.55)))
  local height = math.min(math.max(#lines + 1, 4), math.max(8, math.floor(vim.o.lines * 0.55)))
  local popup = Popup({
    enter = true,
    focusable = true,
    relative = "editor",
    position = "50%",
    size = { width = width, height = height },
    zindex = 60,
    border = { style = "rounded", text = { top = " Notices ", top_align = "center" } },
    buf_options = { modifiable = false, filetype = "log" },
    win_options = { cursorline = true, wrap = true, linebreak = true },
  })
  popup:mount()
  open_popup = popup
  vim.bo[popup.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
  vim.bo[popup.bufnr].modifiable = false
  pcall(vim.api.nvim_win_set_cursor, popup.winid, { cursor, 0 })
  local function close()
    if open_popup == popup then
      open_popup = nil
    end
    pcall(function ()
      popup:unmount()
    end)
  end
  popup:map("n", "q", close, { noremap = true, nowait = true })
  popup:map("n", "<Esc>", close, { noremap = true, nowait = true })
  local function ignore() end
  for _, lhs in ipairs({ "i", "I", "a", "A", "o", "O", "c", "C" }) do
    popup:map("n", lhs, ignore, { noremap = true, nowait = true })
  end
end

return M
