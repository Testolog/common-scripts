vim.api.nvim_create_autocmd('FileType', {
    pattern = "lua,python",
    callback = function()
        vim.cmd("AerialOpen! right")
    end,
})
