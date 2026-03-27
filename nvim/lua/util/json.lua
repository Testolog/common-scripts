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

return M
