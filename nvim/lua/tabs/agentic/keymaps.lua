-- which-key style specs for the Agentic tab. tabs.runtime installs them on TabEnter and removes them on TabLeave.
-- The named functions install buffer-local maps on the tree, read, and write buffers.
local function cmd(name)
  return function ()
    vim.cmd(name)
  end
end

local M = {
  { "<leader>at", cmd("AgentTree"), desc = "agentic: toggle tree" },
  { "<leader>ac", cmd("AgentCreate"), desc = "agentic: create agent" },
  { "<leader>aS", cmd("AgentStart"), desc = "agentic: start an existing agent" },
  { "<leader>as", cmd("AgentStop"), desc = "agentic: stop agent" },
  { "<leader>aK", cmd("AgentKill"), desc = "agentic: kill agent" },
  { "<leader>ad", cmd("AgentDelete"), desc = "agentic: delete agent" },
  { "<leader>ar", cmd("AgentRename"), desc = "agentic: rename agent" },
  { "<leader>am", cmd("AgentMove"), desc = "agentic: move agent (manager)" },
  { "<leader>ap", cmd("AgentPauseToggle"), desc = "agentic: pause / resume agent" },
  { "<leader>ae", cmd("AgentWriteToggle"), desc = "agentic: expand / collapse write buffer" },
  { "<leader>aw", cmd("AgentWriteFocus"), desc = "agentic: focus write buffer" },
  { "<leader>av", cmd("AgentReadSplit"), desc = "agentic: second read buffer" },
  { "<leader>aR", cmd("AgentRefresh"), desc = "agentic: refresh tree" },
  { "<leader>al", cmd("AgentMcpLog"), desc = "agentic: MCP client log" },
  { "<leader>an", cmd("AgentNotices"), desc = "agentic: open notices" },
}

local function map(buf, mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { buffer = buf, nowait = true, silent = true, desc = desc })
end

function M.tree_buffer(buf)
  local tree = function ()
    return require("tabs.agentic.tree")
  end
  local actions = function ()
    return require("tabs.agentic.actions")
  end
  map(buf, "n", "<CR>", function () tree().activate() end, "open agent / toggle")
  map(buf, "n", "o", function () tree().activate() end, "open agent / toggle")
  map(buf, "n", "<2-LeftMouse>", function () tree().activate() end, "open agent / toggle")
  map(buf, "n", "l", function () tree().expand(true) end, "expand")
  map(buf, "n", "h", function () tree().expand(false) end, "collapse")
  map(buf, "n", "<Tab>", function () tree().toggle() end, "toggle")
  map(buf, "n", "a", function () actions().create() end, "AgentCreate")
  map(buf, "n", "S", function () actions().start() end, "AgentStart")
  map(buf, "n", "s", function () actions().stop() end, "AgentStop")
  map(buf, "n", "X", function () actions().kill() end, "AgentKill")
  map(buf, "n", "d", function () actions().delete() end, "AgentDelete")
  map(buf, "n", "r", function () actions().rename() end, "AgentRename")
  map(buf, "n", "m", function () actions().move() end, "AgentMove")
  map(buf, "n", "p", function () actions().toggle_pause() end, "pause / resume")
  map(buf, "n", "v", function () actions().second_read() end, "second read buffer")
  map(buf, "n", "R", cmd("AgentRefresh"), "refresh")
  map(buf, "n", "L", function () actions().mcp_log() end, "MCP log")
  map(buf, "n", "N", cmd("AgentNotices"), "notices")
  map(buf, "n", "q", function () require("tabs.agentic.layout").close_tree() end, "close tree")
  map(buf, "n", "?", function () tree().help() end, "help")
end

local INSERT_KEYS = { "i", "I", "a", "A", "o", "O", "c", "C", "s", "S", "R", "x", "X", "p", "P", "d", "D", "u", "<C-r>" }

function M.read_buffer(buf)
  local blocked = function ()
    vim.notify("The read buffer is read-only. gw copies the block or selection to the write buffer; gn seeds a new agent.",
      vim.log.levels.INFO)
  end
  for _, key in ipairs(INSERT_KEYS) do
    map(buf, "n", key, blocked, "read-only")
  end
  map(buf, "n", "gw", cmd("AgentCopyToWrite"), "copy current block to write buffer")
  map(buf, "x", "gw", ":AgentCopyToWrite<CR>", "copy selection to write buffer")
  map(buf, "n", "gn", cmd("AgentSeed"), "seed a new agent from the current block")
  map(buf, "x", "gn", ":AgentSeed<CR>", "seed a new agent from the selection")
end

function M.write_buffer(buf)
  map(buf, { "n", "i" }, "<C-s>", function ()
    vim.cmd("stopinsert")
    require("tabs.agentic.write").submit(buf)
  end, "submit to the agent")
end

return M
