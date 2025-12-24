M = {}

local lspconfig = require('lspconfig')
local common = require("commons")
local system = require("system")
local table = require("table")
local function lua_config(project_settings)
    local lazydev = require("lazydev")

    local lua_libs = {
        "lazy.nvim",
        vim.env.VIMRUNTIME,
        -- { path = '/home/testolog/common-scripts/nvim/lua_modules' },
        -- { path = "/home/testolog/common-scripts/nvim/lua_modules/share/lua/5.4/?.lua;/home/testolog/common-scripts/nvim/lua_modules/share/lua/5.4/?/init.lua;/usr/local/share/lua/5.4/?.lua;/usr/local/share/lua/5.4/?/init.lua;/usr/share/lua/5.4/?.lua;/usr/share/lua/5.4/?/init.lua;/usr/local/lib/lua/5.4/?.lua;/usr/local/lib/lua/5.4/?/init.lua;/usr/lib/lua/5.4/?.lua;/usr/lib/lua/5.4/?/init.lua;./?.lua;./?/init.lua;/home/testolog/.luarocks/share/lua/5.4/?.lua;/home/testolog/.luarocks/share/lua/5.4/?/init.lua" }
    }
    local default_lua = require("lspconfig.configs.lua_ls")
    local root_path = default_lua.default_config.root_dir
    if common.contains(project_settings, "lua") then
        local lua_rocks_lib = system.lua_libs_path(
            root_path(vim.fn.getcwd()), project_settings.lua.version
        )
        table.insert(lua_libs, lua_rocks_lib.lib)
    end
    local version = project_settings.lua.version or 5.1
    lspconfig.lua_ls.setup({
        runtimes = {
            path = {
                '?.lua',
                '?/init.lua',
                vim.fn.expand '~/.luarocks/share/lua/%s/?.lua':format(version),
                vim.fn.expand '~/.luarocks/share/lua/%s/?/init.lua':format(version),
                ('/usr/share/%s/?.lua'):format(version),
                ('/usr/share/lua/%s/?/init.lua'):format(version)
            },
            workspace = {
                library = {
                    vim.fn.expand '~/.luarocks/share/lua/%s':format(version),
                    ('/usr/share/lua/%s'):format(version)
                }
            }
        },
        capabilities = {
            textDocument = {
                typeDefinition = {
                    linkSupport = false
                }
            }
        }
    })
    lazydev.setup()
end
-- local function linter()
--     require("lint").linters_by_ft =  {
--         sql = { "sqlfluff" },
--     }
-- end
local function null_lsp()
    local null_ls = require("null-ls")
    null_ls.setup({
        sources = {
            -- Diagnostics (lint)
            null_ls.builtins.diagnostics.sqlfluff.with({
                extra_args = { "--dialect", "sparksql" },
            }),

            -- Formatting (sqlfluff fix)
            null_ls.builtins.formatting.sqlfluff.with({
                extra_args = { "--dialect", "sparksql" },
            }),
        },

        -- behaves like LSP
        on_attach = function (client, bufnr)
            if client.supports_method("textDocument/formatting") then
                vim.api.nvim_create_autocmd("BufWritePre", {
                    buffer = bufnr,
                    callback = function ()
                        vim.lsp.buf.format({ bufnr = bufnr })
                    end,
                })
            end
        end,
    })
end
local function schema_support(project_settings)
    lspconfig.yamlls.setup({
        settings = {
            yaml = {
                schemaStore = {
                    -- You must disable built-in schemaStore support if you want to use
                    -- this plugin and its advanced options like `ignore`.
                    enable = false,
                    -- Avoid TypeError: Cannot read properties of undefined (reading 'length')
                    url = "",
                },
                schemas = require('schemastore').yaml.schemas(),
                validate = true,
                completion = true,
                hover = true,
            },
        }
    })
    lspconfig.jsonls.setup({
        settings = {
            json = {
                schemas = require('schemastore').json.schemas(),
                validate = true,
                completion = true,
                hover = true,
            },
        },
    })
    lspconfig.taplo.setup {
        settings = {
            evenBetterToml = {
            }
        }
    }
    -- lspconfig.tombi.setup({})
end
M.setup = function (project_settings)
    local java = require('java')
    local config = require("lazy.core.config")
    local mason = require('mason')
    local cmp_nvim_lsp = require('cmp_nvim_lsp')
    local mason_lspconfig = require("mason-lspconfig")
    local border = common.border
    local constant = require("constants")


    require("luasnip.loaders.from_vscode").lazy_load()

    local capabilities = vim.lsp.protocol.make_client_capabilities()
    local lsp_defaults = lspconfig.util.default_config

    lsp_defaults.capabilities = vim.tbl_deep_extend(
        'force',
        lsp_defaults.capabilities,
        cmp_nvim_lsp.default_capabilities()
    )

    vim.g.lazyvim_rust_diagnostics = "bacon-ls"

    vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup('lsp_attach_disable_ruff_hover', { clear = true }),
        callback = function (args)
            local client = vim.lsp.get_client_by_id(args.data.client_id)
            if client == nil then
                return
            end
            if client.name == 'ruff' then
                -- Disable hover in favor of Pyright
                client.server_capabilities.hoverProvider = false
            end
        end,
        desc = 'LSP: Disable hover capability from Ruff',
    })

    lua_config(project_settings)
    schema_support(project_settings)
    null_lsp()
    -- linter()


    lspconfig.jdtls.setup {
        settings = {
            java = {
                configuration = {
                    runtimes = {
                        {
                            name = "11",
                            path = "/Users/rnad/Library/Java/JavaVirtualMachines/corretto-11.0.25/Contents/Home",
                            default = true,
                        },
                        {
                            name = "17",
                            path = "/opt/homebrew/Cellar/openjdk@17/17.0.14",
                            default = false,
                        },
                        {
                            name = "21",
                            path = "/opt/homebrew/Cellar/openjdk@21/21.0.6",
                            default = false,
                        }
                    }
                }
            }
        }
    }
    java.setup {
        jdk = {
            auto_install = false,
        },
        auto_install = false,
        root_markers = {
            'settings.gradle',
            'settings.gradle.kts',
            'pom.xml',
            'build.gradle',
            'mvnw',
            'gradlew',
            'build.gradle',
            'build.gradle.kts',
        },
    }
    lspconfig.pyright.setup({
        cmd = { "pyright-langserver", "--stdio" },
        filetypes = { "python" },
        capabilities = capabilities,
        autostart = true,
        single_file_support = true,
        root_dir = lspconfig.util.root_pattern(
            "pyproject.toml",
            "setup.py",
            ".git"
        ),
        settings = {
            pyright = {
                disableOrganizeImports = true,
            },
            python = {
                pythonPath = vim.fn.exepath("python"),
                analysis = {
                    autoImportCompletions = true,
                    autoSearchPaths = true,
                    diagnosticMode = "workspace",
                    useLibraryCodeForTypes = true,
                    typeCheckingMode = "basic",
                },
            },
        },
    })
    lspconfig.ruff.setup({
        cmd = { "ruff", "server" },
        filetypes = { "python" },
        capabilities = capabilities,
        autostart = true,
        single_file_support = true,
        init_options = {
            settings = {
                organizeImports = false,
            },
        },
        on_attach = function (client)
            client.server_capabilities.hoverProvider = false
        end,
    })
    lspconfig.rust_analyzer.setup({})
    mason.setup({})
    mason_lspconfig.setup({
        ensure_installed = { "yamlls", 'rust_analyzer' },
        automatic_installation = false,
        automatic_enable = true
    })
end
return M
