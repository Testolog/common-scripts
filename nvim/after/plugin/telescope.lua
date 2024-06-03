local builtin = require('telescope.builtin')

require('telescope').setup({
    defaults = {
        layout_config = {
            vertical = { width = 0.5 }
        },
    },
})
local function grep()
    builtin.grep_string({ search = vim.fn.input("Find: ") });
end
vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = "find files" })
vim.keymap.set('n', '<leader>fg', builtin.git_files, { desc = "find in git files" })
vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = "find in buffer" })
vim.keymap.set('n', '<leader>ft', builtin.help_tags, { desc = "find in tags" })
vim.keymap.set('n', '<leader>fs', grep, { desc = "find by grep" })

