local gitsigns = require("gitsigns")
gitsigns.setup {
    signs                             = {
        add          = { text = '┃' },
        change       = { text = '┃' },
        delete       = { text = '_' },
        topdelete    = { text = '‾' },
        changedelete = { text = '~' },
        untracked    = { text = '┆' },
    },
    signcolumn                        = true,  -- Toggle with `:Gitsigns toggle_signs`
    numhl                             = false, -- Toggle with `:Gitsigns toggle_numhl`
    linehl                            = false, -- Toggle with `:Gitsigns toggle_linehl`
    word_diff                         = false, -- Toggle with `:Gitsigns toggle_word_diff`
    watch_gitdir                      = {
        follow_files = true
    },
    auto_attach                       = true,
    attach_to_untracked               = false,
    current_line_blame                = false, -- Toggle with `:Gitsigns toggle_current_line_blame`
    current_line_blame_opts           = {
        virt_text = true,
        virt_text_pos = 'eol', -- 'eol' | 'overlay' | 'right_align'
        delay = 1000,
        ignore_whitespace = false,
        virt_text_priority = 100,
    },
    current_line_blame_formatter      = '<author>, <author_time:%Y-%m-%d> - <summary>',
    current_line_blame_formatter_opts = {
        relative_time = false,
    },
    sign_priority                     = 6,
    update_debounce                   = 100,
    status_formatter                  = nil,   -- Use default
    max_file_length                   = 40000, -- Disable if file is longer than this (in lines)
    preview_config                    = {
        -- Options passed to nvim_open_win
        border = 'single',
        style = 'minimal',
        relative = 'cursor',
        row = 0,
        col = 1
    },
}
vim.keymap.set("n", "<leader>gsd", gitsigns.diffthis, { desc = "git show difference this" })
vim.keymap.set("n", "<leader>gsc", gitsigns.preview_hunk, { desc = "git show changes with" })
vim.keymap.set("n", "<leader>ghs", gitsigns.stage_hunk, { desc = "git stage hunk" })
vim.keymap.set("n", "<leader>ghr", gitsigns.reset_hunk, { desc = "git resut hunk" })
vim.keymap.set("n", "<leader>tgb", gitsigns.toggle_current_line_blame, { desc = "toggle git current line blame" })
vim.keymap.set("n", "<leader>gl", vim.cmd.LazyGit, { desc = "git lazy" })
