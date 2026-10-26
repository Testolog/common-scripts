-- Business logic for $COMMON_SCRIPT/system_project: template, kind detection, catalog, init, update.
-- This module loads no plugins.
local json = require("util.json")
local kinds = require("system_project.kinds")
local catalog = require("system_project.catalog")

local M = {}

M.dir_name = "system_project"
M.project_file_name = require("constants").project_file_name
M.catalog_file_name = "catalog.json"

-- Keys SystemProjectUpdate rewrites from the template.
M.template_keys = { "system_prompt", "system_skills", "system_tools", "models", "mcp_servers" }

-- Checkout this config ships from (<checkout>/nvim/lua/system_project/init.lua).
function M.shipped_root()
  local source = debug.getinfo(1, "S").source:gsub("^@", "")
  local real = vim.uv.fs_realpath(source) or source
  return vim.fn.fnamemodify(real, ":h:h:h:h")
end

function M.common_script()
  local env = vim.env.COMMON_SCRIPT
  if env and env ~= "" then
    return vim.fs.normalize(env)
  end
  return M.shipped_root()
end

function M.root()
  return vim.fs.joinpath(M.common_script(), M.dir_name)
end

function M.template_path()
  return vim.fs.joinpath(M.root(), M.project_file_name)
end

function M.catalog_path()
  return vim.fs.joinpath(M.root(), M.catalog_file_name)
end

-- Template table and the path it was read from. Falls back to the copy shipped with this config.
function M.read_template()
  local candidates = {
    M.template_path(),
    vim.fs.joinpath(M.shipped_root(), M.dir_name, M.project_file_name),
  }
  for _, path in ipairs(candidates) do
    if vim.uv.fs_stat(path) then
      local ok, data = pcall(json.read_file, path)
      if ok and type(data) == "table" then
        return data, path
      end
      vim.notify("system_project: cannot read template " .. path .. ": " .. tostring(data), vim.log.levels.WARN)
    end
  end
  return nil
end

