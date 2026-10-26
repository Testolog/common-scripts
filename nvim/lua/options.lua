vim.g.mapleader = " "

vim.opt.encoding = "UTF-8"
vim.opt.guicursor = ""
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.opt.termguicolors = true

vim.opt.nu = true
vim.opt.relativenumber = true

-- Gutter, left to right: git and other signs, the line number, then the fold against the text.
function _G.EditStatuscolumn()
  local win = vim.g.statusline_winid
  local wo = vim.wo[win]
  local show_num = wo.number or wo.relativenumber
  local show_sign = wo.signcolumn ~= "no"
  local fold = tostring(wo.foldcolumn)
  local show_fold = fold ~= "0" and fold ~= "auto:0"
  if not show_num and not show_sign and not show_fold then
    return ""
  end
  local num = ""
  if show_num then
    if wo.relativenumber and (not wo.number or vim.v.relnum ~= 0) then
      num = tostring(vim.v.relnum)
    else
      num = tostring(vim.v.lnum)
    end
    num = "%=" .. num .. " "
  end
  return (show_sign and "%s" or "") .. num .. (show_fold and "%C" or "")
end

vim.o.statuscolumn = "%!v:lua.EditStatuscolumn()"
vim.opt.fillchars:append({ foldopen = "▾", foldclose = "▸", foldsep = " " })

-- Obsidian's extra Markdown syntax only runs at conceallevel 1 or 2. Set it on the
-- window before Obsidian's BufEnter check, including when the filetype is applied
-- while another window is current.
local function markdown_conceal(buf)
  local wins = vim.fn.win_findbuf(buf)
  if #wins == 0 and vim.api.nvim_get_current_buf() == buf then
    vim.wo.conceallevel = 2
    return
  end
  for _, win in ipairs(wins) do
    vim.wo[win].conceallevel = 2
  end
end

local markdown_conceal_group = vim.api.nvim_create_augroup("markdown_conceal", { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  group = markdown_conceal_group,
  pattern = "*.md",
  callback = function (ev)
    markdown_conceal(ev.buf)
  end,
})
vim.api.nvim_create_autocmd("FileType", {
  group = markdown_conceal_group,
  pattern = "markdown",
  callback = function (ev)
    markdown_conceal(ev.buf)
  end,
})

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

vim.opt.smartindent = true
vim.opt.wrap = false
vim.opt.clipboard = "unnamedplus"
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true
vim.g.have_nerd_font = true
vim.opt.guifont = "Nerd Font"
vim.opt.fixeol = false

vim.o.foldcolumn = "1"
vim.o.foldlevel = 99
vim.o.foldlevelstart = 99
vim.o.foldenable = true

vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")
vim.opt.updatetime = 50
vim.opt.completeopt = { "menu", "menuone", "noselect" }

vim.opt.colorcolumn = "80"
vim.g.tmux_navigator_no_mappings = 1
vim.g.tmux_navigator_save_on_switch = 2
vim.g.neovide_input_macos_alt_is_meta = true
