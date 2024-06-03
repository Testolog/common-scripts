local mason = require('mason')
local lspconfig = require('lspconfig')
local cmp = require('cmp')
local cmp_nvim_lsp = require('cmp_nvim_lsp')
local luasnip = require('luasnip')
local mason_lspconfig = require("mason-lspconfig")


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

local function bufopts(desc, bufnr)
    return { desc = desc, noremap = true, silent = true, buffer = bufnr }
end

local on_attach = function(client, bufnr)
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

    vim.keymap.set('n', '<leader>shi', vim.lsp.buf.hover, bufopts("show hover information", bufnr))
    vim.keymap.set('n', '<leader>sai', vim.lsp.buf.implementation, bufopts("show all implementations", bufnr))
    vim.keymap.set('n', '<ledaer>sar', vim.lsp.buf.references, bufopts("show all references", bufnr))
    vim.keymap.set('n', '<leader>lgd', vim.lsp.buf.definition, bufopts("Go to definition", bufnr))
    vim.keymap.set('n', '<leader>lgD', vim.lsp.buf.declaration, bufopts("Go to declaration", bufnr))
    vim.keymap.set('n', '<leader>lgs', vim.lsp.buf.type_definition, bufopts("Go to definition symbol", bufnr))
    vim.keymap.set('n', '<leader>lf', function() vim.lsp.buf.format { async = true } end, bufopts("formatting", bufnr))
    vim.keymap.set('n', '<leader>lss', vimdlsp.buf.signature_help, bufopts("show signature", bufnr))
    vim.keymap.set('n', '<leader>lwr', vim.lsp.buf.rename, bufopts("rename", bufnr))
    vim.keymap.set('n', '<leader>sdm', function(cfg)
        return vim.diagnostic.open_float(cfg, { focus = true, scope = "cursor" })
    end, bufopts("show diagnostics message", bufnr))

    vim.keymap.set('n', '<leader>sdp', vim.lsp.diagnostic.goto_prev, bufopts("prev diagnostics", bufnr))
    vim.keymap.set('n', '<leader>sdn', vim.lsp.diagnostic.goto_next, bufopts("next diagnostics", bufnr))
    vim.keymap.set('n', '<leader>lwa', vim.lsp.buf.code_action, bufopts("code actions", bufnr))
    vim.keymap.set('v', '<leader>lwr', vim.lsp.buf.range_code_action, bufopts("range code actions", bufnr))
end

local select_opts = { behavior = cmp.SelectBehavior.Select }
local lsp_defaults = lspconfig.util.default_config

lsp_defaults.capabilities = vim.tbl_deep_extend(
    'force',
    lsp_defaults.capabilities,
    cmp_nvim_lsp.default_capabilities()
)

vim.opt.completeopt = { 'menu', 'menuone', 'noselect' }

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
        ['<S-Tab>'] = cmp.mapping.select_prev_item(select_opts),
        ['<Tab>'] = cmp.mapping.select_next_item(select_opts),
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

--Issue with it, because masson install this lsp into venv and not for active python
lspconfig.pyright.setup({
    settings = {
        pyright = {
            disableOrganizeImports = true,
        },
        python = {
            analysis = {
                ignore = { '*' },
            },
        },
    },
    on_attach = on_attach
})
lspconfig.ruff_lsp.setup({
    settings = {
        ruff_lsp = {
            server_capabilities = {
                hoverProvider = false
            }
        }
    },
    on_attach = on_attach
})

mason.setup({})
mason_lspconfig.setup({})
mason_lspconfig.setup_handlers {
    function(server_name) -- default handler (optional)
        lspconfig[server_name].setup({ on_attach = on_attach })
    end,
}
