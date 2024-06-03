local treesitter = require("nvim-treesitter.configs")

treesitter.setup({
    ensure_installed = {"c", "lua", "vim", "vimdoc", "python", "query" },
    auto_install = true,
    highlight = {
        enable = true
    },
})
