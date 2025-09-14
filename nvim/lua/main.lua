M = {}
local const = require("constants")
local system = require("system")
local common = require("commons")
local vim_libs = system.lua_libs_path(vim.fn.stdpath("config"), 5.1)
local function load_config()
    local json = require("cjson")
    local lfs = require("lfs")
    local root = vim.fs.root(0, { const.project_file_name })
    local al_root = vim.fn.getcwd()
    root = root or al_root
    local project_name = vim.fs.basename(root)
    local prj_file = vim.fs.joinpath(root, const.project_file_name)
    local default = {
        name = project_name,
    }
    if lfs.attributes(prj_file, "mode") == nil then
        local file = io.open(prj_file, "w+")
        file:write(json.encode(default))
        file:close()
    else
        local file = io.open(prj_file, "r+")
        local data = file:read("*all")
        data = json.decode(data)
        default = common.merge_table(default, data)
        file:close()
    end
    return default
end
M.collorschema = "catppuccin"
M.options = require("options")
M.load_vim_libs = function ()
    if vim.fn.isdirectory(vim_libs.share) == 1 then
        package.path = package.path .. ";" .. vim_libs.share .. "/?.lua"
    end
    if vim.fn.isdirectory(vim_libs.lib) == 1 then
        package.cpath = package.cpath .. ";" .. vim_libs.lib .. "/?.so"
    end
end
M.load = function ()
    local project = load_config()
    system.auto_commands()
    system.filetype()
    system.tmux_rename(project)
    require("keymapping")
    require("languages").setup(project)
end
return M
