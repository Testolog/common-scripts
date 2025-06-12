local lspconfig = require 'lspconfig'
local configs = require 'lspconfig.configs'
local util = require 'lspconfig.util'
if not configs["pyright"] then
    configs["pyright"] = {
        default_config = {
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
    }
end
-- TODO asd
-- TODO append configs file is not exist
if not configs["ruff"] then
    configs["ruff"] = {
        default_config = {
            cmd = { "ruff", "server" },
            filetypes = { "python" },
            autostart = true,
            single_file_support = true,
        }
    }
end
lspconfig.pyright.setup({})
lspconfig.ruff.setup({})
