local M = {}

local lspconfig = require("lspconfig")
local util = require("util")
local table_stdlib = require("table")
local const = require("constants")
local system = require("system")

-- `initial` is the project resolved at startup; `active` is the project of the current Standard tab.
local state = { initial = nil, active = nil, java_ready = false }

local function in_root(dir, root)
    return dir ~= nil and root ~= nil and (dir == root or dir:sub(1, #root + 1) == root .. "/")
end

-- Project whose settings override the startup config for a client rooted at `root_dir`, or nil.
local function tab_override(root_dir)
    local p = state.active
    if p and state.initial and p.root ~= state.initial.root and in_root(root_dir, p.root) then
        return p
    end
end

local function lua_runtimes(project_settings)
    local version = project_settings.lua and project_settings.lua.version or 5.1
    return {
        path = {
            "?.lua",
            "?/init.lua",
            vim.fn.expand("~/.luarocks/share/lua/" .. version .. "/?.lua"),
            vim.fn.expand("~/.luarocks/share/lua/" .. version .. "/?/init.lua"),
            ("/usr/share/%s/?.lua"):format(version),
            ("/usr/share/lua/%s/?/init.lua"):format(version),
        },
        workspace = {
            library = {
                vim.fn.expand("~/.luarocks/share/lua/" .. version),
                ("/usr/share/lua/%s"):format(version),
            },
        },
    }
end

local function lua_config(project_settings)
    local lazydev = require("lazydev")
    local lua_libs = {
        "lazy.nvim",
        vim.env.VIMRUNTIME,
    }
    local default_lua = require("lspconfig.configs.lua_ls")
    local root_path = default_lua.default_config.root_dir
    if project_settings.lua then
        local lua_rocks_lib = system.lua_libs_path(
            root_path(vim.fn.getcwd()),
            project_settings.lua.version
        )
        table_stdlib.insert(lua_libs, lua_rocks_lib.lib)
    end
    lspconfig.lua_ls.setup({
        runtimes = lua_runtimes(project_settings),
        on_new_config = function (new_config, root_dir)
            local p = tab_override(root_dir)
            if p then
                new_config.runtimes = lua_runtimes(p)
            end
        end,
        capabilities = {
            textDocument = {
                typeDefinition = { linkSupport = false },
            },
        },
    })
    lazydev.setup()
end

local function null_lsp()
    local null_ls = require("null-ls")
    null_ls.setup({
        sources = {
            null_ls.builtins.diagnostics.sqlfluff.with({ extra_args = { "--dialect", "sparksql" } }),
            null_ls.builtins.formatting.sqlfluff.with({ extra_args = { "--dialect", "sparksql" } }),
        },
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

local function merge_yaml_schemas(schemastore_schemas, project_schemas)
    if not project_schemas or vim.tbl_isempty(project_schemas) then
        return schemastore_schemas or {}
    end
    local out = vim.tbl_deep_extend("force", {}, schemastore_schemas or {})
    for schema_url, file_match in pairs(project_schemas) do
        if type(file_match) == "string" then
            out[schema_url] = file_match
        elseif type(file_match) == "table" then
            out[schema_url] = file_match
        end
    end
    return out
end

local function merge_json_schemas(schemastore_list, project_schemas)
    local out = vim.islist(schemastore_list) and vim.deepcopy(schemastore_list) or {}
    if not project_schemas or vim.tbl_isempty(project_schemas) then
        return out
    end
    for schema_url, file_match in pairs(project_schemas) do
        local fm = type(file_match) == "string" and { file_match } or file_match
        if type(fm) == "table" then
            out[#out + 1] = { url = schema_url, fileMatch = fm }
        end
    end
    return out
end

local function schema_settings(project_settings)
    project_settings = project_settings or {}
    local yaml_cfg = project_settings.yaml or {}
    local json_cfg = project_settings.json or {}
    local schema_store_url = yaml_cfg.schema_store_url or json_cfg.schema_store_url

    local yaml_schemas = merge_yaml_schemas(require("schemastore").yaml.schemas(), yaml_cfg.schemas)
    local json_schemas = merge_json_schemas(require("schemastore").json.schemas(), json_cfg.schemas)

    local yaml_settings = {
        schemaStore = {
            enable = schema_store_url == nil,
            url = schema_store_url or "",
        },
        schemas = yaml_schemas,
        validate = true,
        completion = true,
        hover = true,
        format = {
            enable = true,
            singleQuote = false,
            bracketSpacing = true,
            proseWrap = "preserve",
        },
    }
    local json_settings = {
        schemas = json_schemas,
        validate = true,
        completion = true,
        hover = true,
        format = {
            enable = true,
            tabSize = 2,
        },
    }
    return { yaml = yaml_settings }, { json = json_settings }
end

local function schema_support(project_settings)
    local yaml_settings, json_settings = schema_settings(project_settings)
    lspconfig.yamlls.setup({
        settings = yaml_settings,
        on_new_config = function (new_config, root_dir)
            local p = tab_override(root_dir)
            if p then
                new_config.settings = (schema_settings(p))
            end
        end,
    })
    lspconfig.jsonls.setup({
        settings = json_settings,
        on_new_config = function (new_config, root_dir)
            local p = tab_override(root_dir)
            if p then
                local _, json = schema_settings(p)
                new_config.settings = json
            end
        end,
    })
    lspconfig.taplo.setup({
        settings = { evenBetterToml = {} },
    })
end

local function java_home_for(root)
    local out = vim.fn.system({ "sh", "-c", "cd " .. vim.fn.shellescape(root) .. " && jenv javahome" })
    local java_home = out and vim.trim(out) or ""
    if java_home == "" or vim.fn.isdirectory(java_home) ~= 1 then
        return nil
    end
    return java_home
end

local function apply_java_home(config, java_home)
    local path_env = vim.fn.getenv("PATH") or ""
    config.cmd_env = vim.tbl_extend("force", config.cmd_env or {}, {
        JAVA_HOME = java_home,
        PATH = java_home .. "/bin:" .. path_env,
    })
    config.settings = config.settings or {}
    config.settings.java = config.settings.java or {}
    config.settings.java.configuration = config.settings.java.configuration or {}
    config.settings.java.configuration.runtimes = { { name = "jenv", path = java_home, default = true } }
end

-- Returns true when jdtls was configured.
local function java_config(root)
    local java_home = java_home_for(root)
    if not java_home then
        vim.notify("Java: jenv javahome did not return a valid path. jdtls disabled.", vim.log.levels.WARN)
        return false
    end
    require("java").setup({
        jdk = { auto_install = false },
        auto_install = false,
        root_markers = {
            "settings.gradle", "settings.gradle.kts", "pom.xml", "build.gradle",
            "mvnw", "gradlew", "build.gradle.kts",
        },
    })
    local path_env = vim.fn.getenv("PATH") or ""
    lspconfig.jdtls.setup({
        cmd_env = {
            JAVA_HOME = java_home,
            PATH = java_home .. "/bin:" .. path_env,
        },
        on_new_config = function (new_config, root_dir)
            local p = tab_override(root_dir)
            local tab_home = p and java_home_for(p.root)
            if tab_home then
                apply_java_home(new_config, tab_home)
            end
        end,
        settings = {
            java = {
                configuration = {
                    runtimes = { { name = "jenv", path = java_home, default = true } },
                },
                import = { maven = { enabled = true }, gradle = { enabled = true } },
                autobuild = { enabled = true },
                contentProvider = { preferred = "fernflower" },
                completion = {
                    favoriteStaticMembers = {
                        "org.junit.Assert.*",
                        "org.junit.jupiter.api.Assertions.*",
                        "org.mockito.Mockito.*",
                        "org.mockito.ArgumentMatchers.*",
                        "org.springframework.test.web.servlet.result.MockMvcResultMatchers.*",
                        "org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*",
                    },
                    importOrder = { "java", "javax", "com", "org", "org.springframework", "org.springframework.boot", "#" },
                },
                sources = { organizeImports = { starThreshold = 9999, staticStarThreshold = 9999 } },
            },
        },
    })
    return true
end

function M.setup(project_settings)
    local java = require("java")
    local mason = require("mason")
    local cmp_nvim_lsp = require("cmp_nvim_lsp")
    local mason_lspconfig = require("mason-lspconfig")

    require("luasnip.loaders.from_vscode").lazy_load()

    local capabilities = vim.lsp.protocol.make_client_capabilities()
    local lsp_defaults = lspconfig.util.default_config
    lsp_defaults.capabilities = vim.tbl_deep_extend(
        "force",
        lsp_defaults.capabilities,
        cmp_nvim_lsp.default_capabilities()
    )

    vim.g.lazyvim_rust_diagnostics = "bacon-ls"

    vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("lsp_attach_disable_ruff_hover", { clear = true }),
        callback = function (args)
            local client = vim.lsp.get_client_by_id(args.data.client_id)
            if client and client.name == "ruff" then
                client.server_capabilities.hoverProvider = false
            end
        end,
        desc = "LSP: Disable hover capability from Ruff",
    })

    lua_config(project_settings)
    schema_support(project_settings)
    null_lsp()

    -- Java: JAVA_HOME from `jenv javahome` run from project root; no fallback, skip jdtls if missing.
    state.initial = project_settings
    state.active = project_settings
    state.java_ready = java_config(project_settings and project_settings.root or vim.fn.getcwd())

    lspconfig.pyright.setup({
        cmd = { "pyright-langserver", "--stdio" },
        filetypes = { "python" },
        capabilities = capabilities,
        autostart = true,
        single_file_support = true,
        root_dir = lspconfig.util.root_pattern("pyproject.toml", "setup.py", ".git"),
        settings = {
            pyright = { disableOrganizeImports = true },
            python = {
                pythonPath = vim.fn.exepath("python"),
                analysis = {
                    autoImportCompletions = true,
                    autoSearchPaths = true,
                    diagnosticMode = "workspace",
                    useLibraryCodeForTypes = true,
                    typeCheckingMode = "basic",
                    extraPaths = {}, -- Can be populated dynamically if needed
                    stubPath = "typings",
                    indexing = true, -- Force aggressive indexing
                    packageIndexDepths = {
                        { name = "airflow", depth = 5, includeSubModules = true }
                    },
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
        init_options = { settings = { organizeImports = false } },
        on_attach = function (client)
            client.server_capabilities.hoverProvider = false
        end,
    })
    lspconfig.rust_analyzer.setup({})

    -- C/C++ (clangd)
    lspconfig.clangd.setup({
        capabilities = capabilities,
        filetypes = { "c", "cpp", "objc", "objcpp" },
        cmd = {
            "clangd",
            "--background-index",
            "--clang-tidy",
            "--header-insertion=iwyu",
        },
    })

    -- Arduino Language Server (requires: arduino-language-server, arduino-cli, clangd; sketch.yaml in sketch dir)
    lspconfig.arduino_language_server.setup({
        capabilities = capabilities,
        filetypes = { "arduino" },
        root_dir = lspconfig.util.root_pattern("*.ino"),
    })

    mason.setup({})
    mason_lspconfig.setup({
        ensure_installed = { "yamlls", "rust_analyzer" },
        automatic_installation = false,
        automatic_enable = true,
    })
end

-- Standard TabEnter: make `project_settings` (that tab's .nvim_project.json) the source for
-- project-sensitive pieces. Clients started later under its root pick up its Lua runtimes,
-- YAML/JSON schemas, and jenv JAVA_HOME through on_new_config; yamlls/jsonls clients already
-- running under that root get the new schemas. The startup project is left exactly as configured.
function M.refresh(project_settings)
    if not state.initial or not project_settings or not project_settings.root then
        return
    end
    state.active = project_settings
    if project_settings.root == state.initial.root then
        return
    end
    if not state.java_ready and java_home_for(project_settings.root) then
        state.java_ready = java_config(project_settings.root)
    end
    local yaml, json = schema_settings(project_settings)
    local by_name = { yamlls = yaml, jsonls = json }
    for _, client in ipairs(vim.lsp.get_clients()) do
        local settings = by_name[client.name]
        if settings and in_root(client.config.root_dir, project_settings.root) then
            client.settings = settings
            client.config.settings = settings
            if vim.fn.has("nvim-0.11") == 1 then
                client:notify("workspace/didChangeConfiguration", { settings = settings })
            else
                client.notify("workspace/didChangeConfiguration", { settings = settings })
            end
        end
    end
end

return M
