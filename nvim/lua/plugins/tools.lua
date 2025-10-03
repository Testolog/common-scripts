local cmdline_config = function ()
    local cmp = require("cmp")
    local mapping = cmp.mapping.preset.cmdline()

    cmp.setup.cmdline("/", { mapping = mapping, sources = { { name = "buffer" } } })

    cmp.setup.cmdline(":", {
        mapping = mapping,
        sources = cmp.config.sources({ { name = "path" } }, {
            {
                name = "cmdline",
                option = { ignore_cmds = { "Man", "!" } },
            },
        }),
    })
end
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
        "lewis6991/gitsigns.nvim",
        opts = require("configs.gitsigns_opts")
    },
    {
        "hrsh7th/nvim-cmp",
        event = 'InsertEnter',
        opts = function ()
            return require("configs.cmp_opts")
        end,
        dependencies = {
            'L3MON4D3/LuaSnip',
            'rafamadriz/friendly-snippets',

            {
                'hrsh7th/cmp-cmdline',
                event = { "InsertEnter", "CmdlineEnter" },
                config = cmdline_config
            },
            "hrsh7th/cmp-buffer",
            "hrsh7th/cmp-path",
            "hrsh7th/cmp-nvim-lua",
            "hrsh7th/cmp-nvim-lsp",
            "saadparwaiz1/cmp_luasnip",
            {
                "windwp/nvim-autopairs",
                opts = { fast_wrap = {}, disable_filetype = { "TelescopePrompt", "vim" } },
                config = function (_, opts) -- setup cmp for autopairs
                    require("nvim-autopairs").setup(opts)
                    local cmp_autopairs = require("nvim-autopairs.completion.cmp")
                    require("cmp").event:on("confirm_done", cmp_autopairs.on_confirm_done())
                end,
            },
        },
    },
    { "christoomey/vim-tmux-navigator", lazy = false },
    {
        "nvim-tree/nvim-tree.lua",
        lazy = false,
        dependencies = {
            "nvim-tree/nvim-web-devicons",
        },
        config = function ()
            local tree = require("nvim-tree")
            tree.setup({
                renderer = {
                    group_empty = true,
                    indent_markers = {
                        enable = true
                    }
                },
                filters = {
                    dotfiles = false
                },
                view = {
                    width = 30
                },
                actions = {
                    open_file = {
                        resize_window = false,
                    },
                }
            })
        end
    },
    {
        "kevinhwang91/nvim-ufo",
        dependencies = {
            "kevinhwang91/promise-async",
            "nvim-treesitter/nvim-treesitter"
        },
        opts = {
            provider_selector = function (bufnr, filetype, buftype)
                return { 'treesitter', 'indent' }
            end
        }
    },
    { "nvim-dap" },
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
