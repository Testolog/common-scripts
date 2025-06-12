local builtin = require("telescope.builtin")
local gitsigns = require("gitsigns")
local which_key = require("which-key")
local harpoon = require("harpoon")
local trouble = require("trouble")
local cmp = require("cmp")
local ntree = require("nvim-tree.api")

local not_leader_map = {
    { "<C-h>", vim.cmd.TmuxNavigateLeft,  desc = "tmux move left",  expr = false, nowait = false, remap = false },
    { "<C-j>", vim.cmd.TmuxNavigateDown,  desc = "tmux move down",  expr = false, nowait = false, remap = false },
    { "<C-k>", vim.cmd.TmuxNavigateUp,    desc = "tmux move up",    expr = false, nowait = false, remap = false },
    { "<C-l>", vim.cmd.TmuxNavigateRight, desc = "tmux move right", expr = false, nowait = false, remap = false },
}

local v_map = {
    { "<C-S-DOWN>", ":m '>+1<CR>gv=gv", desc = "move selected line down", expr = false, mode = "v", nowait = false, remap = false },
    { "<C-S-UP>",   ":m '<-2<CR>gv=gv", desc = "move selected line up",   expr = false, mode = "v", nowait = false, remap = false },
}

local leader_map = {
    -- f find
    { "<leader>ff",  builtin.find_files,                           mode = "n", desc = "find files" },
    { "<leader>fg",  builtin.git_files,                            mode = "n", desc = "find in git files" },
    { "<leader>fb",  builtin.buffers,                              mode = "n", desc = "find in buffer" },
    { "<leader>ft",  builtin.help_tags,                            mode = "n", desc = "find in tags" },
    --{ "<leader>fs",  grep,                                         mode = "n", desc = "find by grep" },
    { "<leader>fs",  builtin.live_grep,                            mode = "n", desc = "find live grep" },
    -- g go/git
    { "<leader>gt",  gitsigns.diffthis,                            mode = "n", desc = "git show difference this" },
    { "<leader>gd",  vim.lsp.buf.definition,                       mode = "n", desc = "Go to definition" },
    { "<leader>gD",  vim.lsp.buf.declaration,                      mode = "n", desc = "Go to declaration" },
    { "<leader>gs",  vim.lsp.buf.type_definition,                  mode = "n", desc = "Go to definition symbol" },
    { "<leader>ggc", gitsigns.preview_hunk,                        mode = "n", desc = "git show changes with" },
    { "<leader>ggs", gitsigns.stage_hunk,                          mode = "n", desc = "git stage hunk" },
    { "<leader>ggr", gitsigns.reset_hunk,                          mode = "n", desc = "git resut hunk" },
    { "<leader>gl",  vim.cmd.LazyGit,                              mode = "n", desc = "git lazy" },
    -- t toogle window
    { "<leader>tb",  gitsigns.toggle_current_line_blame,           mode = "n", desc = "toggle git current line blame" },
    { "<leader>ts",  function() vim.cmd.AerialToggle("right") end, mode = "n", desc = "toggle current structure" },
    { "<leader>tu",  vim.cmd.UndotreeToggle,                       mode = "n", desc = "toggle undo tree" },
    { "<leader>tt",  vim.cmd.NvimTreeToggle,                       mode = "n", desc = "toggle nvim tree" },
    {
        "<leader>te",
        function()
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
        end,
        mode = "n",
        desc = "toggle trouble"
    },
    {
        "<leader>tm",
        function()
            vim.cmd.Maven()
        end,
        mode = "n",
        desc = "Maven"
    },
    -- harpoon
    {
        "<leader>a",
        function()
            harpoon:list():add()
        end,
        mode = "n",
        desc = "append to harpoon"
    },
    {
        "<leader>e",
        function()
            harpoon.ui:toggle_quick_menu(harpoon:list())
        end,
        mode = "n",
        desc = "list tabs"
    }, -- s show
    { "<leader>si", vim.lsp.buf.hover,          mode = "n", desc = "show hover information" },
    {
        "<leader>sI",
        function(opts)
            print("asd")
            vim.lsp.buf.implementation(opts)
        end,
        mode = "n",
        desc = "show all implementations"
    },
    {
        "<leader>sar",
        vim.lsp.buf.references,
        mode = "n",
        desc = "show all references"
    },
    {
        "<leader>slf",
        function()
            ntree.tree.find_file({ open = true, focus = true, })
        end,
        mode = "n",
        desc = "show location of file"
    },
    {
        "<leader>sdm",
        function(cfg)
            return vim.diagnostic.open_float(cfg, { focus = true, scope = "cursor" })
        end,
        mode = "n",
        desc = "show diagnostics message"
    },
    { "<leader>sl", vim.cmd.NERDTreeFind,       mode = "n", desc = "locate file in tree" },
    -- l LSP
    { "<leader>ls", vim.lsp.buf.signature_help, mode = "n", desc = "show signature" },
    { "<leader>lr", vim.lsp.buf.rename,         mode = "n", desc = "rename" },
    {
        "<leader>lf",
        function()
            vim.lsp.buf.format { async = true }
        end,
        mode = "n",
        desc = "formatting"
    },
    {
        "<leader>la",
        function(opts)
            require("tiny-code-action").code_action(opts)
        end,
        mode = "n",
        desc = "actions"
    },
}
which_key.add(leader_map)
which_key.add(not_leader_map)
which_key.add(v_map)
