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
M.auto_commands = function ()
    -- vim.api.nvim_create_autocmd("InsertLeave", {
    --     pattern = "*",
    --     callback = function()
    --         vim.cmd("w")
    --     end
    -- })
    vim.api.nvim_create_user_command(
        "JsonFormat",
        function ()
            vim.cmd("%!jq")
        end,
        {}
    )
    --vim.api.nvim_create_autocmd('FileType', {
    --    pattern = "lua,python",
    --    callback = function()
    --        vim.cmd("AerialOpen! right")
    --    end,
    --})
    --vim.api.nvim_create_autocmd('FileType', {
    --    pattern = "pom.xml",
    --    callback = function()
    --        vim.cmd("Maven")
    --    end,
    --})
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
