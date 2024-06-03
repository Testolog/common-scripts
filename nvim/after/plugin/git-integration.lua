vim.keymap.set("n", "<leader>lg", vim.cmd.LazyGit, { desc = "LazyGit" })
local gitsigns = require("gitsigns")
gitsigns.setup()
vim.keymap.set("n", "<leader>sd",gitsigns.diffthis,{desc = "difference this"} )
vim.keymap.set("n", "<leader>sh",gitsigns.stage_hunk ,{desc = "stage hunk"} )

