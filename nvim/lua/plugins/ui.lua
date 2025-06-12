return {
    {
        {
            "SmiteshP/nvim-navbuddy",
            dependencies = {
                "SmiteshP/nvim-navic",
                "MunifTanjim/nui.nvim"
            },
        }
    },
    {
        "catppuccin/nvim",
        name = "catppuccin",
        priority = 1000,
        opts = require("configs.catppuccin_opts")
    },
    {
        "ThePrimeagen/harpoon",
        branch = "harpoon2",
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function()
            local harpoon = require("harpoon")
            harpoon:setup()
        end
    },
    { "mbbill/undotree" },
    { "ryanoasis/vim-devicons" },
    { "vim-airline/vim-airline" },
    {
        "stevearc/aerial.nvim",
        dependencies = {
            'nvim-treesitter/nvim-treesitter'
        },
        opts = {
            layout = {
                width = 0.3,
            }
        }
    },
    {
        "folke/trouble.nvim",
        opts = {},
        cmd = "Trouble",
    },
    { "nvim-tree/nvim-web-devicons" },
    {
        "rose-pine/neovim",
        name = "rose-pine"
    },
    {
        "rachartier/tiny-code-action.nvim",
        dependencies = {
            { "nvim-lua/plenary.nvim" },

            -- optional picker via telescope
            { "nvim-telescope/telescope.nvim" },
            -- optional picker via fzf-lua
            { "ibhagwan/fzf-lua" },
            -- .. or via snacks
            {
                "folke/snacks.nvim",
                opts = {
                    terminal = {},
                }
            }
        },
        event = "LspAttach",
        opts = {},
    },
    {
        "folke/snacks.nvim",
        priority = 1000,
        lazy = false,
        ---@type snacks.Config
        opts = {
            -- your configuration comes here
            -- or leave it empty to use the default settings
            -- refer to the configuration section below
            bigfile = { enabled = true },
            dashboard = { enabled = true },
            picker = { enabled = true },
            notifier = { enabled = false },
            quickfile = { enabled = true },
        },
    },

}
