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
vim.api.nvim_create_autocmd("InsertLeave", {
    pattern = "*",
    callback = function()
        vim.cmd("w")
    end
})
vim.api.nvim_create_user_command(
    "JsonFormat",
    function()
        vim.cmd("%!jq")
    end,
    {}
)
