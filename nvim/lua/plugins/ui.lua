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
        config = function ()
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
            {
                "folke/snacks.nvim",
                opts = {
                    terminal = {},
                }
            },

        },
        event = "LspAttach",
        opts = {
            picker = "snacks"
        },
    },
    {
        "folke/snacks.nvim",
        priority = 1000,
        lazy = false,
        opts = {
            -- your configuration comes here
            -- or leave it empty to use the default settings
            -- refer to the configuration section below
            bigfile = { enabled = true },
            dashboard = { enabled = true },
            picker = { enabled = true },
            notifier = { enabled = false },
            quickfile = { enabled = true },
            terminal = { enabled = true },
            matcher = {
                frecency = true
            }
        },
    },
    {
        "rachartier/tiny-inline-diagnostic.nvim",
        event = "VeryLazy", -- Or `LspAttach`
        priority = 1001,    -- needs to be loaded in first
        config = function ()
            require('tiny-inline-diagnostic').setup({ preset = "modern" })
            vim.diagnostic.config({ virtual_text = false }) -- Only if needed in your configuration, if you already have native LSP diagnostics
        end
    },
    {
        "rebelot/heirline.nvim",
    },
    {
        "folke/noice.nvim",
        event = "VeryLazy",
        enabled = false,
        opts = {
            background_colour = "#000000",

            -- add any options here
        },
        dependencies = {
            -- if you lazy-load any plugin below, make sure to add proper `module="..."` entries
            "MunifTanjim/nui.nvim",
            -- OPTIONAL:
            --   `nvim-notify` is only needed, if you want to use the notification view.
            --   If not available, we use `mini` as the fallback
            "rcarriga/nvim-notify",
        }
    },
    {
        "folke/edgy.nvim",
        event = "VeryLazy",
        opts = {}
    },
    -- Lua
    {
        "folke/zen-mode.nvim",
        opts = {
            width = .85

        }
    }
}
