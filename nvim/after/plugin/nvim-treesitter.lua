local treesitter = require("nvim-treesitter.configs")
local aerial = require("aerial")
treesitter.setup({
    ensure_installed = { "c", "lua", "vim", "vimdoc", "python", "query" },
    auto_install = true,
    highlight = {
        enable = true
    },
})
aerial.setup({})
vim.keymap.set("n", "<leader>ts", "<cmd>AerialToggle left<CR>")
