require('mason').setup({})
require('mason-lspconfig').setup({})
require('luasnip.loaders.from_vscode').lazy_load()
local lspconfig = require('lspconfig')
local cmp = require('cmp')
local luasnip = require('luasnip')
local function border(hl_name)
    return {
        { "╭", hl_name },
        { "─", hl_name },
        { "╮", hl_name },
        { "│", hl_name },
        { "╯", hl_name },
        { "─", hl_name },
        { "╰", hl_name },
        { "│", hl_name },
    }
end
local lsp_defaults = lspconfig.util.default_config

lsp_defaults.capabilities = vim.tbl_deep_extend(
    'force',
    lsp_defaults.capabilities,
    require('cmp_nvim_lsp').default_capabilities()
)

vim.opt.completeopt = { 'menu', 'menuone', 'noselect' }

local select_opts = { behavior = cmp.SelectBehavior.Select }

cmp.setup({
    snippet = {
        expand = function(args)
            luasnip.lsp_expand(args.body)
        end
    },
    sources = {
        { name = 'path' },
        { name = 'nvim_lsp', keyword_length = 1 },
        { name = 'buffer',   keyword_length = 3 },
        { name = 'luasnip',  keyword_length = 2 },
    },
    window = {
        completion = {
            border = border "CmpBorder",
            winhighlight = "Normal:CmpPmenu,CursorLine:PmenuSel,Search:None",
        },
        documentation = {
            border = border "CmpDocBorder",
        },
    },
    formatting = {
        fields = { 'menu', 'abbr', 'kind' },
        format = function(entry, item)
            local menu_icon = {
                nvim_lsp = 'λ',
                luasnip = '⋗',
                buffer = 'Ω',
                path = '🖫',
            }

            item.menu = menu_icon[entry.source.name]
            return item
        end,
    },
    mapping = {
        ['<Up>'] = cmp.mapping.select_prev_item(select_opts),
        ['<Down>'] = cmp.mapping.select_next_item(select_opts),
        ['<C-p>'] = cmp.mapping.select_prev_item(select_opts),
        ['<C-n>'] = cmp.mapping.select_next_item(select_opts),
        ['<CR>'] = cmp.mapping.confirm({ select = true }),
        ["<C-Space>"] = cmp.mapping.complete(),
    },
})
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
    virtual_text = false,
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

vim.lsp.handlers['textDocument/signatureHelp'] = vim.lsp.with(
    vim.lsp.handlers.signature_help,
    { border = border('rounded') }
)
local on_attach = function(client, bufnr)
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')
    local bufopts = { noremap = true, silent = true, buffer = bufnr }

    -- Displays hover information about the symbol under the cursor
    vim.keymap.set('n', 'K', vim.lsp.buf.hover, bufopts)

    -- Jump to the definition
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bufopts)

    -- Jump to declaration
    vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, bufopts)

    -- Lists all the implementations for the symbol under the cursor
    vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, bufopts)

    -- Jumps to the definition of the type symbol
    vim.keymap.set('n', 'go', vim.lsp.buf.type_definition, bufopts)

    -- Lists all the references
    vim.keymap.set('n', 'gr', vim.lsp.buf.references, bufopts)

    vim.keymap.set('n', '<leader>l', function()
        vim.lsp.buf.format { async = true }
    end, bufopts)

    -- Displays a function's signature information
    vim.keymap.set('n', 'gs', vim.lsp.buf.signature_help, bufopts)

    -- Renames all references to the symbol under the cursor
    vim.keymap.set('n', '<leader>wr', vim.lsp.buf.rename, bufopts)

    -- Selects a code action available at the current cursor position
    vim.keymap.set('n', '<leader>wa', vim.lsp.buf.code_action, bufopts)
    vim.keymap.set('x', '<leader>wq', vim.lsp.buf.range_code_action, bufopts)

    -- Show diagnostics in a floating window
    vim.keymap.set('n', 'gl', vim.diagnostic.open_float, bufopts)

    -- Move to the previous diagnostic
    vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, bufopts)

    -- Move to the next diagnostic
    vim.keymap.set('n', ']d', vim.diagnostic.goto_next, bufopts)
end
lspconfig.tsserver.setup({ on_attach = on_attach })
lspconfig.lua_ls.setup({ on_attach = on_attach })
lspconfig.pyright.setup({ on_attach = on_attach })
