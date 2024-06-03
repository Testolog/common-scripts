local plugins = {
    { "folke/which-key.nvim" },
    { "folke/neoconf.nvim",   cmd = "Neoconf" },
    { "folke/neodev.nvim" },
    { "nvim-lua/plenary.nvim" },
    {
        "nvim-telescope/telescope.nvim",
        dependencies = { 'nvim-lua/plenary.nvim' },
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
            require("plugins.treesitter")
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
        dependencies = { "nvim-lua/plenary.nvim" }
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
        -- optional for floating window border decoration
        dependencies = {
            "nvim-lua/plenary.nvim",
        },
        -- setting the keybinding for LazyGit with 'keys' is recommended in
        -- order to load the plugin when the command is run for the first time
        keys = {
            { "<leader>lg", "<cmd>LazyGit<cr>", desc = "LazyGit" }
        }
    },
    { "neovim/nvim-lspconfig" },
    { "christoomey/vim-tmux-navigator", lazy = false },
}
return plugins
