-- Agentic tab locked to $COMMON_SCRIPT/system_project. Reuses the Agentic package; registers no plugins.
local agentic = require("tabs.agentic")
local system_project = require("system_project")

local M = setmetatable({}, { __index = agentic })

M.mode = "system_agentic"

function M.root(_)
  return system_project.ensure()
end

function M.vault(_)
  return system_project.common_script()
end

return M
