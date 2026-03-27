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
    { "<leader>cf", ":'<,'>FormatSelection<CR>", mode = "v", desc = "format selection (JSON/YAML/SQL/Python)" },
}

local function ivy_picker_layout(fun)
    local setup = { layout = { preset = "ivy" } }
    return function ()
        fun(setup)
    end
end

local function smart_picker_layout(fun)
    local setup = {
        layout = {
            reverse = false,
            layout = {
                box = "horizontal",
                backdrop = false,
                width = 0.8,
                height = 0.9,
                border = "none",
                {
                    box = "vertical",
                    { win = "input", height = 1, border = "rounded", title = "{title} {live} {flags}", title_pos = "center" },
                    { win = "list", title = " Results ", title_pos = "center", border = "rounded" },
                },
                {
                    win = "preview",
                    title = "{preview:Preview}",
                    width = 0.45,
                    border = "rounded",
                    title_pos = "center",
                },
            },
        },
    }
    return function ()
        fun(setup)
    end
end

local leader_map = {
    { "gs", ":w | source %<CR>", mode = "n", desc = "save source" },
    { "?", ivy_picker_layout(snacks.picker.help), mode = "n", desc = "Help" },
    { "<space><space>", snacks.picker.smart, desc = "Smart Find Files" },
    { "<leader>fk", ivy_picker_layout(snacks.picker.keymaps), mode = "n", desc = "FindKey" },
    { "<leader>ff", smart_picker_layout(snacks.picker.files), mode = "n", desc = "find files" },
    { "<leader>fg", smart_picker_layout(snacks.picker.git_files), mode = "n", desc = "find in git files" },
    { "<leader>fb", smart_picker_layout(snacks.picker.buffers), mode = "n", desc = "find in buffer" },
    { "<leader>fc", smart_picker_layout(snacks.picker.commands), mode = "n", desc = "find in commands" },
    { "<leader>fs", smart_picker_layout(snacks.picker.grep), mode = "n", desc = "find live grep" },
    { "gld", ivy_picker_layout(snacks.picker.lsp_definitions), desc = "Goto Definition" },
    { "glD", ivy_picker_layout(snacks.picker.lsp_declarations), desc = "Goto Declaration" },
    { "glr", ivy_picker_layout(snacks.picker.lsp_references), nowait = true, desc = "References" },
    { "glI", ivy_picker_layout(snacks.picker.lsp_implementations), desc = "Goto Implementation" },
    { "glt", ivy_picker_layout(snacks.picker.lsp_type_definitions), desc = "Goto T[y]pe Definition" },
    { "gls", vim.lsp.buf.hover, desc = "display signature" },
    { "<leader>gt", gitsigns.diffthis, mode = "n", desc = "git show difference this" },
    { "<leader>ggc", gitsigns.preview_hunk, mode = "n", desc = "git show changes with" },
    { "<leader>ggs", gitsigns.stage_hunk, mode = "n", desc = "git stage hunk" },
    { "<leader>ggr", gitsigns.reset_hunk, mode = "n", desc = "git resut hunk" },
    { "<leader>gl", vim.cmd.LazyGit, mode = "n", desc = "git lazy" },
    { "<leader>tb", gitsigns.toggle_current_line_blame, mode = "n", desc = "toggle git current line blame" },
    { "<leader>ts", function () vim.cmd.AerialToggle("right") end, mode = "n", desc = "toggle current structure" },
    { "<leader>tu", vim.cmd.UndotreeToggle, mode = "n", desc = "toggle undo tree" },
    { "<leader>tt", vim.cmd.NvimTreeToggle, mode = "n", desc = "toggle nvim tree" },
    {
        "<leader>te",
        function ()
            trouble.toggle({
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
            })
        end,
        mode = "n",
        desc = "toggle trouble",
    },
    { "<leader>tm", function () vim.cmd.Maven() end, mode = "n", desc = "Maven" },
    { "<leader>tq", function () require("quicker").toggle({ loclist = true }) end, desc = "Toggle quickfix" },
    {
        "<leader>tz",
        function ()
            require("zen-mode").toggle({ window = { width = 0.55 } })
        end,
        desc = "Toggle Zen Mode",
    },
    { "<leader>a", function () harpoon:list():add() end, mode = "n", desc = "append to harpoon" },
    { "<leader>e", function () harpoon.ui:toggle_quick_menu(harpoon:list()) end, mode = "n", desc = "list tabs" },
    { "<leader>si", vim.lsp.buf.hover, mode = "n", desc = "show hover information" },
    { "<leader>sI", function (opts) vim.lsp.buf.implementation(opts) end, mode = "n", desc = "show all implementations" },
    { "<leader>sar", vim.lsp.buf.references, mode = "n", desc = "show all references" },
    {
        "<leader>slf",
        function ()
            ntree.tree.find_file({ open = true, focus = true })
        end,
        mode = "n",
        desc = "show location of file",
    },
    {
        "<leader>sdm",
        function (cfg)
            return vim.diagnostic.open_float(cfg, { focus = true, scope = "cursor" })
        end,
        mode = "n",
        desc = "show diagnostics message",
    },
    { "<leader>sl", vim.cmd.NERDTreeFind, mode = "n", desc = "locate file in tree" },
    { "<leader>ls", vim.lsp.buf.signature_help, mode = "n", desc = "show signature" },
    { "<leader>lr", vim.lsp.buf.rename, mode = "n", desc = "rename" },
    { "<leader>lf", function () vim.lsp.buf.format({ async = true }) end, mode = "n", desc = "formatting" },
    { "<leader>la", function (opts) require("tiny-code-action").code_action(opts) end, mode = "n", desc = "actions" },
    { "zR", require("ufo").openAllFolds, mode = "n", desc = "open all folds" },
    { "zM", require("ufo").closeAllFolds, mode = "n", desc = "close all folds" },
    { "<leader>we", "<C-W>w", mode = "n", desc = "next window" },
    { "<leader>wr", "<C-W>W", mode = "n", desc = "prev window" },
    { "<leader>qs", function() require("persistence").load() end, desc = "Restore session for cwd" },
    { "<leader>ql", function() require("persistence").load({ last = true }) end, desc = "Restore last session" },
    { "<leader>qd", function() require("persistence").stop() end, desc = "Don't save current session" },
    -- Arduino / ESP32
    { "<leader>ac", "<cmd>ArduinoCompile<CR>", mode = "n", desc = "Arduino compile" },
    { "<leader>au", "<cmd>ArduinoUpload<CR>", mode = "n", desc = "Arduino upload (auto-detect ESP32)" },
    { "<leader>am", "<cmd>ArduinoMonitor<CR>", mode = "n", desc = "Arduino serial monitor" },
    { "<leader>ar", "<cmd>ArduinoUploadAndMonitor<CR>", mode = "n", desc = "Arduino upload + monitor" },
    { "<leader>ap", "<cmd>ArduinoPort<CR>", mode = "n", desc = "Arduino pick USB port" },
    { "<leader>at", "<cmd>ArduinoChip<CR>", mode = "n", desc = "Arduino set chip (ESP32/C3/S2/S3)" },
    { "<leader>as", "<cmd>ArduinoMonitorStop<CR>", mode = "n", desc = "Arduino stop serial monitor" },
    { "<leader>al", "<cmd>ArduinoLibInstall<CR>", mode = "n", desc = "Arduino install library" },
    { "<leader>a/", "<cmd>ArduinoLibSearch<CR>", mode = "n", desc = "Arduino search libraries" },
    { "<leader>aA", "<cmd>ArduinoLibAdd<CR>", mode = "n", desc = "Arduino add lib to project" },
    { "<leader>rr", "<cmd>CRun<CR>", mode = "n", desc = "Run C/C++ file" },
    -- { "<leader>tte", "<cmd>ErrorLogToggle<CR>", mode = "n", desc = "Toggle error log tab" },
    -- ESP-IDF (idf.py) C/C++
    { "<leader>ip", "<cmd>IDFPort<CR>", mode = "n", desc = "IDF pick device port" },
    { "<leader>ib", "<cmd>IDFBuild<CR>", mode = "n", desc = "IDF build" },
    { "<leader>if", "<cmd>IDFFlash<CR>", mode = "n", desc = "IDF flash to ESP32" },
    { "<leader>im", "<cmd>IDFMonitor<CR>", mode = "n", desc = "IDF serial monitor" },
    { "<leader>ir", "<cmd>IDFFlashAndMonitor<CR>", mode = "n", desc = "IDF flash + monitor" },
    { "<leader>is", "<cmd>IDFMonitorStop<CR>", mode = "n", desc = "IDF stop monitor" },
}

which_key.add(leader_map)
which_key.add(not_leader_map)
which_key.add(v_map)
