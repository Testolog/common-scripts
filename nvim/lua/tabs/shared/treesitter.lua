-- nvim-treesitter `main` only installs parsers and queries; highlighting is Neovim's vim.treesitter.start().
-- Mirrors the old master config: ensure_installed + auto_install + highlight for every filetype.
local M = {}

local available

local function start(buf, lang)
  return pcall(vim.treesitter.start, buf, lang)
end

local function installable(ts, lang)
  available = available or ts.get_available()
  return vim.list_contains(available, lang)
end

function M.setup(ensure_installed)
  local ts = require("nvim-treesitter")
  ts.setup({})
  ts.install(ensure_installed)

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("shared_treesitter", { clear = true }),
    callback = function (args)
      local buf = args.buf
      if vim.bo[buf].buftype ~= "" and vim.bo[buf].buftype ~= "help" then
        return
      end
      local lang = vim.treesitter.language.get_lang(args.match) or args.match
      if start(buf, lang) or not installable(ts, lang) then
        return
      end
      ts.install({ lang }):await(function (err)
        if err then
          return
        end
        vim.schedule(function ()
          if vim.api.nvim_buf_is_valid(buf) then
            start(buf, lang)
          end
        end)
      end)
    end,
  })
end

return M
