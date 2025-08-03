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

-- local sign = function(opts)
--     vim.fn.sign_define(opts.name, {
--         texthl = opts.name,
--         text = opts.text,
--         numhl = ''
--     })
-- end
--
-- sign({ name = 'DiagnosticSignError', text = '✘' })
-- sign({ name = 'DiagnosticSignWarn', text = '▲' })
-- sign({ name = 'DiagnosticSignHint', text = '⚑' })
-- sign({ name = 'DiagnosticSignInfo', text = '' })
--
-- vim.diagnostic.config({
--     virtual_text = true,
--     severity_sort = true,
--     float = {
--         border = 'rounded',
--         -- source = 'always',
--     },
-- })

vim.lsp.handlers['textDocument/hover'] = vim.lsp.buf.hover({ border = 'rounded' })
vim.lsp.handlers['textDocument/signatureHelp'] = vim.lsp.buf.signature_help(
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
