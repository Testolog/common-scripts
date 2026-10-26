local M = {}

function M.vault()
  local ok, runtime = pcall(require, "tabs.runtime")
  local vault = ok and runtime.vault() or nil
  return vault or vim.fn.getcwd()
end

-- Point obsidian.nvim at the current tab's vault. No-op until the plugin has been loaded.
function M.sync()
  if not package.loaded["obsidian"] or type(_G.Obsidian) ~= "table" or not Obsidian.workspaces then
    return
  end
  local ok, err = pcall(function ()
    local Workspace = require("obsidian.workspace")
    local vault = vim.fs.normalize(M.vault())
    local target
    for _, ws in ipairs(Obsidian.workspaces) do
      if vim.fs.normalize(tostring(ws.path)) == vault then
        target = ws
        break
      end
    end
    if not target then
      target = Workspace.new({ name = vault, path = vault, strict = true })
      if not target then
        return
      end
      table.insert(Obsidian.workspaces, target)
    end
    if Obsidian.workspace ~= target then
      Workspace.set(target)
    end
  end)
  if not ok then
    vim.notify("obsidian.nvim: could not switch vault: " .. tostring(err), vim.log.levels.WARN)
  end
end

return M
