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
    }
}
