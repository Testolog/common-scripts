-- Standard tab locked to $COMMON_SCRIPT/system_project. Reuses the Standard package; registers no plugins.
local standard = require("tabs.standard")
local system_project = require("system_project")

local M = setmetatable({}, { __index = standard })

M.mode = "system_standard"

function M.root(_)
  return system_project.ensure()
end

function M.vault(_)
  return system_project.common_script()
end

return M
