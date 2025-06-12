local mason = require('mason')
local lspconfig = require('lspconfig')
local cmp_nvim_lsp = require('cmp_nvim_lsp')
local mason_lspconfig = require("mason-lspconfig")
local common = require("commons")
local border = common.border
local constant = require("constants")
require("luasnip.loaders.from_vscode").lazy_load()

local lsp_defaults = lspconfig.util.default_config

lsp_defaults.capabilities = vim.tbl_deep_extend(
    'force',
    lsp_defaults.capabilities,
    cmp_nvim_lsp.default_capabilities()
)

local sign = function(opts)
    vim.fn.sign_define(opts.name, {
        texthl = opts.name,
        text = opts.text,
        numhl = ''
    })
end

sign({ name = 'DiagnosticSignError', text = '✘' })
sign({ name = 'DiagnosticSignWarn', text = '▲' })
sign({ name = 'DiagnosticSignHint', text = '⚑' })
sign({ name = 'DiagnosticSignInfo', text = '' })

vim.diagnostic.config({
    virtual_text = true,
    severity_sort = true,
    float = {
        border = 'rounded',
        source = 'always',
    },
})

vim.lsp.handlers['textDocument/hover'] = vim.lsp.with(
    vim.lsp.handlers.hover,
    { border = border('rounded') }
)

vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(
    vim.lsp.diagnostic.on_publish_diagnostics, {
        -- Enable underline, use default values
        underline = true,
        -- Enable virtual text, override spacing to 4
        virtual_text = {
            spacing = 4,
        },
        -- Use a function to dynamically turn signs off
        -- and on, using buffer local variables
        signs = function(namespace, bufnr)
            return vim.b[bufnr].show_signs == true
        end,
        -- Disable a feature
        update_in_insert = false,
    }
)

vim.lsp.handlers['textDocument/signatureHelp'] = vim.lsp.with(
    vim.lsp.handlers.signature_help,
    { border = border('rounded') }
)

mason.setup({})

mason_lspconfig.setup_handlers {
    function(server_name) -- default handler (optional)
        if not common.contains(constant.not_attached_lsp, server_name) then
            lspconfig[server_name].setup({ on_attach = common.lsp_on_attach })
        end
    end
}
-- lspconfig.lua_ls.setup {
--     on_init = function(client)
--         if client.workspace_folders then
--             local path = client.workspace_folders[1].name
--             if vim.loop.fs_stat(path .. '/.luarc.json') or vim.loop.fs_stat(path .. '/.luarc.jsonc') then
--                 return
--             end
--         end
--
--         client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua, {
--             runtime = {
--                 -- Tell the language server which version of Lua you're using
--                 -- (most likely LuaJIT in the case of Neovim)
--                 version = 'LuaJIT'
--             },
--             -- Make the server aware of Neovim runtime files
--             workspace = {
--                 checkThirdParty = false,
--                 library = {
--                     vim.env.VIMRUNTIME
--                     -- Depending on the usage, you might want to add additional paths here.
--                     -- "${3rd}/luv/library"
--                     -- "${3rd}/busted/library",
--                 }
--                 -- or pull in all of 'runtimepath'. NOTE: this is a lot slower and will cause issues when working on your own configuration (see https://github.com/neovim/nvim-lspconfig/issues/3189)
--                 -- library = vim.api.nvim_get_runtime_file("", true)
--             }
--         })
--     end,
--     settings = {
--         Lua = {}
--     }
-- }
