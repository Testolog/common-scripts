return {
    {
        "oclay1st/maven.nvim",
        cmd = { "Maven", "MavenInit", "MavenExec" },
        dependencies = {
            "nvim-lua/plenary.nvim",
            "MunifTanjim/nui.nvim",
        },
        opts = {}, -- options, see default configuration
    },
    { 'williamboman/mason.nvim' },
    { 'williamboman/mason-lspconfig.nvim' },
    {
        "neovim/nvim-lspconfig",
        dependencies = {
            "hrsh7th/cmp-nvim-lsp",
            'williamboman/mason.nvim',
            'williamboman/mason-lspconfig.nvim',
            "hrsh7th/nvim-cmp",
            "saadparwaiz1/cmp_luasnip",
        }
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
        "willothy/flatten.nvim",
        config = true,
        lazy = false,
        priority = 1001,
    },
    {
        "lewis6991/gitsigns.nvim",
        opts = require("configs.gitsigns_opts")
    },
    { "christoomey/vim-tmux-navigator", lazy = false },
    {
        "nvim-tree/nvim-tree.lua",
        lazy = false,
        dependencies = {
            "nvim-tree/nvim-web-devicons",
        },
        config = function()
            local tree = require("nvim-tree")
            local api = require("nvim-tree.api")
            local function refactor_rename()
                local node = api.tree.get_node_under_cursor()
                if not node or node.name == ".." then return end
                api.node.open.edit(node)
                vim.schedule(function()
                    vim.lsp.buf.rename()
                end)
            end
            local function refactor_move()
                local node = api.tree.get_node_under_cursor()
                if not node or node.name == ".." then return end
                api.node.open.edit(node)
                vim.schedule(function()
                    local ok, code_action = pcall(require, "tiny-code-action")
                    if ok and code_action and code_action.code_action then
                        code_action.code_action({ name = "move" })
                    else
                        vim.lsp.buf.code_action({ apply = true, context = { only = { "refactor.rewrite" } } })
                    end
                end)
            end
            local function on_attach(bufnr)
                local opts = function(desc)
                    return { buffer = bufnr, noremap = true, silent = true, nowait = true, desc = "nvim-tree: " .. desc }
                end
                api.config.mappings.default_on_attach(bufnr)
                vim.keymap.set("n", "R", refactor_rename, opts("Rename (refactor project)"))
                vim.keymap.set("n", "M", refactor_move, opts("Move (refactor project)"))
            end
            tree.setup({
                renderer = {
                    group_empty = true,
                    indent_markers = { enable = true },
                },
                filters = { dotfiles = false },
                view = { width = 30 },
                actions = {
                    open_file = { resize_window = false },
                },
                on_attach = on_attach,
            })
        end,
    },
    {
        "mfussenegger/nvim-dap",
        dependencies = {
            "rcarriga/nvim-dap-ui",
            "nvim-neotest/nvim-nio",
        },
        config = function()
            local dap = require("dap")
            local dapui = require("dapui")
            dapui.setup()
            dap.listeners.after.event_initialized["dapui_config"] = function()
                dapui.open()
            end
            dap.listeners.before.event_terminated["dapui_config"] = function()
                dapui.close()
            end
            dap.listeners.before.event_exited["dapui_config"] = function()
                dapui.close()
            end
        end
    },
    {
        'kristijanhusak/vim-dadbod-ui',
        dependencies = {
            { 'tpope/vim-dadbod', lazy = true },
            { 'kristijanhusak/vim-dadbod-completion', ft = { 'sql', 'mysql', 'plsql' }, lazy = true }, -- Optional
        },
        cmd = {
            'DBUI',
            'DBUIToggle',
            'DBUIAddConnection',
            'DBUIFindBuffer',
        },
        init = function ()
            -- Your DBUI configuration
            vim.g.db_ui_use_nerd_fonts = 1
        end,
    }
}
