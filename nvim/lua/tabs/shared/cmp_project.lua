local M = {}

local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:get_trigger_characters()
  return { "$", "." }
end

function source:get_keyword_pattern()
  return [[\$\?[A-Za-z_][A-Za-z0-9_.]*]]
end

local function project_keys(tbl, prefix, out)
  if type(tbl) ~= "table" or vim.islist(tbl) then
    return out
  end
  for key, value in pairs(tbl) do
    if type(key) == "string" and key ~= "root" then
      local path = prefix and (prefix .. "." .. key) or key
      out[#out + 1] = { path = path, value = value }
      project_keys(value, path, out)
    end
  end
  return out
end

function source:complete(params, callback)
  local cmp = require("cmp")
  local before = params.context.cursor_before_line
  local items = {}
  if before:match("%$[%w_]*$") then
    for name, value in pairs(vim.fn.environ()) do
      items[#items + 1] = {
        label = "$" .. name,
        insertText = "$" .. name,
        kind = cmp.lsp.CompletionItemKind.Variable,
        documentation = value,
      }
    end
  else
    local project = require("tabs.runtime").project() or {}
    for _, entry in ipairs(project_keys(project, nil, {})) do
      local doc = type(entry.value) == "table" and vim.inspect(entry.value) or tostring(entry.value)
      items[#items + 1] = {
        label = entry.path,
        kind = cmp.lsp.CompletionItemKind.Property,
        documentation = doc,
      }
    end
  end
  callback({ items = items, isIncomplete = false })
end

function M.register()
  local ok, cmp = pcall(require, "cmp")
  if ok and not M.registered then
    cmp.register_source("nvim_project", source.new())
    M.registered = true
  end
end

return M
