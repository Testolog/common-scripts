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
    },
    -- Deferred: Markdown is rendered by obsidian.nvim (tabs.shared.plugins). Do not load render-markdown.nvim.
    -- {
    --     'MeanderingProgrammer/render-markdown.nvim',
    --     dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-mini/mini.nvim' }, -- if you use the mini.nvim suite
    --     -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-mini/mini.icons' },        -- if you use standalone mini plugins
    --     -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
    --     ---@module 'render-markdown'
    --     ---@type render.md.UserConfig
    --     opts = {},
    -- }
}
