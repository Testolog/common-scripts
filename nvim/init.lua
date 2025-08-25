local vimrc = vim.fn.stdpath("config") .. "/vimrc.vim"
require("options")
-- todo is kind funny, but common has dependency on lib
local commons = require("commons")
local lua_paths = commons.lua_libs_path(vim.fn.stdpath("config"), 5.1)
if vim.fn.isdirectory(lua_paths.share) == 1 then
    package.path = package.path .. ";" .. lua_paths.share .. "/?.lua"
end
if vim.fn.isdirectory(lua_paths.lib) == 1 then
    package.cpath = package.cpath .. ";" .. lua_paths.lib .. "/?.so"
end
require("cjson")
-- vim.cmd.source(vimrc)
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", -- latest stable release
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins", {
    change_detection = {
        enabled = true, -- automatically check for config file changes and reload the ui
        notify = false, -- turn off notifications whenever plugin changes are made
    },
})
local main = require("main")
vim.cmd.colorscheme(main.collorschema)
