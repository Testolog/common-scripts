local const = require("constants")

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
        "nvim-lua/plenary.nvim",
        priority = 51
    },
    { "MunifTanjim/nui.nvim" },
    {
        "folke/which-key.nvim",
        event = "VeryLazy",
        init = function ()
            vim.o.timeout = true
            vim.o.timeoutlen = 300
        end,
    },
    {
        "nvim-telescope/telescope.nvim",
        dependencies = { 'nvim-lua/plenary.nvim' },
        opts = require("configs.telescope_opts")
    },
    {
        -- `main` is the rewrite for Neovim 0.12; parsers are built with tree-sitter-cli.
        'nvim-treesitter/nvim-treesitter',
        branch = "main",
        lazy = false,
        build = ":TSUpdate",
        config = function ()
            require("tabs.shared.treesitter").setup(const.treesitter.lang)
        end,
    },
    {
        "catppuccin/nvim",
        name = "catppuccin",
        priority = 1000,
        opts = require("configs.catppuccin_opts")
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
        "kevinhwang91/nvim-ufo",
        dependencies = {
            "kevinhwang91/promise-async",
            "nvim-treesitter/nvim-treesitter"
        },
        opts = {
            provider_selector = function (bufnr, filetype, buftype)
                -- Agentic read buffers fold only between explicit {{{agentic / }}}agentic markers.
                if vim.b[bufnr].agentic_read then
                    return 'marker'
                end
                return { 'treesitter', 'indent' }
            end
        }
    },
    { "rafamadriz/friendly-snippets" },
    {
        "L3MON4D3/LuaSnip",
        dependencies = { "rafamadriz/friendly-snippets" },
        version = "2.*",
        build = "make install_jsregexp"
    },
    {
        "hrsh7th/nvim-cmp",
        event = 'InsertEnter',
        opts = function ()
            return require("configs.cmp_opts")
        end,
        config = function (_, opts)
            local cmp = require("cmp")
            cmp.setup(opts)
            require("tabs.shared.cmp_project").register()
            local markdown_sources = vim.deepcopy(opts.sources or {})
            table.insert(markdown_sources, { name = "nvim_project" })
            cmp.setup.filetype("markdown", { sources = markdown_sources })
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
    {
        -- Requires Neovim 0.11 and ripgrep; the vault follows the tab (tabs.shared.obsidian).
        "obsidian-nvim/obsidian.nvim",
        version = "*",
        enabled = vim.fn.has("nvim-0.11") == 1,
        ft = "markdown",
        cmd = "Obsidian",
        dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope.nvim" },
        opts = function ()
            return {
                legacy_commands = false,
                workspaces = {
                    {
                        name = "tab",
                        strict = true,
                        path = function ()
                            return require("tabs.shared.obsidian").vault()
                        end,
                    },
                },
                picker = { name = "telescope.nvim" },
                -- Agent write notes are sent verbatim as the next message.
                frontmatter = {
                    enabled = function (fname)
                        return not (fname and ("/" .. fname):find("/.agentic/notes/", 1, true))
                    end,
                },
            }
        end,
        config = function (_, opts)
            require("obsidian").setup(opts)
            require("tabs.shared.obsidian").sync()
        end,
    },
}
