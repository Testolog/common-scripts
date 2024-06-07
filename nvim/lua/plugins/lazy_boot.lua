return {
    {
        "folke/which-key.nvim",
        config = function()
            require("which-key").setup()
        end
    },
    { "folke/neoconf.nvim",   cmd = "Neoconf" },
    { "folke/neodev.nvim" },
    { "nvim-lua/plenary.nvim" },
    {
        "nvim-telescope/telescope.nvim",
        dependencies = { 'nvim-lua/plenary.nvim' },
        config = function()
            require('telescope').setup({
                defaults = {
                    layout_config = {
                        vertical = { width = 0.5 }
                    },
                },
            })
        end
    },
    {
        "catppuccin/nvim",
        name = "catppuccin",
        priority = 1000,
        opts = function()
            require("plugins.catppuccin")
        end
    },
    {
        'nvim-treesitter/nvim-treesitter',
        opts = function()
            local treesitter = require("nvim-treesitter.configs")
            treesitter.setup({
                ensure_installed = { "c", "lua", "vim", "vimdoc", "python", "query" },
                auto_install = true,
                highlight = {
                    enable = true
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
        "folke/which-key.nvim",
        event = "VeryLazy",
        init = function()
            vim.o.timeout = true
            vim.o.timeoutlen = 300
        end,
    },
    { 'williamboman/mason.nvim' },
    { 'williamboman/mason-lspconfig.nvim' },
    { "hrsh7th/nvim-cmp" },
    { "hrsh7th/cmp-buffer" },
    { "hrsh7th/cmp-path" },
    { "hrsh7th/cmp-nvim-lsp" },
    { "saadparwaiz1/cmp_luasnip" },
    { "rafamadriz/friendly-snippets" },
    {
        "L3MON4D3/LuaSnip",
        version = "2.*",
        build = "make install_jsregexp"
    },
    {
        "kdheepak/lazygit.nvim",
        cmd = {
            "LazyGit",
            "LazyGitConfig",
            "LazyGitCurrentFile",
            "LazyGitFilter",
            "LazyGitFilterCurrentFile",
        },
        dependencies = {
            "nvim-lua/plenary.nvim",
        },
    },
    {
        "neovim/nvim-lspconfig",
        dependencies = {
            "hrsh7th/cmp-nvim-lsp",
            'williamboman/mason.nvim',
            'williamboman/mason-lspconfig.nvim',
            "hrsh7th/nvim-cmp",
            "saadparwaiz1/cmp_luasnip",
        },
        config = function()
            require("plugins.lspconfig")
        end
    },
    { "christoomey/vim-tmux-navigator", lazy = false },
    {
        "lewis6991/gitsigns.nvim",
        config = function()
            require("plugins.git-integration")
        end
    },
    {
        "stevearc/aerial.nvim",
        dependencies = {
            'nvim-treesitter/nvim-treesitter'
        },
        config = function()
            require("aerial").setup({
                layout = {
                    max_width = { 40, 0.2 },
                    width = nil,
                    min_width = 20,
                }
            })
        end
    }
}
