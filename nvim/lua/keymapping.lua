local gitsigns = require("gitsigns")
local which_key = require("which-key")
local harpoon = require("harpoon")
local trouble = require("trouble")
local ntree = require("nvim-tree.api")
local snacks = require("snacks")

local not_leader_map = {
    { "<C-h>", vim.cmd.TmuxNavigateLeft, desc = "tmux move left", expr = false, nowait = false, remap = false },
    { "<C-j>", vim.cmd.TmuxNavigateDown, desc = "tmux move down", expr = false, nowait = false, remap = false },
    { "<C-k>", vim.cmd.TmuxNavigateUp, desc = "tmux move up", expr = false, nowait = false, remap = false },
    { "<C-l>", vim.cmd.TmuxNavigateRight, desc = "tmux move right", expr = false, nowait = false, remap = false },
}

local v_map = {
    { "<C-S-DOWN>", ":m '>+1<CR>gv=gv", desc = "move selected line down", expr = false, mode = "v", nowait = false, remap = false },
    { "<C-S-UP>", ":m '<-2<CR>gv=gv", desc = "move selected line up", expr = false, mode = "v", nowait = false, remap = false },
}
local function ivy_picker_layout(fun)
    local setup = {
        layout = {
            preset = "ivy"
        }
    }
    return function ()
        fun(setup)
    end
end
local leader_map = {
    { "gs", ":w | source %<CR>", mode = "n", desc = "save source" },
    --other
    { "?", ivy_picker_layout(snacks.picker.help), mode = "n", desc = "Help" },
    { "<space><space>", snacks.picker.smart, desc = "Smart Find Files" },
    { "<leader>fk", ivy_picker_layout(snacks.picker.keymaps), mode = "n", desc = "FindKey" },
    -- f find
    { "<leader>ff", ivy_picker_layout(snacks.picker.files), mode = "n", desc = "find files" },
    { "<leader>fg", ivy_picker_layout(snacks.picker.git_files), mode = "n", desc = "find in git files" },
    { "<leader>fb", ivy_picker_layout(snacks.picker.buffers), mode = "n", desc = "find in buffer" },
    { "<leader>fc", ivy_picker_layout(snacks.picker.commands), mode = "n", desc = "find in commands" },
    { "<leader>fs", ivy_picker_layout(snacks.picker.grep), mode = "n", desc = "find live grep" },
    -- g go/git
    { "gld", ivy_picker_layout(snacks.picker.lsp_definitions), desc = "Goto Definition" },
    { "glD", ivy_picker_layout(snacks.picker.lsp_declarations), desc = "Goto Declaration" },
    { "glr", ivy_picker_layout(snacks.picker.lsp_references), nowait = true, desc = "References" },
    { "glI", ivy_picker_layout(snacks.picker.lsp_implementations), desc = "Goto Implementation" },
    { "glt", ivy_picker_layout(snacks.picker.lsp_type_definitions), desc = "Goto T[y]pe Definition" },
    { "<leader>gt", gitsigns.diffthis, mode = "n", desc = "git show difference this" },
    { "<leader>ggc", gitsigns.preview_hunk, mode = "n", desc = "git show changes with" },
    { "<leader>ggs", gitsigns.stage_hunk, mode = "n", desc = "git stage hunk" },
    { "<leader>ggr", gitsigns.reset_hunk, mode = "n", desc = "git resut hunk" },
    { "<leader>gl", vim.cmd.LazyGit, mode = "n", desc = "git lazy" },
    -- t toogle window
    { "<leader>tb", gitsigns.toggle_current_line_blame, mode = "n", desc = "toggle git current line blame" },
    { "<leader>ts", function () vim.cmd.AerialToggle("right") end, mode = "n", desc = "toggle current structure" },
    { "<leader>tu", vim.cmd.UndotreeToggle, mode = "n", desc = "toggle undo tree" },
    { "<leader>tt", vim.cmd.NvimTreeToggle, mode = "n", desc = "toggle nvim tree" },
    -- { "<leader>tq", vim.}
    {
        "<leader>te",
        function ()
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
        function ()
            vim.cmd.Maven()
        end,
        mode = "n",
        desc = "Maven"
    },
    {
        "<leader>tq",
        function ()
            require("quicker").toggle({ loclist = true })
        end,
        desc = "Toggle quickfix",
    },
    -- harpoon
    {
        "<leader>a",
        function ()
            harpoon:list():add()
        end,
        mode = "n",
        desc = "append to harpoon"
    },
    {
        "<leader>e",
        function ()
            harpoon.ui:toggle_quick_menu(harpoon:list())
        end,
        mode = "n",
        desc = "list tabs"
    }, -- s show
    { "<leader>si", vim.lsp.buf.hover, mode = "n", desc = "show hover information" },
    {
        "<leader>sI",
        function (opts)
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
        function ()
            ntree.tree.find_file({ open = true, focus = true, })
        end,
        mode = "n",
        desc = "show location of file"
    },
    {
        "<leader>sdm",
        function (cfg)
            return vim.diagnostic.open_float(cfg, { focus = true, scope = "cursor" })
        end,
        mode = "n",
        desc = "show diagnostics message"
    },
    { "<leader>sl", vim.cmd.NERDTreeFind, mode = "n", desc = "locate file in tree" },
    -- l LSP
    { "<leader>ls", vim.lsp.buf.signature_help, mode = "n", desc = "show signature" },
    { "<leader>lr", vim.lsp.buf.rename, mode = "n", desc = "rename" },
    {
        "<leader>lf",
        function () vim.lsp.buf.format { async = true } end,
        mode = "n",
        desc = "formatting"
    },
    {
        "<leader>la",
        function (opts)
            require("tiny-code-action").code_action(opts)
        end,
        mode = "n",
        desc = "actions"
    },
    -- z
    { "zR", require("ufo").openAllFolds, mode = "n", desc = "open all folds" },
    { "zM", require("ufo").closeAllFolds, mode = "n", desc = "close all folds" },
    --esp :tnoremap <Esc> <C-\><C-n>
}
which_key.add(leader_map)
which_key.add(not_leader_map)
which_key.add(v_map)
