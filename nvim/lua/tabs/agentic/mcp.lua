-- Turn one MCP server on or off in this tab's .nvim_project.json.
-- Only the mcp_servers array is rewritten. Connection urls stay in ~/.cursor/mcp.json.
local json = require("util.json")

local M = {}

local function encode_servers(servers)
  if #servers == 0 then
    return "[]"
  end
  local lines = {}
  for _, item in ipairs(servers) do
    lines[#lines + 1] = string.format(
      '    { "name": %s, "isActive": %s }',
      vim.json.encode(tostring(item.name)),
      item.isActive == true and "true" or "false"
    )
  end
  return "[\n" .. table.concat(lines, ",\n") .. "\n  ]"
end

local function read_text(path)
  local f, err = io.open(path, "rb")
  if not f then
    return nil, err
  end
  local text = f:read("*a")
  f:close()
  return text
end

-- Set `name` to `active` in the project file. Returns true, or false and an error.
function M.set_active(path, name, active)
  local text, err = read_text(path)
  if not text then
    return false, err
  end
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" then
    return false, "cannot read " .. path .. ": " .. tostring(data)
  end
  local servers, found = {}, false
  if type(data.mcp_servers) == "table" and vim.islist(data.mcp_servers) then
    for _, item in ipairs(data.mcp_servers) do
      if type(item) == "table" and item.name then
        local on = item.name == name and active == true or item.name ~= name and item.isActive == true
        servers[#servers + 1] = { name = item.name, isActive = on }
        found = found or item.name == name
      end
    end
  end
  if not found then
    servers[#servers + 1] = { name = name, isActive = active == true }
  end
  local encoded = encode_servers(servers)
  local next_text, replace_err = json.replace_key(text, "mcp_servers", encoded)
  if not next_text then
    return false, replace_err
  end
  local f, open_err = io.open(path, "w")
  if not f then
    return false, open_err
  end
  f:write(next_text)
  f:close()
  return true
end

return M
