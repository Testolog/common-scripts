-- Agentic tab windows: tree on the left (~30%), read context top-right, write context bottom-right (20%).
local state = require("tabs.agentic.state")

local M = {}

M.TREE_WIDTH = 0.30
M.WRITE_HEIGHT = 0.20

local placeholder

local function placeholder_buf()
  if placeholder and vim.api.nvim_buf_is_valid(placeholder) then
    return placeholder
  end
  placeholder = vim.api.nvim_create_buf(false, true)
  vim.bo[placeholder].bufhidden = "hide"
  pcall(vim.api.nvim_buf_set_name, placeholder, "agentic://none")
  vim.api.nvim_buf_set_lines(placeholder, 0, -1, false, {
    "No agent selected.",
    "",
    "In the tree: <CR> opens an agent, a creates one (:AgentCreate), ? lists the keys.",
  })
  vim.bo[placeholder].modifiable = false
  return placeholder
end

local function is_scratch_noname(buf)
  return vim.api.nvim_buf_get_name(buf) == ""
    and not vim.bo[buf].modified
    and vim.api.nvim_buf_line_count(buf) == 1
    and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

local function right_height(u)
  local h = 0
  if state.valid_win(u.read_win) then
    h = h + vim.api.nvim_win_get_height(u.read_win) + 1
  end
  if state.valid_win(u.write_win) then
    h = h + vim.api.nvim_win_get_height(u.write_win) + 1
  end
  return math.max(h, 6)
end

local function write_height(total)
  return math.max(3, math.floor(total * M.WRITE_HEIGHT))
end

local function current_read_buf(u)
  if u.agent_id then
    local s = require("tabs.agentic.read").get(u.agent_id)
    if s then
      return s.buf, s
    end
  end
  return placeholder_buf()
end

local function current_write_buf(u)
  return require("tabs.agentic.write").buffer(u.agent_id or require("tabs.agentic.write").DRAFT)
end

local function configure_write(win)
  vim.wo[win].winfixheight = true
  vim.wo[win].winbar = "%#Title# write %* <C-s> submit · --- queues another request · <leader>ae expand/collapse"
end

-- Create whatever windows are missing in the current agentic tab.
function M.ensure()
  local u = state.get()
  if not u then
    return
  end
  local tab = state.tab()
  local tree = require("tabs.agentic.tree")
  if not state.valid_win(u.read_win) and not state.valid_win(u.write_win) then
    local main
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if win ~= u.tree_win and vim.api.nvim_win_get_config(win).relative == "" then
        main = win
        break
      end
    end
    local rbuf, s = current_read_buf(u)
    if main then
      local old = vim.api.nvim_win_get_buf(main)
      vim.api.nvim_win_set_buf(main, rbuf)
      if old ~= rbuf and is_scratch_noname(old) and #vim.fn.win_findbuf(old) == 0 then
        pcall(vim.api.nvim_buf_delete, old, {})
      end
    else
      main = vim.api.nvim_open_win(rbuf, false, { split = "right", win = u.tree_win })
    end
    u.read_win = main
    if s then
      require("tabs.agentic.read").configure_window(main, s)
    end
  end
  if not state.valid_win(u.tree_win) then
    u.tree_win = vim.api.nvim_open_win(tree.buffer(), false, {
      split = "left",
      win = -1,
      width = math.max(24, math.floor(vim.o.columns * M.TREE_WIDTH)),
    })
    tree.configure_window(u.tree_win)
  end
  if not u.write_expanded then
    if state.valid_win(u.read_win) and not state.valid_win(u.write_win) then
      local total = vim.api.nvim_win_get_height(u.read_win)
      u.write_win = vim.api.nvim_open_win(current_write_buf(u), false, {
        split = "below",
        win = u.read_win,
        height = write_height(total),
      })
      configure_write(u.write_win)
    elseif state.valid_win(u.write_win) and not state.valid_win(u.read_win) then
      local rbuf, s = current_read_buf(u)
      local total = vim.api.nvim_win_get_height(u.write_win)
      u.read_win = vim.api.nvim_open_win(rbuf, false, { split = "above", win = u.write_win })
      if s then
        require("tabs.agentic.read").configure_window(u.read_win, s)
      end
      vim.api.nvim_win_set_height(u.write_win, write_height(total))
    end
  elseif not state.valid_win(u.write_win) then
    local anchor = state.valid_win(u.tree_win) and { split = "right", win = u.tree_win } or { split = "below", win = 0 }
    u.write_win = vim.api.nvim_open_win(current_write_buf(u), false, anchor)
    configure_write(u.write_win)
  end
  return u