local function mcp_flags(servers)
  local out = {}
  for _, server in ipairs(servers or {}) do
    if type(server) == "table" and server.name then
      out[#out + 1] = { name = server.name, isActive = server.isActive == true }
    end
  end
  return out
end

-- Template-owned values for a project whose kinds are `project_kinds`.
function M.template_values(template, project_kinds)
  return {
    system_prompt = kinds.select_prompts(template.system_prompt, project_kinds),
    system_skills = vim.deepcopy(template.system_skills or {}),
    system_tools = vim.deepcopy(template.system_tools or {}),
    models = vim.deepcopy(template.models or {}),
    mcp_servers = mcp_flags(template.mcp_servers),
  }
end

-- Standalone project table for `root`: `base` keys (name, lua, yaml, json) plus the template copy.
function M.new_project(root, base, template)
  local data = vim.deepcopy(base or {})
  data.root = nil
  local project_kinds = kinds.detect(root)
  data.project_type = project_kinds
  if template then
    for key, value in pairs(M.template_values(template, project_kinds)) do
      data[key] = value
    end
  end
  data.project_prompt = {}
  data.project_skills = {}
  data.project_tools = {}
  return data
end

-- Write a new .nvim_project.json for `root` and add it to the catalog.
-- Returns the written table (or `base` when the write failed).
function M.create_project_file(root, base)
  local template, template_path = M.read_template()
  if not template then
    vim.notify("system_project: template missing; run :SystemProjectInit", vim.log.levels.WARN)
  elseif template_path ~= M.template_path() then
    vim.notify("system_project: " .. M.root() .. " is missing; prompt paths point there. Run :SystemProjectInit",
      vim.log.levels.WARN)
  end
  local data = M.new_project(root, base, template)
  local path = vim.fs.joinpath(root, M.project_file_name)
  local ok, err = json.write_file(path, data)
  if not ok then
    vim.notify("Failed to create " .. M.project_file_name .. " in " .. root .. ": " .. tostring(err), vim.log.levels.WARN)
    return base
  end
  M.register(root, data.name)
  return data
end

-- Add `root` to the catalog when the system project exists. Returns true when added.
function M.register(root, name)
  if vim.fn.isdirectory(M.root()) ~= 1 or vim.fs.normalize(root) == vim.fs.normalize(M.root()) then
    return false
  end
  return catalog.register(M.catalog_path(), root, name)
end

local function copy_missing(source, target, created)
  for name, type in vim.fs.dir(source, { depth = 10 }) do
    local from = vim.fs.joinpath(source, name)
    local to = vim.fs.joinpath(target, name)
    if type == "directory" then
      if vim.fn.isdirectory(to) ~= 1 then
        vim.fn.mkdir(to, "p")
        created[#created + 1] = to
      end
    elseif type == "file" and name ~= M.catalog_file_name and not vim.uv.fs_stat(to) then
      vim.fn.mkdir(vim.fs.dirname(to), "p")
      local ok = vim.uv.fs_copyfile(from, to)
      if ok then
        created[#created + 1] = to
      end
    end
  end
end

-- Create $COMMON_SCRIPT/system_project (prompts, skills, system_function, template, catalog) where missing.
-- Existing files are never overwritten. Returns the root and the list of created paths.
function M.init()
  local target = M.root()
  local source = vim.fs.joinpath(M.shipped_root(), M.dir_name)
  local created = {}
  if vim.fn.isdirectory(target) ~= 1 then
    vim.fn.mkdir(target, "p")
    created[#created + 1] = target
  end
  if vim.fs.normalize(source) ~= vim.fs.normalize(target) and vim.fn.isdirectory(source) == 1 then
    copy_missing(source, target, created)
  end
  for _, sub in ipairs({ "prompts", "skills/base", "system_function" }) do
    local dir = vim.fs.joinpath(target, sub)
    if vim.fn.isdirectory(dir) ~= 1 then
      vim.fn.mkdir(dir, "p")
      created[#created + 1] = dir
    end
  end
  if not vim.uv.fs_stat(M.catalog_path()) then
    catalog.write(M.catalog_path(), { projects = {} })
    created[#created + 1] = M.catalog_path()
  end
  if not vim.uv.fs_stat(M.template_path()) then
    vim.notify("system_project: no template at " .. M.template_path(), vim.log.levels.ERROR)
  end
  return target, created
end

-- Root of the system project, initialising it first when the template is missing.
function M.ensure()
  if not vim.uv.fs_stat(M.template_path()) then
    M.init()
  end
  return M.root()
end

-- Rewrite the template-owned keys in every cataloged project. project_* and other keys are kept.
-- Returns the list of updated roots and the list of { root, error } failures.
function M.update()
  local template = M.read_template()
  if not template then
    return {}, { { root = M.root(), error = "template missing" } }
  end
  local updated, failed = {}, {}
  for _, entry in ipairs(catalog.read(M.catalog_path()).projects) do
    local path = vim.fs.joinpath(entry.root, M.project_file_name)
    local ok, data = pcall(json.read_file, path)
    if not ok or type(data) ~= "table" then
      failed[#failed + 1] = { root = entry.root, error = ok and "not a JSON object" or tostring(data) }
    else
      local project_kinds = kinds.detect(entry.root, data.project_type)
      for key, value in pairs(M.template_values(template, project_kinds)) do
        data[key] = value
      end
      local wrote, err = json.write_file(path, data)
      if wrote then
        updated[#updated + 1] = entry.root
      else
        failed[#failed + 1] = { root = entry.root, error = tostring(err) }
      end
    end
  end
  return updated, failed
end

function M.setup()
  vim.api.nvim_create_user_command("SystemProjectInit", function ()
    local root, created = M.init()
    if #created == 0 then
      vim.notify("System project already initialised at " .. root, vim.log.levels.INFO)
    else
      vim.notify("System project at " .. root .. ", created:\n" .. table.concat(created, "\n"), vim.log.levels.INFO)
    end
  end, { desc = "Create $COMMON_SCRIPT/system_project where missing" })

  vim.api.nvim_create_user_command("SystemProjectUpdate", function ()
    local updated, failed = M.update()
    local lines = { string.format("SystemProjectUpdate: %d updated, %d failed", #updated, #failed) }
    for _, root in ipairs(updated) do
      lines[#lines + 1] = "  updated " .. root
    end
    for _, f in ipairs(failed) do
      lines[#lines + 1] = "  failed  " .. f.root .. ": " .. f.error
    end
    vim.notify(table.concat(lines, "\n"), #failed > 0 and vim.log.levels.WARN or vim.log.levels.INFO)
  end, { desc = "Write system prompts, skills, tools, models, and mcp_servers into every cataloged project" })

  vim.api.nvim_create_user_command("CursorUpdateModelList", function ()
    require("tabs.agentic.client").update_cursor_models(function (value, err)
      if err then
        vim.notify("CursorUpdateModelList: " .. err, vim.log.levels.ERROR)
        return
      end
      local models = type(value) == "table" and value.models or {}
      local path = type(value) == "table" and value.path or M.root()
      vim.notify(
        string.format("Cursor models updated (%d) at %s", #models, path),
        vim.log.levels.INFO
      )
    end)
  end, { desc = "Ask Cursor for its model list and store it in the system project" })

  vim.api.nvim_create_user_command("SystemProjectRegister", function (args)
    local dir = args.args ~= "" and vim.fn.fnamemodify(args.args, ":p") or nil
    local root = dir and (vim.fs.root(dir, M.project_file_name) or dir)
      or require("tabs.runtime").root() or vim.fn.getcwd()
    root = vim.fs.normalize(root)
    if not vim.uv.fs_stat(vim.fs.joinpath(root, M.project_file_name)) then
      return vim.notify("No " .. M.project_file_name .. " in " .. root, vim.log.levels.WARN)
    end
    if vim.fn.isdirectory(M.root()) ~= 1 then
      return vim.notify("System project missing; run :SystemProjectInit", vim.log.levels.WARN)
    end
    local added = M.register(root)
    vim.notify((added and "Registered " or "Already registered ") .. root, vim.log.levels.INFO)
  end, { nargs = "?", complete = "dir", desc = "Add a project (default: current tab root) to the system catalog" })
end

return M
