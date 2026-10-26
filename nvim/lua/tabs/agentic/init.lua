-- Agentic tab package: nui agent tree, AgentCreate panel, read/write buffers, and the Agent* commands.
-- System Agentic reuses this package (tabs.system_agentic) with a fixed root and the cross-project tree.
local M = {}

M.mode = "agentic"
M.modes = { "agentic", "system_agentic" }
M.send_modes = { "standard", "system_standard" }

function M.keymaps()
  return require("tabs.agentic.keymaps")
end

-- Close nvim-tree, build the tree/read/write layout, and refresh the tree for this tab.
function M.on_enter(_)
  require("tabs.standard").close_tree()
  local layout = require("tabs.agentic.layout")
  local tree = require("tabs.agentic.tree")
  layout.ensure()
  tree.refresh()
  tree.check_branch()
  tree.start_timer()
end

function M.on_leave(_)
end

-- Close the agentic tree in the current tab (called on Standard TabEnter).
function M.close_tree()
  require("tabs.agentic.layout").close_tree()
end

-- Agent shown in the panes of the current tab, as fresh meta (or nil).
function M.selected()
  local u = require("tabs.agentic.state").get()
  return u and u.agent_id and require("tabs.agentic.store").find(u.agent_id) or nil
end

-- Show agent `agent_id` in the read and write panes of the current agentic tab.
function M.open_agent(agent_id)
  local meta = require("tabs.agentic.store").find(agent_id)
  if not meta then
    return vim.notify("No agent " .. tostring(agent_id), vim.log.levels.WARN)
  end
  require("tabs.agentic.layout").show(meta)
end

local function id_command(fn)
  return function (args)
    fn(args.args)
  end
end

-- Register the Agent* user commands. Bodies only run in Agentic / System Agentic tabs,
-- except AgentSend, which only runs in Standard / System Standard tabs.
function M.setup()
  local runtime = require("tabs.runtime")
  local actions = function ()
    return require("tabs.agentic.actions")
  end
  local complete = function (lead)
    return actions().complete(lead)
  end
  local id_opts = function (desc)
    return { nargs = "?", complete = complete, desc = desc }
  end

  runtime.guard_commands(M.modes, function ()
    local create = vim.api.nvim_create_user_command
    create("AgentCreate", function (args)
      actions().create({ name = args.args ~= "" and args.args or nil })
    end, { nargs = "?", desc = "Open the AgentCreate panel ([name])" })
    create("AgentStart", id_command(function (id) actions().start(id) end), id_opts("Start an agent that already exists"))
    create("AgentStop", id_command(function (id) actions().stop(id) end), id_opts("Ask an agent's supervisor to finish"))
    create("AgentKill", id_command(function (id) actions().kill(id) end), id_opts("Terminate an agent's supervisor now"))
    create("AgentDelete", id_command(function (id) actions().delete(id) end), id_opts("Kill and delete an agent and its transcript"))
    create("AgentPause", id_command(function (id) actions().pause(id) end), id_opts("Pause an agent"))
    create("AgentResume", id_command(function (id) actions().resume(id) end), id_opts("Resume an agent"))
    create("AgentPauseToggle", id_command(function (id) actions().toggle_pause(id) end), id_opts("Pause or resume an agent"))
    create("AgentRename", function (args)
      local id, name = args.fargs[1], table.concat(vim.list_slice(args.fargs, 2), " ")
      if id and not require("tabs.agentic.store").find(id) then
        id, name = nil, args.args
      end
      actions().rename(id, name)
    end, { nargs = "*", complete = complete, desc = "Rename an agent ([id] [new name])" })
    create("AgentMove", function (args)
      local id, manager = args.fargs[1], args.fargs[2]
      if id and not manager and not require("tabs.agentic.store").find(id) then
        id, manager = nil, id
      end
      actions().move(id, manager)
    end, { nargs = "*", complete = complete, desc = "Move an agent to another manager ([id] [manager])" })
    create("AgentSubmit", function ()
      require("tabs.agentic.write").submit()
    end, { desc = "Send the write buffer to the selected agent" })
    create("AgentWriteToggle", function ()
      require("tabs.agentic.layout").toggle_write()
    end, { desc = "Expand the write buffer to the right side or collapse it to 20%" })
    create("AgentWriteFocus", function ()
      require("tabs.agentic.layout").focus_write()
    end, { desc = "Focus the write buffer" })
    create("AgentReadSplit", id_command(function (id) actions().second_read(id) end), id_opts("Open a second read buffer"))
    create("AgentMcpLog", id_command(function (id) actions().mcp_log(id) end), id_opts("Open the MCP client log in a read-only buffer"))
    create("AgentNotices", function ()
      require("tabs.agentic.notices").open()
    end, { desc = "Open the Notices messages in a read-only panel" })
    create("AgentTree", function ()
      require("tabs.agentic.layout").toggle_tree()
    end, { desc = "Toggle the agentic tree" })
    create("AgentAllowRead", function (args)
      local meta = M.selected()
      if not meta then
        return vim.notify("AgentAllowRead: select an agent first", vim.log.levels.WARN)
      end
      local dir = vim.fn.fnamemodify(args.args, ":p")
      if vim.fn.isdirectory(dir) ~= 1 then
        return vim.notify("AgentAllowRead: not a directory: " .. dir, vim.log.levels.WARN)
      end
      require("tabs.agentic.client").allow_read(meta.agent_id, dir, function (value, err)
        if err then
          vim.notify("AgentAllowRead: " .. err, vim.log.levels.ERROR)
        else
          vim.notify("Agent " .. meta.agent_id .. " may read " .. dir, vim.log.levels.INFO)
        end
      end)
    end, { nargs = 1, complete = "dir", desc = "Grant the selected agent read access to one extra directory" })
    create("AgentRefresh", function ()
      local tree = require("tabs.agentic.tree")
      local u = require("tabs.agentic.state").get()
      u.mcp, u.mcp_errors = nil, {}
      tree.check_branch()
      tree.refresh()
    end, { desc = "Refresh the agentic tree and MCP status" })
    create("AgentCopyToWrite", function (args)
      actions().copy_to_write(args)
    end, { range = true, desc = "Copy the selection or current read block into the write buffer" })
    create("AgentSeed", function (args)
      actions().seed(args)
    end, { range = true, desc = "Seed a new agent from the selection or current read block" })
  end)

  vim.api.nvim_create_user_command("AgentSend", function (args)
    if runtime.guard(M.send_modes, "AgentSend") then
      require("tabs.agentic.send").run(args)
    end
  end, { range = true, desc = "Put the visual selection into a new or existing agent's write buffer (not submitted)" })
end

return M
