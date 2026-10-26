local M = {}

M.packages = {
  standard = "tabs.standard",
  agentic = "tabs.agentic",
  system_standard = "tabs.system_standard",
  system_agentic = "tabs.system_agentic",
}

M.commands = {
  EditTab = "standard",
  AgenticTab = "agentic",
  SystemEditTab = "system_standard",
  SystemAgenticTab = "system_agentic",
}

M.default_mode = "standard"

-- [tabpage handle] = { mode, root, project }
local tabs = {}
-- Keymaps currently installed for the active tab: { mode, lhs, previous }
local applied = {}
local last_left
local opening = false

function M.package(mode)
  return require(M.packages[mode or M.default_mode])
end

function M.state(tab)
  return tabs[tab or vim.api.nvim_get_current_tabpage()]
end

function M.mode(tab)
  local st = M.state(tab)
  return st and st.mode or M.default_mode
end

function M.root(tab)
  local st = M.state(tab)
  return st and st.root or nil
end

function M.project(tab)
  local st = M.state(tab)
  return st and st.project or nil
end

function M.vault(tab)
  local st = M.state(tab)
  if not st then
    return nil
  end
  local pkg = M.package(st.mode)
  if pkg.vault then
    return pkg.vault(st)
  end
  return st.root
end

function M.is_mode(modes, tab)
  local current = M.mode(tab)
  for _, m in ipairs(modes) do
    if m == current then
      return true
    end
  end
  return false
end

-- Returns true when the current tab is in one of `modes`; otherwise reports and returns false.
function M.guard(modes, name)
  if M.is_mode(modes) then
    return true
  end
  vim.notify(
    string.format(":%s is not available in this tab (mode %s; needs %s)", name, M.mode(), table.concat(modes, "/")),
    vim.log.levels.WARN
  )
  return false
end

-- Run `register` with nvim_create_user_command patched so every Lua command body it creates
-- is guarded by `modes`. Names in `exempt` stay unguarded.
function M.guard_commands(modes, register, exempt)
  exempt = exempt or {}
  local create = vim.api.nvim_create_user_command
  vim.api.nvim_create_user_command = function (name, command, opts)
    if type(command) == "function" and not exempt[name] then
      local body = command
      command = function (args)
        if M.guard(modes, name) then
          return body(args)
        end
      end
    end
    return create(name, command, opts)
  end
  local ok, err = pcall(register)
  vim.api.nvim_create_user_command = create
  if not ok then
    error(err, 0)
  end
end

