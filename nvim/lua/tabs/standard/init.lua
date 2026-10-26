local M = {}

M.mode = "standard"
M.modes = { "standard", "system_standard" }

-- Commands registered by system.lua that stay usable in every tab.
M.global_commands = {
  Quit = true,
  ReloadConfig = true,
  ErrorLogToggle = true,
  ErrorLogClear = true,
}

-- One-time global setup for the Standard package: editing commands (guarded to Standard tabs),
-- autocmds, filetypes, and the LSP servers in languages.lua.
function M.setup(project)
  local runtime = require("tabs.runtime")
  local system = require("system")
  runtime.guard_commands(M.modes, function ()
    system.auto_commands(project)
    system.user_command(project)
  end, M.global_commands)
  system.filetype()
  require("languages").setup(project)
end

function M.keymaps()
  return require("tabs.standard.keymaps")
end

local function tree_core()
  if not package.loaded["nvim-tree"] then
    return nil
  end
  local ok, core = pcall(require, "nvim-tree.core")
  return ok and core or nil
end

function M.close_tree()
  if not package.loaded["nvim-tree"] then
    return
  end
  local api = require("nvim-tree.api")
  if api.tree.close_in_this_tab then
    pcall(api.tree.close_in_this_tab)
  else
    pcall(api.tree.close)
  end
end

local function close_agentic_tree()
  local ok, agentic = pcall(require, "tabs.agentic")
  if ok and type(agentic.close_tree) == "function" then
    pcall(agentic.close_tree)
  end
end

-- nvim-tree has one explorer for all tabs; remember each tab's tree root and restore it on enter.
local function sync_tree_root(st)
  local core = tree_core()
  if not core or not core.get_explorer() then
    return
  end
  local wanted = st.tree_root or (st.opened and st.root) or nil
  if wanted and core.get_cwd() ~= wanted then
    pcall(require("nvim-tree.api").tree.change_root, wanted)
  end
end

-- A command-opened tab starts as an unnamed buffer. Show the file tree for its root.
local function open_file_tree(root)
  local ok, api = pcall(require, "nvim-tree.api")
  if ok then
    pcall(api.tree.open, { path = root })
    pcall(api.tree.focus)
  end
end

-- File windows keep the editing gutter: signs, line numbers, fold against the text.
local function restore_gutter()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= "NvimTree" then
      local wo = vim.wo[win]
      wo.number = true
      wo.relativenumber = true
      wo.signcolumn = "yes"
      wo.foldcolumn = "1"
      wo.foldenable = true
    end
  end
end

function M.on_enter(st)
  close_agentic_tree()
  restore_gutter()
  if st.opened then
    st.opened = nil
    open_file_tree(st.root)
  else
    sync_tree_root(st)
  end
  if st.project then
    require("languages").refresh(st.project)
  end
end

function M.on_leave(st)
  local core = tree_core()
  if core and core.get_explorer() then
    st.tree_root = core.get_cwd()
  end
end

return M
