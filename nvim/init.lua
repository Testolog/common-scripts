require("options")

local main = require("main")
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

main.load_vim_libs(5.1)

require("lazy").setup("plugins", {
  change_detection = { enabled = true, notify = false },
})

vim.cmd.colorscheme(main.colorscheme)
main.load()
