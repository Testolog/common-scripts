local lspconfig = require("lspconfig")
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
})
lspconfig.ruff.setup({
    settings = {
        ruff_lsp = {
            server_capabilities = {
                hoverProvider = false
            }
        }
    }
})
