return {
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
        opts = function ()
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
        config = function ()
            require("nvim-surround").setup({
                -- Configuration here, or leave empty to use defaults
            })
        end
    },
    {
        "m-gail/escape.nvim"
    },
    { "b0o/schemastore.nvim" },
    { "mfussenegger/nvim-lint" },
    {
        "nvimtools/none-ls.nvim",
        dependencies = { "nvim-lua/plenary.nvim" },
    },
    {
        "folke/persistence.nvim",
        event = "BufReadPre",
        opts = {
            options = { "buffers", "curdir", "tabpages", "winsize", "help", "terminal", "folds" },
        },
        keys = {
            { "<leader>qs", function () require("persistence").load() end, desc = "Restore session for cwd" },
            { "<leader>ql", function () require("persistence").load({ last = true }) end, desc = "Restore last session" },
            { "<leader>qd", function () require("persistence").stop() end, desc = "Don't save current session" },
        },
    },
    -- lazy.nvim
}
