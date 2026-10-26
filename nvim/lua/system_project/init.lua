-- Business logic for $COMMON_SCRIPT/system_project: template, kind detection, catalog, init, update.
-- This module loads no plugins.
local json = require("util.json")
local kinds = require("system_project.kinds")
local catalog = require("system_project.catalog")

local M = {}

M.dir_name = "system_project"
M.project_file_name = require("constants").project_file_name
M.template_file_name = "nvim_project.template.json"
M.catalog_file_name = "catalog.json"

-- Keys merged from the template on :NvimProjectInit (existing file) and :SystemProjectUpdate.
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
  return vim.fs.joinpath(M.root(), M.template_file_name)
end

function M.catalog_path()
  return vim.fs.joinpath(M.root(), M.catalog_file_name)
end

-- nvim_project.template.json and the path it was read from.
-- The only template is that file. Falls back to the copy shipped with this config.
function M.read_template()
  local candidates = {
    M.template_path(),
    vim.fs.joinpath(M.shipped_root(), M.dir_name, M.template_file_name),
  }
  local seen = {}
  for _, path in ipairs(candidates) do
    if not seen[path] then
      seen[path] = true
      if vim.uv.fs_stat(path) then
        local ok, data = pcall(json.read_file, path)
        if ok and type(data) == "table" then
          return data, path
        end
        vim.notify("system_project: cannot read template " .. path .. ": " .. tostring(data), vim.log.levels.WARN)
      end
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

local function entry_name(entry)
  if type(entry) == "table" then
    return entry.name
  end
  if type(entry) == "string" or type(entry) == "number" then
    return entry
  end
  return nil
end

