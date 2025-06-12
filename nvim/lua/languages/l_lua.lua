local lspconfig = require("lspconfig")
local lazydev   = require("lazydev")
local config    = require("lazy.core.config")
lspconfig.lua_ls.setup {
    on_init = function(client)
        if client.workspace_folders then
            local path = client.workspace_folders[1].name
            if vim.loop.fs_stat(path .. '/.luarc.json') or vim.loop.fs_stat(path .. '/.luarc.jsonc') then
                return
            end
        end
    end,
    settings = {
        Lua = {}
    }
}
lazydev.setup({
    enabled = true,
    config = {
        library = {
            "lazy.nvim",
            vim.env.VIMRUNTIME
        }
    }
})
