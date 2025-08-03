local M = {}
M.border = function(hl_name)
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

M.lsp_on_attach = function(client, bufnr)
    vim.api.nvim_set_option_value('omnifunc', 'v:lua.vim.lsp.omnifunc', { buf = bufnr })
end
M.contains = function(table, val)
    for i = 1, #table do
        if table[i] == val then
            return true
        end
    end
    return false
end

vim.filetype.add({
  pattern = {
    ['*.jsonc'] = 'json',
  },
})

return M
