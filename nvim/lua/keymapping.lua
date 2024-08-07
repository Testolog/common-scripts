local builtin = require("telescope.builtin")
local gitsigns = require("gitsigns")
local which_key = require("which-key")
local harpoon = require("harpoon")
local trouble = require("trouble")
local function grep()
    builtin.grep_string({ search = vim.fn.input("Find: ") });
end
local leader_ops = {
    mode = "n",
    prefix = "<leader>",
    silent = true,  -- use `silent` when creating keymaps
    noremap = true, -- use `noremap` when creating keymaps
    nowait = false, -- use `nowait` when creating keymaps
    expr = false,   -- use `expr` when creating keymaps
}
local not_leader_osp = {
    mode = "n",
    silent = true,  -- use `silent` when creating keymaps
    noremap = true, -- use `noremap` when creating keymaps
    nowait = false, -- use `nowait` when creating keymaps
    expr = false,   -- use `expr` when creating keymaps
}
local v_ops = {
    mode = "v",
    silent = true,  -- use `silent` when creating keymaps
    noremap = true, -- use `noremap` when creating keymaps
    nowait = false, -- use `nowait` when creating keymaps
    expr = false,   -- use `expr` when creating keymaps
}
--['<leader>sdp', vim.lsp.diagnostic.goto_prev, "prev diagnostics", },
--['<leader>sdn', vim.lsp.diagnostic.goto_next, "next diagnostics", },
--['<leader>lwa', vim.lsp.buf.code_action, "code actions", },
--vim.keymap.set('v', '<leader>lwr', vim.lsp.buf.range_code_action, "range code actions", },
local not_leader_map = {
    ["<C-h>"] = { "<cmd><TmuxNavigateLeft<cr>", "tmux move left" },
    ["<C-j>"] = { "<cmd>TmuxNavigateDown<cr>", "tmux move down" },
    ["<C-k>"] = { "<cmd>TmuxNavigкateUp<cr>", "tmux move up" },
    ["<C-l>"] = { "<cmd>TmuxNavigateRight<cr>", "tmux move right" },
}
local v_map = {
    ["<C-S-DOWN>"] = { ":m '>+1<CR>gv=gv", "move selected line down" },
    ["<C-S-UP>"] = { ":m '<-2<CR>gv=gv", "move selected line up" }
}
local leader_map = {
    f = {
        f = { builtin.find_files, "find files" },
        g = { builtin.git_files, "find in git files" },
        b = { builtin.buffers, "find in buffer" },
        t = { builtin.help_tags, "find in tags" },
        s = { grep, "find by grep" },
    },
    g = {
        t = { gitsigns.diffthis, "git show difference this" },
        d = { vim.lsp.buf.definition, "Go to definition", },
        D = { vim.lsp.buf.declaration, "Go to declaration", },
        s = { vim.lsp.buf.type_definition, "Go to definition symbol", },
        gc = { gitsigns.preview_hunk, "git show changes with" },
        gs = { gitsigns.stage_hunk, "git stage hunk" },
        gr = { gitsigns.reset_hunk, "git resut hunk" },
        l = { vim.cmd.LazyGit, "git lazy" }
    },
    t = {
        b = { gitsigns.toggle_current_line_blame, "toggle git current line blame" },
        s = { function() vim.cmd.AerialToggle("right") end, "toggle current structure" },
        u = { vim.cmd.UndotreeToggle, "toggle undo tree" },
        t = { vim.cmd.NvimTreeToggle, "toggle nvim tree" },
        e = { function()
            local t_opts = {
                mode = "diagnostics",
                win = {
                    type = "split",
                    relative = "editor",
                    border = "rounded",
                    title = "Preview",
                    title_pos = "center",
                    position = "right",
                    size = { width = 0.3, height = 0.3 },
                    zindex = 200,
                },
            }
            trouble.toggle(t_opts)
        end, "toggle trouble" }
    },
    a = { function() harpoon:list():add() end, "append to harpoon" },
    e = { function() harpoon.ui:toggle_quick_menu(harpoon:list()) end, "list tabs" },
    s = {
        i = { vim.lsp.buf.hover, "show hover information", },
        I = { vim.lsp.buf.implementation, "show all implementations", },
        ar = { vim.lsp.buf.references, "show all references", },
        dm = { function(cfg) return vim.diagnostic.open_float(cfg, { focus = true, scope = "cursor" }) end, "show diagnostics message", },
    },
    l = {
        s = { vim.lsp.buf.signature_help, "show signature", },
        r = { vim.lsp.buf.rename, "rename", },
        f = { function() vim.lsp.buf.format { async = true } end, "formatting", },
    },
}
which_key.register(leader_map, leader_ops)
which_key.register(not_leader_map, not_leader_osp)
which_key.register(v_map, v_ops)
