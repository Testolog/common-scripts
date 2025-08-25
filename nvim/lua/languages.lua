local java            = require('java')
local lspconfig       = require('lspconfig')
local lazydev         = require("lazydev")
local config          = require("lazy.core.config")
local common          = require("commons")
local mason           = require('mason')
local cmp_nvim_lsp    = require('cmp_nvim_lsp')
local mason_lspconfig = require("mason-lspconfig")
local border          = common.border
local constant        = require("constants")


require("luasnip.loaders.from_vscode").lazy_load()

local capabilities             = vim.lsp.protocol.make_client_capabilities()
local lsp_defaults             = lspconfig.util.default_config

lsp_defaults.capabilities      = vim.tbl_deep_extend(
    'force',
    lsp_defaults.capabilities,
    cmp_nvim_lsp.default_capabilities()
)

vim.g.lazyvim_rust_diagnostics = "bacon-ls"

vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup('lsp_attach_disable_ruff_hover', { clear = true }),
    callback = function(args)
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


-- vim.lsp.handlers["textDocument/typeDefinition"] = function(_, method, result)
--   if result and vim.tbl_islist(result) then
--     print(result)
--     -- Custom logic to open in a new split
--     vim.cmd('vsplit')
--     vim.lsp.util.jump_to_location(result[1])
--   end
-- end
-- vim.lsp.handlers['textDocument/hover'] = vim.lsp.buf.hover({ border = 'rounded' })
-- vim.lsp.handlers['textDocument/signatureHelp'] = vim.lsp.buf.signature_help(
--     { border = border('rounded') }
-- )
--

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
-- java.setup {
--     jdk = {
--         auto_install = false,
--     },
--     auto_install = false,
--     root_markers = {
--         'settings.gradle',
--         'settings.gradle.kts',
--         'pom.xml',
--         'build.gradle',
--         'mvnw',
--         'gradlew',
--         'build.gradle',
--         'build.gradle.kts',
--     },
-- }
lspconfig.lua_ls.setup({
    capabilities = {
        textDocument = {
            typeDefinition = {
                linkSupport = false
            }
        }
    }
})
lazydev.setup({
    enabled = true,
    config = {
        library = {
            "lazy.nvim",
            vim.env.VIMRUNTIME,

            -- { path = '/home/testolog/common-scripts/nvim/lua_modules' },
            -- { path = "/home/testolog/common-scripts/nvim/lua_modules/share/lua/5.4/?.lua;/home/testolog/common-scripts/nvim/lua_modules/share/lua/5.4/?/init.lua;/usr/local/share/lua/5.4/?.lua;/usr/local/share/lua/5.4/?/init.lua;/usr/share/lua/5.4/?.lua;/usr/share/lua/5.4/?/init.lua;/usr/local/lib/lua/5.4/?.lua;/usr/local/lib/lua/5.4/?/init.lua;/usr/lib/lua/5.4/?.lua;/usr/lib/lua/5.4/?/init.lua;./?.lua;./?/init.lua;/home/testolog/.luarocks/share/lua/5.4/?.lua;/home/testolog/.luarocks/share/lua/5.4/?/init.lua" }
        }
    }
})
lspconfig.pyright.setup({
    settings = {
        cmd = { "pyright-langserver", "--stdio" },
        filetypes = { "python" },
        autostart = true,
        single_file_support = true,
        -- root_dir = util.root_pattern("pyproject.toml", "setup.py"),
        settings = {
            pyright = {
                disableOrganizeImports = true
            },
            python = {
                analysis = {
                    autoSearchPaths = true,
                    diagnosticMode = "workspace",
                    useLibraryCodeForTypes = true,
                    autoImportCompletions = true,
                    ignore = { '*' }
                }
            }
        }
    }
})
lspconfig.ruff.setup({
    settings = {
        cmd = { "ruff", "server" },
        filetypes = { "python" },
        autostart = true,
        single_file_support = true,
        ruff_lsp = {
            server_capabilities = {
                hoverProvider = false
            }
        }
    }
})
lspconfig.rust_analyzer.setup({})

mason.setup({})

mason_lspconfig.setup_handlers {
    function(server_name) -- default handler (optional)
        if not common.contains(constant.not_attached_lsp, server_name) then
            lspconfig[server_name].setup({ on_attach = common.lsp_on_attach })
        end
    end
}
