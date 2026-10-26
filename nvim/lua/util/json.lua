local M = {}

local function read_file(path)
  local f, err = io.open(path, "rb")
  if not f then
    error(err)
  end
  local s = f:read("*a")
  f:close()
  return s
end

function M.read(path)
  local cjson = require("cjson.safe")
  local obj, err = cjson.decode(read_file(path))
  if not obj then
    error("JSON decode error: " .. tostring(err))
  end
  return obj
end

-- Decode with vim.json so empty objects (vim.empty_dict()) and empty arrays stay distinct.
function M.read_file(path)
  local ok, obj = pcall(vim.json.decode, read_file(path))
  if not ok then
    error("JSON decode error in " .. path .. ": " .. tostring(obj))
  end
  return obj
end

local key_order = {
  "$schema", "name", "lua", "yaml", "json", "ssh_key", "arduino", "project_type",
  "system_prompt", "system_skills", "project_prompt", "project_skills",
  "system_tools", "project_tools", "models", "mcp_servers",
  "projects", "root", "path", "function", "description", "kind", "mutates",
  "vendor", "context_limit", "base_url", "api_key", "isActive",
}
local key_rank = {}
for i, k in ipairs(key_order) do
  key_rank[k] = i
end

-- Keys whose empty value is an object, not an array.
local object_keys = { lua = true, yaml = true, json = true, arduino = true, schemas = true }

local empty_dict_mt = getmetatable(vim.empty_dict())

local function encode_string(s)
  return (vim.json.encode(s):gsub("\\/", "/"))
end

local function sorted_keys(tbl)
  local keys = vim.tbl_keys(tbl)
  table.sort(keys, function (a, b)
    local ra, rb = key_rank[a] or math.huge, key_rank[b] or math.huge
    if ra ~= rb then
      return ra < rb
    end
    return tostring(a) < tostring(b)
  end)
  return keys
end

local function encode(value, indent, key)
  local t = type(value)
  if value == nil or value == vim.NIL then
    return "null"
  elseif t == "string" then
    return encode_string(value)
  elseif t == "number" or t == "boolean" then
    return vim.json.encode(value)
  elseif t ~= "table" then
    error("cannot encode " .. t)
  end
  local pad = string.rep("  ", indent + 1)
  local close = string.rep("  ", indent)
  if next(value) == nil then
    if getmetatable(value) == empty_dict_mt or object_keys[key] then
      return "{}"
    end
    return "[]"
  end
  local parts = {}
  if vim.islist(value) then
    for _, v in ipairs(value) do
      parts[#parts + 1] = pad .. encode(v, indent + 1)
    end
    return "[\n" .. table.concat(parts, ",\n") .. "\n" .. close .. "]"
  end
  for _, k in ipairs(sorted_keys(value)) do
    parts[#parts + 1] = pad .. encode_string(tostring(k)) .. ": " .. encode(value[k], indent + 1, k)
  end
  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. close .. "}"
end

function M.encode_pretty(value)
  return encode(value, 0) .. "\n"
end

-- End index of one JSON value starting at or after `i` (leading space is skipped).
local function value_end(text, i)
  while text:sub(i, i):match("%s") do
    i = i + 1
  end
  local c = text:sub(i, i)
  if c == "" then
    return nil
  end
  if c == "{" or c == "[" then
    local close = c == "{" and "}" or "]"
    local depth, in_str, esc = 0, false, false
    for j = i, #text do
      local ch = text:sub(j, j)
      if in_str then
        if esc then
          esc = false
        elseif ch == "\\" then
          esc = true
        elseif ch == '"' then
          in_str = false
        end
      elseif ch == '"' then
        in_str = true
      elseif ch == c then
        depth = depth + 1
      elseif ch == close then
        depth = depth - 1
        if depth == 0 then
          return j
        end
      end
    end
    return nil
  end
  if c == '"' then
    local esc = false
    for j = i + 1, #text do
      local ch = text:sub(j, j)
      if esc then
        esc = false
      elseif ch == "\\" then
        esc = true
      elseif ch == '"' then
        return j
      end
    end
    return nil
  end
  local j = i
  while j <= #text do
    local ch = text:sub(j, j)
    if ch == "," or ch == "}" or ch == "]" or ch:match("%s") then
      return j - 1
    end
    j = j + 1
  end
  return #text
end

-- Replace the value of top-level-looking `"key":` or insert it before the closing brace.
-- The rest of `text` is left unchanged. Returns the new text, or nil and an error.
function M.replace_key(text, key, encoded)
  local pattern = '"' .. key:gsub("(%W)", "%%%1") .. '"%s*:'
  local _, colon = text:find(pattern)
  if not colon then
    local close_at
    for i = #text, 1, -1 do
      local ch = text:sub(i, i)
      if not ch:match("%s") then
        if ch ~= "}" then
          return nil, "JSON does not end with an object"
        end
        close_at = i
        break
      end
    end
    if not close_at then
      return nil, "JSON does not end with an object"
    end
    local inner = text:sub(1, close_at - 1):gsub("^%s*{", "")
    local comma = inner:match("%S") and "," or ""
    local addition = comma .. '\n  "' .. key .. '": ' .. encoded .. "\n"
    return text:sub(1, close_at - 1) .. addition .. text:sub(close_at)
  end
  local vend = value_end(text, colon + 1)
  if not vend then
    return nil, "could not find the value of " .. key
  end
  return text:sub(1, colon) .. " " .. encoded .. text:sub(vend + 1)
end

-- Write `value` as indented JSON. Returns true, or false and an error message.
function M.write_file(path, value)
  local ok, text = pcall(M.encode_pretty, value)
  if not ok then
    return false, text
  end
  local f, err = io.open(path, "w")
  if not f then
    return false, err
  end
  f:write(text)
  f:close()
  return true
end

return M
