local json = require("util.json")

local M = {}

-- { projects = { { name, root }, ... } } stored beside the template, never copied into projects.
function M.read(path)
  if not vim.uv.fs_stat(path) then
    return { projects = {} }
  end
  local ok, data = pcall(json.read_file, path)
  if not ok or type(data) ~= "table" then
    vim.notify("system_project: cannot read catalog " .. path, vim.log.levels.WARN)
    return { projects = {} }
  end
  data.projects = data.projects or {}
  return data
end

function M.write(path, data)
  return json.write_file(path, data)
end

-- Add `root` to the catalog at `path`. Returns true when it was added.
function M.register(path, root, name)
  local data = M.read(path)
  for _, entry in ipairs(data.projects) do
    if entry.root == root then
      return false
    end
  end
  table.insert(data.projects, { name = name or vim.fs.basename(root), root = root })
  local ok, err = M.write(path, data)
  if not ok then
    vim.notify("system_project: cannot write catalog: " .. tostring(err), vim.log.levels.WARN)
    return false
  end
  return true
end

return M
