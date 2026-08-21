local M = {}

local const = require("constants")
local system = require("system")
local util = require("util")

local function load_config()
  local json = require("cjson")
  local lfs = require("lfs")
  
  -- First, try to find an existing project file by walking up the directory tree
  local root = vim.fs.root(0, { const.project_file_name })
  
  -- If not found, use the current working directory as the root
  root = root or vim.fn.getcwd()
  
  local project_name = vim.fs.basename(root)
  local prj_file = vim.fs.joinpath(root, const.project_file_name)
  
  local default = {
    name = project_name,
    lua = { version = 5.1 },
    yaml = { schemas = {}, schema_store_url = nil },
    json = { schemas = {}, schema_store_url = nil },
  }
  
  -- If the file doesn't exist in the resolved root, create it
  if lfs.attributes(prj_file, "mode") == nil then
    local io_prj_file = io.open(prj_file, "w+")
    if io_prj_file then
      io_prj_file:write(json.encode(default))
      io_prj_file:close()
    else
      vim.notify("Failed to create " .. const.project_file_name .. " in " .. root, vim.log.levels.WARN)
    end
    default.root = root
    return default
  end
  
  local data = util.read_json(prj_file)
  local merged = util.merge_table(default, data)
  merged.root = root
  return merged
end

M.colorscheme = "catppuccin"

function M.load_vim_libs(lua_version)
  local vim_libs = system.lua_libs_path(vim.fn.stdpath("config"), lua_version)
  if vim.fn.isdirectory(vim_libs.share) == 1 then
    package.path = package.path .. ";" .. vim_libs.share .. "/?.lua"
  end
  if vim.fn.isdirectory(vim_libs.lib) == 1 then
    package.cpath = package.cpath .. ";" .. vim_libs.lib .. "/?.so"
  end
end

function M.load()
  local project = load_config()
  system.auto_commands(project)
  system.user_command(project)
  system.filetype()
  system.tmux_rename(project)
  require("keymapping")
  require("languages").setup(project)
end

return M
