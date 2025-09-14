local const = require("constants")

return {
    {
        "nvim-lua/plenary.nvim",
        priority = 51
    },
    {
        "folke/which-key.nvim",
        event = "VeryLazy",
        init = function()
            vim.o.timeout = true
            vim.o.timeoutlen = 300
        end,
    },
    {
        'nvim-treesitter/nvim-treesitter',
        opts = function()
            local treesitter = require("nvim-treesitter.configs")
            treesitter.setup({
                ensure_installed = const.treesitter.lang,
                auto_install = true,
                sync_install = false,
                ignore_install = {},
                modules = {},
                highlight = {
                    enable = true,
                    disable = "help"
                },
            })
        end,
        cmd = "TSUpdate",
    },
    {
        'nvim-treesitter/playground',
        dependecies = { 'nvim-treesitter/nvim-treesitter' }
    },
    {
        "nvim-telescope/telescope.nvim",
        dependencies = { 'nvim-lua/plenary.nvim' },
        opts = require("configs.telescope_opts")
    },
    {
        "sotte/presenting.nvim",
        opts = {
            options = {
                width = 100,
            },
        },
        cmd = { "Presenting" },
    },
    {
        "j-hui/fidget.nvim",
        opts = function()
            require("fidget")
        end,
    },
    {
        'stevearc/quicker.nvim',
        event = "FileType qf",
        ---@module "quicker"
        ---@type quicker.SetupOptions
        opts = {},
    },
    {
        "kylechui/nvim-surround",
        version = "^3.0.0", -- Use for stability; omit to use `main` branch for the latest features
        event = "VeryLazy",
        config = function()
            require("nvim-surround").setup({
                -- Configuration here, or leave empty to use defaults
            })
        end
    }
}