-- Named-array union. Local order stays. Shared names are refreshed from the template.
-- Template-only names are appended. A non-list local value is left as stored.
local function union_by_name(local_list, template_list)
  if type(local_list) == "table" and not vim.islist(local_list) then
    return local_list
  end
  local out, seen, from_template = {}, {}, {}
  if type(template_list) == "table" and vim.islist(template_list) then
    for _, entry in ipairs(template_list) do
      local name = entry_name(entry)
      if name ~= nil and from_template[name] == nil then
        from_template[name] = entry
      end
    end
  end
  if type(local_list) == "table" and vim.islist(local_list) then
    for _, entry in ipairs(local_list) do
      local name = entry_name(entry)
      if name ~= nil and from_template[name] ~= nil then
        out[#out + 1] = vim.deepcopy(from_template[name])
      else
        out[#out + 1] = vim.deepcopy(entry)
      end
      if name ~= nil then
        seen[name] = true
      end
    end
  end
  if type(template_list) == "table" and vim.islist(template_list) then
    for _, entry in ipairs(template_list) do
      local name = entry_name(entry)
      if name ~= nil and not seen[name] then
        seen[name] = true
        out[#out + 1] = vim.deepcopy(entry)
      end
    end
  end
  return out
end

-- Array of named entries, or an object, as a map. The first name wins.
local function model_map(value)
  local map = {}
  if type(value) ~= "table" then
    return map
  end
  if vim.islist(value) then
    for _, entry in ipairs(value) do
      local name = entry_name(entry)
      if name ~= nil and map[name] == nil then
        map[name] = entry
      end
    end
    return map
  end
  for key, entry in pairs(value) do
    if map[key] == nil then
      map[key] = entry
    end
  end
  return map
end

-- Named array: union by name. Object: template refreshes shared keys, local-only keys stay.
local function merge_models(local_models, template_models)
  if type(local_models) == "table" and not vim.islist(local_models) then
    local out = {}
    for key, entry in pairs(local_models) do
      out[key] = vim.deepcopy(entry)
    end
    for key, entry in pairs(model_map(template_models)) do
      out[key] = vim.deepcopy(entry)
    end
    return out
  end
  return union_by_name(local_models, template_models)
end

-- Local servers keep their isActive. Template-only servers are added with the template isActive.
-- Each stored server is name and isActive only.
local function merge_mcp(local_servers, template_servers)
  local out, seen = {}, {}
  local function add(server, active)
    if type(server) ~= "table" or server.name == nil or seen[server.name] then
      return
    end
    seen[server.name] = true
    out[#out + 1] = { name = server.name, isActive = active == true }
  end
  if type(local_servers) == "table" and vim.islist(local_servers) then
    for _, server in ipairs(local_servers) do
      add(server, type(server) == "table" and server.isActive or false)
    end
  end
  if type(template_servers) == "table" and vim.islist(template_servers) then
    for _, server in ipairs(template_servers) do
      add(server, type(server) == "table" and server.isActive or false)
    end
  end
  return out
end

-- Template-owned values for a project whose kinds are `project_kinds`.
-- system_prompt is filtered by kinds.select_prompts; the other keys are the full template copy.
function M.template_values(template, project_kinds)
  return {
    system_prompt = kinds.select_prompts(template.system_prompt, project_kinds),
    system_skills = vim.deepcopy(template.system_skills or {}),
    system_tools = vim.deepcopy(template.system_tools or {}),
    models = vim.deepcopy(template.models or {}),
    mcp_servers = mcp_flags(template.mcp_servers),
  }
end

-- Merge the five template keys into `data` in place. Other keys are untouched.
function M.apply_template(data, template, project_kinds)
  local values = M.template_values(template, project_kinds)
  data.system_prompt = union_by_name(data.system_prompt, values.system_prompt)
  data.system_skills = union_by_name(data.system_skills, values.system_skills)
  data.system_tools = union_by_name(data.system_tools, values.system_tools)
  data.models = merge_models(data.models, values.models)
  data.mcp_servers = merge_mcp(data.mcp_servers, values.mcp_servers)
  return data
end

-- Standalone project table for `root`: `base` keys (name, lua, yaml, json) plus the template merge.
function M.new_project(root, base, template)
  local data = vim.deepcopy(base or {})
  data.root = nil
  local project_kinds = kinds.detect(root)
  data.project_type = project_kinds
  data.project_prompt = {}
  data.project_skills = {}
  data.project_tools = {}
  if template then
    M.apply_template(data, template, project_kinds)
  end
  return data
end

-- Basename of `git rev-parse --show-toplevel` when that succeeds in `dir`, else the directory basename.
function M.default_name(dir)
  local ok, proc = pcall(vim.system, { "git", "rev-parse", "--show-toplevel" }, { cwd = dir, text = true })
  if ok and proc then
    local waited, obj = pcall(function ()
      return proc:wait(5000)
    end)
    if waited and obj and obj.code == 0 then
      local top = vim.trim(obj.stdout or "")
      if top ~= "" then
        return vim.fs.basename(vim.fs.normalize(top))
      end
    end
  end
  return vim.fs.basename(dir)
end

local function keep_stored_name(data, dir)
  if type(data.name) == "string" and vim.trim(data.name) ~= "" then
    return
  end
  data.name = M.default_name(dir)
end

local function base_project(name)
  return {
    name = name,
    lua = { version = 5.1 },
    yaml = { schemas = {}, schema_store_url = nil },
    json = { schemas = {}, schema_store_url = nil },
  }
end

local function warn_template(template, template_from)
  if not template then
    vim.notify("system_project: template missing; run :SystemProjectInit", vim.log.levels.WARN)
  elseif template_from ~= M.template_path() then
    vim.notify("system_project: " .. M.root() .. " is missing; prompt paths point there. Run :SystemProjectInit",
      vim.log.levels.WARN)
  end
end

-- Write .nvim_project.json in `dir` and catalog.register it.
-- A new file takes default_name. An existing non-empty name is kept, and the template is merged.
-- Returns the written table, nil, and whether the catalog gained the project. On failure: nil, error.
function M.init_project(dir)
  dir = vim.fs.normalize(dir)
  if vim.fn.isdirectory(dir) ~= 1 then
    return nil, "not a directory: " .. dir
  end
  local template, template_from = M.read_template()
  warn_template(template, template_from)
  local path = vim.fs.joinpath(dir, M.project_file_name)
  local data
  if vim.uv.fs_stat(path) then
    local ok, decoded = pcall(json.read_file, path)
    if not ok or type(decoded) ~= "table" or vim.islist(decoded) then
      return nil, (ok and "not a JSON object" or tostring(decoded))
    end
    data = decoded
    keep_stored_name(data, dir)
    if template then
      M.apply_template(data, template, kinds.detect(dir, data.project_type))
    end
  else
    data = M.new_project(dir, base_project(M.default_name(dir)), template)
  end
  local wrote, err = json.write_file(path, data)
  if not wrote then
    return nil, tostring(err)
  end
  local added = M.register(dir, data.name)
  return data, nil, added
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

-- Merge the template into every cataloged project. Local keys are kept.
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
    if not ok or type(data) ~= "table" or vim.islist(data) then
      failed[#failed + 1] = { root = entry.root, error = ok and "not a JSON object" or tostring(data) }
    else
      M.apply_template(data, template, kinds.detect(entry.root, data.project_type))
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
  vim.api.nvim_create_user_command("NvimProjectInit", function (args)
    local dir = args.args ~= "" and vim.fn.fnamemodify(args.args, ":p")
      or require("tabs.runtime").root()
      or vim.fn.getcwd()
    local data, err, added = M.init_project(dir)
    if not data then
      return vim.notify("NvimProjectInit: " .. tostring(err), vim.log.levels.ERROR)
    end
    local where = vim.fs.joinpath(vim.fs.normalize(dir), M.project_file_name)
    local catalog_note = added and "registered in the catalog" or "catalog unchanged"
    vim.notify("NvimProjectInit: wrote " .. where .. " (" .. catalog_note .. ")", vim.log.levels.INFO)
  end, {
    nargs = "?",
    complete = "dir",
    desc = "Write .nvim_project.json in [dir] (default: current tab root) and register it",
  })

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
  end, { desc = "Merge system prompts, skills, tools, models, and mcp_servers from the template into every cataloged project" })

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
