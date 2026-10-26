-- Per-tab agentic UI state, stored on the tabs.runtime state of the tabpage (st.agentic).
local M = {}

local notices = {}
M.MAX_NOTICES = 30

function M.tab()
  return vim.api.nvim_get_current_tabpage()
end

-- UI state and runtime state of `tab` (default current), or nil when the tab is not bound.
function M.get(tab)
  local st = require("tabs.runtime").state(tab or M.tab())
  if not st then
    return nil
  end
  st.agentic = st.agentic or {
    collapsed = {},
    expanded = {},
    write_expanded = false,
    mcp = nil,
    mcp_errors = {},
  }
  return st.agentic, st
end

function M.is_agentic(st)
  return st ~= nil and (st.mode == "agentic" or st.mode == "system_agentic")
end

function M.is_system(st)
  return st ~= nil and st.mode == "system_agentic"
end

function M.valid_win(win, tab)
  return win ~= nil
    and vim.api.nvim_win_is_valid(win)
    and vim.api.nvim_win_get_tabpage(win) == (tab or M.tab())
end

-- Every agentic tab handle with its UI state.
function M.agentic_tabs()
  local out = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local u, st = M.get(tab)
    if u and M.is_agentic(st) then
      out[#out + 1] = { tab = tab, ui = u, st = st }
    end
  end
  return out
end

-- Tree notices: { time, agent_id?, text, level }. Shown by every tree that lists the agent (or all when agent_id is nil).
function M.notice(text, level, agent_id)
  table.insert(notices, 1, { time = os.date("%H:%M:%S"), agent_id = agent_id, text = text, level = level or vim.log.levels.INFO })
  while #notices > M.MAX_NOTICES do
    table.remove(notices)
  end
  pcall(function ()
    require("tabs.agentic.tree").refresh_all()
  end)
end

function M.notices()
  return notices
end

return M
