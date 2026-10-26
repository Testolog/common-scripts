local M = {}

local const = require("constants")
local system = require("system")
local util = require("util")

-- `start` is a directory to resolve from; nil resolves from the current buffer / cwd as at startup.
local function load_config(start)
  local lfs = require("lfs")

  -- First, try to find an existing project file by walking up the directory tree
  local root = vim.fs.root(start or 0, { const.project_file_name })

  -- If not found, use the starting directory (or the current working directory) as the root
  root = root or start or vim.fn.getcwd()

  local project_name = vim.fs.basename(root)
  local prj_file = vim.fs.joinpath(root, const.project_file_name)

  local default = {
    name = project_name,
    lua = { version = 5.1 },
    yaml = { schemas = {}, schema_store_url = nil },
    json = { schemas = {}, schema_store_url = nil },
  }

  -- If the file doesn't exist in the resolved root, write a standalone file from the system-project template
  if lfs.attributes(prj_file, "mode") == nil then
    local created = require("system_project").create_project_file(root, default)
    local merged = util.merge_table(default, created)
    merged.root = root
    return merged
  end

  -- An existing file is read as stored and never rewritten here
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

-- Project settings for the project that contains `dir` (creating its file when missing).
function M.load_project(dir)
  return load_config(vim.fs.normalize(dir))
end

function M.load()
  local project = load_config()
  system.tmux_rename(project)
  require("tabs.standard").setup(project)
  require("tabs.agentic").setup()
  require("system_project").setup()
  require("tabs.runtime").setup(project)
end

return M
