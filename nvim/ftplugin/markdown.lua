-- Markdown specific settings
vim.opt.wrap = true -- Wrap text
vim.opt.breakindent = true -- Match indent on line break
vim.opt.linebreak = true -- Line break on whole words

-- Allow j/k when navigating wrapped lines
vim.keymap.set("n", "j", "gj")
vim.keymap.set("n", "k", "gk")

-- Spell check
vim.opt.spelllang = 'en_us'
vim.opt.spell = true

-- obsidian.nvim renders links, checkboxes and embeds through conceal (level 1 or 2).
local markdown_buf = vim.api.nvim_get_current_buf()
local markdown_wins = vim.fn.win_findbuf(markdown_buf)
if #markdown_wins == 0 then
  vim.opt_local.conceallevel = 2
else
  for _, win in ipairs(markdown_wins) do
    vim.wo[win].conceallevel = 2
  end
end
