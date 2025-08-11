local lspconfig = require("lspconfig")
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
