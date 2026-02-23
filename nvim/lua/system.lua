M = {}
M.lua_libs_path = function (root, lua_version)
    local luarocks = vim.fn.join({ root, "lua_modules" }, "/")
    local share = vim.fn.join({ luarocks, "share", "lua", lua_version, }, "/")
    local lib = vim.fn.join({ luarocks, "lib", "lua", lua_version, }, "/")
    return {
        share = share,
        lib = lib
    }
end
M.user_command = function (project_settings)
    vim.api.nvim_create_user_command(
        "JsonFormat",
        function ()
            vim.cmd("%!jq")
        end,
        {
            desc = "json format with jq"
        }
    )
    vim.api.nvim_create_user_command(
        "SQLFormat",
        function ()
            vim.cmd("%!sql-formatter -l spark")
        end,
        {
            desc = "format sql file"
        }
    )
    vim.api.nvim_create_user_command(
        "Escape",
        require("escape").escape,
        {
            desc = "escape text"
        }
    )
    vim.api.nvim_create_user_command(
        "UnEscape",
        function (input)
            return vim.fn.execute(string.format("python -c \"print('%s'.encode('utf-8').decode('unicode_escape'))\"",
                input.args))
        end,
        {
            desc = "un escape string "
        }

    )
    vim.api.nvim_create_user_command(
        "Quit",
        function ()
            vim.cmd("qa!")
        end,
        {
            desc = "Quit"
        }

    )
    vim.api.nvim_create_user_command(
        "SSHKeyLoad",
        function ()
            vim.fn.system('eval "$(ssh-agent -s)"')
            print(project_settings.ssh_key)
            vim.fn.system('ssh-add ' .. project_settings.ssh_key)
        end,
        {}
    )
end
M.auto_commands = function (project_settings)
    -- vim.api.nvim_create_autocmd("InsertLeave", {
    --     pattern = "*",
    --     callback = function()
    --         vim.cmd("w")
    --     end
    -- })
    vim.api.nvim_create_autocmd("TermOpen", {
        group = vim.api.nvim_create_augroup("custom_configuration", { clear = true }),
        callback = function ()
            vim.opt.number = false
            vim.opt.relativenumber = false
        end,
    })
    -- vim.api.nvim_create_autocmd({ "BufWritePost" }, {
    --     group = vim.api.nvim_create_augroup("custom_configuration", { clear = true }),
    --     pattern = "*.sql",
    --     callback = function ()
    --         require("lint").try_lint()
    --     end,
    -- })
    -- vim.api.nvim_create_autocmd('FileType', {
    --     group = vim.api.nvim_create_augroup("custom_configuration", { clear = true }),
    --     pattern = "lua,python",
    --     callback = function ()
    --         vim.cmd("AerialOpen! right")
    --     end,
    -- })
    vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup("custom_configuration", { clear = true }),
        pattern = "pom.xml",
        callback = function ()
            vim.cmd("Maven")
        end,
    })
    vim.api.nvim_create_user_command("AppendPy", function ()
        -- Check for Snacks
        local ok, snacks = pcall(require, "snacks")
        if not ok then return vim.notify("Snacks.nvim not found!", vim.log.levels.ERROR) end

        -- Define the custom action to append path and restart LSP
        local function add_pythonpath(picker, item)
            picker:close()
            if not item or not item.file then return end

            local path = item.file

            -- 1. Get current PYTHONPATH
            local current_env = vim.fn.getenv('PYTHONPATH')
            if current_env == vim.NIL then current_env = "" end

            -- 2. Detect OS separator
            local is_windows = vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1
            local sep = is_windows and ';' or ':'

            -- 3. Append new path
            local new_env = (current_env ~= "" and (current_env .. sep) or "") .. path
            vim.fn.setenv('PYTHONPATH', new_env)

            -- 4. Restart LSP
            vim.cmd("LspRestart")

            vim.notify("PYTHONPATH appended & LSP restarted:\n" .. path, vim.log.levels.INFO)
        end

        -- Open the Explorer Picker
        snacks.picker.explorer({
            -- Start at Home Directory
            cwd = vim.fn.expand("~"),

            -- FORCE Floating Layout (Center Window)
            layout = { preset = "default", preview = false },
            exclude = {
                "__pycache__",
                "node_modules",
                ".git",
                ".venv",
                ".mypy_cache",
                ".pytest_cache",
                ".ruff_cache",
                "build",
                "dist",
                "egg-info",
            },

            -- Don't show hidden files (dotfiles) unless toggled
            hidden = false,
            -- Keymaps
            win = {
                input = {
                    keys = {
                        -- Use <C-e> to "Execute" (Add to Path)
                        ["<C-e>"] = { "add_pythonpath", mode = { "i", "n" } },
                    },
                },
                list = {
                    keys = {
                        -- Use <C-e> in the list view too
                        ["<C-e>"] = "add_pythonpath",
                    }
                }
            },

            -- Register the custom action
            actions = {
                add_pythonpath = add_pythonpath
            }
        })
    end, {})
end

M.filetype = function ()
    vim.filetype.add({
        pattern = {
            ['*.jsonc'] = 'json',
        },
    })
end
-- becuase i want to have a name for each folder
M.tmux_rename = function (settings)
    if vim.env.TMUX ~= nil then
        local tmux_command = string.format("tmux rename-window '%s'", settings.name)
        vim.fn.system(tmux_command)
    end
end
return M