end

-- Fill the read and write panes with `meta`'s agent (or the draft when meta is nil).
function M.show(meta, opts)
  opts = opts or {}
  local u = state.get()
  if not u then
    return
  end
  u.agent_id = meta and meta.agent_id or nil
  M.ensure()
  local read = require("tabs.agentic.read")
  local write = require("tabs.agentic.write")
  if state.valid_win(u.read_win) then
    if meta then
      local s = read.session(meta)
      vim.api.nvim_win_set_buf(u.read_win, s.buf)
      read.configure_window(u.read_win, s)
      pcall(vim.api.nvim_win_set_cursor, u.read_win, { vim.api.nvim_buf_line_count(s.buf), 0 })
    else
      vim.api.nvim_win_set_buf(u.read_win, placeholder_buf())
      vim.wo[u.read_win].winbar = ""
    end
  elseif meta then
    read.session(meta)
  end
  if state.valid_win(u.write_win) then
    vim.api.nvim_win_set_buf(u.write_win, write.buffer(meta and meta.agent_id or write.DRAFT))
    configure_write(u.write_win)
  end
  require("tabs.agentic.tree").refresh()
  if opts.focus == "write" and state.valid_win(u.write_win) then
    vim.api.nvim_set_current_win(u.write_win)
  elseif opts.focus == "read" and state.valid_win(u.read_win) then
    vim.api.nvim_set_current_win(u.read_win)
  end
end

-- Expand the write pane to the full right side, or collapse it back to 20%.
function M.toggle_write()
  local u = M.ensure()
  if not u then
    return
  end
  if not u.write_expanded then
    u.write_expanded = true
    if state.valid_win(u.read_win) then
      local wins = vim.api.nvim_tabpage_list_wins(state.tab())
      if #wins > 2 then
        vim.api.nvim_win_close(u.read_win, false)
      end
    end
    u.read_win = nil
    if state.valid_win(u.write_win) then
      vim.api.nvim_set_current_win(u.write_win)
    end
  else
    u.write_expanded = false
    local total = state.valid_win(u.write_win) and vim.api.nvim_win_get_height(u.write_win) or right_height(u)
    M.ensure()
    if state.valid_win(u.write_win) then
      vim.api.nvim_win_set_height(u.write_win, write_height(total))
      vim.api.nvim_set_current_win(u.write_win)
    end
  end
end

function M.focus_write()
  local u = M.ensure()
  if u and state.valid_win(u.write_win) then
    vim.api.nvim_set_current_win(u.write_win)
  end
end

-- Second read buffer, only on request: a vertical split of the read pane showing `meta`.
function M.open_second_read(meta)
  local u = M.ensure()
  if not u or not meta then
    return
  end
  local read = require("tabs.agentic.read")
  local s = read.session(meta)
  local anchor = state.valid_win(u.read_win) and u.read_win or u.write_win
  local win = vim.api.nvim_open_win(s.buf, true, { split = "right", win = anchor })
  read.configure_window(win, s)
end

-- Close the agentic tree in the current tab (called when entering a Standard tab).
function M.close_tree()
  local u = state.get()
  if u and state.valid_win(u.tree_win) then
    local wins = vim.api.nvim_tabpage_list_wins(state.tab())
    if #wins > 1 then
      vim.api.nvim_win_close(u.tree_win, true)
    end
  end
  if u then
    u.tree_win = nil
  end
end

function M.toggle_tree()
  local u = state.get()
  if u and state.valid_win(u.tree_win) then
    M.close_tree()
  else
    M.ensure()
    require("tabs.agentic.tree").refresh()
  end
end

return M
