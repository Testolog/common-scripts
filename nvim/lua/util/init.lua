local table_util = require("util.table")
local json_util = require("util.json")
local ui_util = require("util.ui")

local M = {}

M.contains = table_util.contains
M.merge_table = table_util.merge
M.tprint = table_util.tprint
M.read_json = json_util.read
M.border = ui_util.border
M.lsp_on_attach = ui_util.lsp_on_attach

function M.start_mode()
  if vim.fn.argc() == 0 then
    return 0
  end
  local arg0 = vim.fn.fnamemodify(vim.fn.argv(0), ":p")
  if vim.fn.isdirectory(arg0) == 1 then
    return 1
  end
  return 2
end

return M
