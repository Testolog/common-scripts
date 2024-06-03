local mark = require("harpoon.mark")
local ui = require("harpoon.ui")

vim.keymap.set("n", "<leader>a", mark.add_file, {desc = "harpoon add file" })
vim.keymap.set("n", "<leader>e", ui.toggle_quick_menu, {desc = "harpoon quick menu"})

vim.keymap.set("n", "<leader>1", function() ui.nav_file(1) end, {desc="first tab"})
vim.keymap.set("n", "<leader>2", function() ui.nav_file(2) end, {desc="sec tab"})
vim.keymap.set("n", "<leader>3", function() ui.nav_file(3) end, {desc="threed tab"})
vim.keymap.set("n", "<leader>4", function() ui.nav_file(4) end, {desc="four tab"})
