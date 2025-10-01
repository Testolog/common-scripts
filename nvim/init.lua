local vimrc = vim.fn.stdpath("config") .. "/vimrc.vim"
require("options")
-- todo is kind funny, but common has dependency on lib
local main = require("main")
local lua_version = 5.1

main.load_vim_libs(lua_version)
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
vim.cmd.colorscheme(main.collorschema)
main.load()

