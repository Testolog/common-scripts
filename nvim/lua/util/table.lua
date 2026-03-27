local M = {}

function M.contains(tbl, val)
  for i = 1, #tbl do
    if tbl[i] == val then
      return true
    end
  end
  return false
end

function M.merge(base, overlay)
  if base == nil then return overlay end
  if overlay == nil then return base end
  local result = {}
  for k, v in pairs(base) do
    result[k] = v
  end
  for k, v in pairs(overlay) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = M.merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

function M.tprint(tbl, indent)
  if tbl == nil then
    return "nil"
  end
  indent = indent or 0
  local lines = { string.rep(" ", indent) .. "{" }
  indent = indent + 2
  for k, v in pairs(tbl) do
    local key = type(k) == "number" and ("[" .. k .. "]") or k
    local val
    if type(v) == "number" then
      val = tostring(v)
    elseif type(v) == "string" then
      val = '"' .. v .. '"'
    elseif type(v) == "table" then
      val = M.tprint(v, indent)
    else
      val = '"' .. tostring(v) .. '"'
    end
    table.insert(lines, string.rep(" ", indent) .. key .. " = " .. val .. ",")
  end
  table.insert(lines, string.rep(" ", indent - 2) .. "}")
  return table.concat(lines, "\n")
end

return M
