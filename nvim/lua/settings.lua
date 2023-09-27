vim.g.mapleader = " "
vim.keymap.set("n","<leader>pe", vim.cmd.Ex)

vim.opt.encoding="UTF-8"

vim.opt.guicursor = ""

vim.opt.nu = true
vim.opt.relativenumber = true

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

vim.opt.smartindent = true

vim.opt.wrap = false

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true

vim.opt.termguicolors = true

vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")

vim.opt.updatetime = 50

vim.opt.colorcolumn = "120"
vim.keymap.set("v", "<M-S-DOWN>", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "<M-S-UP>", ":m '<-2<CR>gv=gv")