local function split_modes(mode)
  if type(mode) == "table" then
    return mode
  end
  mode = mode or "n"
  local out = {}
  for c in mode:gmatch(".") do
    out[#out + 1] = c
  end
  return out
end

-- Install which-key style specs: { lhs, rhs, mode = "n", desc = "", expr, nowait, remap, silent }.
function M.apply_keymaps(specs)
  for _, spec in ipairs(specs or {}) do
    local lhs, rhs = spec[1], spec[2]
    if lhs and rhs ~= nil then
      for _, m in ipairs(split_modes(spec.mode)) do
        local previous = vim.fn.maparg(lhs, m, false, true)
        if vim.tbl_isempty(previous) or previous.buffer == 1 then
          previous = nil
        end
        vim.keymap.set(m, lhs, rhs, {
          desc = spec.desc,
          expr = spec.expr,
          nowait = spec.nowait,
          remap = spec.remap,
          silent = spec.silent,
        })
        applied[#applied + 1] = { mode = m, lhs = lhs, previous = previous }
      end
    end
  end
end

-- Remove every map installed by apply_keymaps and restore what was there before.
function M.clear_keymaps()
  for i = #applied, 1, -1 do
    local entry = applied[i]
    pcall(vim.keymap.del, entry.mode, entry.lhs)
    if entry.previous then
      pcall(vim.fn.mapset, entry.mode, false, entry.previous)
    end
  end
  applied = {}
end

local function bind(tab, mode, root, project)
  local st = { mode = mode, root = root, project = project }
  tabs[tab] = st
  vim.t[tab].mode = mode
  vim.t[tab].root = root
  return st
end

function M.enter()
  local tab = vim.api.nvim_get_current_tabpage()
  local st = tabs[tab]
  if not st then
    local from = last_left or { mode = M.default_mode, root = vim.fn.getcwd() }
    st = bind(tab, from.mode, from.root, from.project)
  end
  M.clear_keymaps()
  local pkg = M.package(st.mode)
  M.apply_keymaps(pkg.keymaps and pkg.keymaps() or {})
  if pkg.on_enter then
    local ok, err = pcall(pkg.on_enter, st)
    if not ok then
      vim.notify("tab enter (" .. st.mode .. "): " .. tostring(err), vim.log.levels.WARN)
    end
  end
  require("tabs.shared.obsidian").sync()
end

function M.leave()
  local st = M.state()
  last_left = st
  M.clear_keymaps()
  if st then
    local pkg = M.package(st.mode)
    if pkg.on_leave then
      pcall(pkg.on_leave, st)
    end
  end
end

-- First tabpage handle bound to `mode` and `root`, or nil.
function M.find(mode, root)
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local st = tabs[tab]
    if st and st.mode == mode and (root == nil or st.root == root) then
      return tab
    end
  end
end

-- Open a new tab in `mode`, tcd to its root, and record mode/root on the tabpage.
-- `dir` is ignored by system modes. With opts.reuse, switch to an existing matching tab.
function M.open(mode, dir, opts)
  opts = opts or {}
  local pkg = M.package(mode)
  local start = pkg.root and pkg.root(dir) or (dir ~= nil and dir ~= "" and vim.fn.fnamemodify(dir, ":p")) or M.root() or vim.fn.getcwd()
  start = vim.fs.normalize(start)
  if vim.fn.isdirectory(start) ~= 1 then
    vim.notify("Not a directory: " .. start, vim.log.levels.ERROR)
    return
  end
  local project = require("main").load_project(start)
  if opts.reuse then
    local existing = M.find(mode, project.root)
    if existing then
      vim.api.nvim_set_current_tabpage(existing)
      return existing
    end
  end
  opening = true
  local ok, err = pcall(function ()
    vim.cmd("tabnew")
    vim.cmd.tcd(vim.fn.fnameescape(project.root))
    bind(vim.api.nvim_get_current_tabpage(), mode, project.root, project).opened = true
  end)
  opening = false
  if not ok then
    vim.notify("Failed to open " .. mode .. " tab: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  M.enter()
  return vim.api.nvim_get_current_tabpage()
end

local function prune()
  local alive = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    alive[tab] = true
  end
  for tab in pairs(tabs) do
    if not alive[tab] then
      tabs[tab] = nil
    end
  end
end

-- Bind the startup tab to Standard for `project` (no tcd, so the startup cwd is unchanged),
-- install the tab autocmds and the *Tab commands, and apply the Standard maps.
function M.setup(project)
  local group = vim.api.nvim_create_augroup("tabs_runtime", { clear = true })
  vim.api.nvim_create_autocmd("TabEnter", {
    group = group,
    callback = function ()
      if not opening then
        M.enter()
      end
    end,
  })
  vim.api.nvim_create_autocmd("TabLeave", { group = group, callback = M.leave })
  vim.api.nvim_create_autocmd("TabClosed", { group = group, callback = prune })

  for name, mode in pairs(M.commands) do
    local system = mode:match("^system_") ~= nil
    vim.api.nvim_create_user_command(name, function (args)
      M.open(mode, args.args)
    end, {
      nargs = system and 0 or "?",
      complete = (not system) and "dir" or nil,
      desc = system and ("Open a " .. mode .. " tab at $COMMON_SCRIPT/system_project")
        or ("Open a " .. mode .. " tab (root: [dir] or the current tab root)"),
    })
  end

  local tab = vim.api.nvim_get_current_tabpage()
  if not tabs[tab] then
    bind(tab, M.default_mode, project.root, project)
  end
  M.enter()
end

return M
