-- Bodies of the Agent* commands. Targets: an explicit agent id, else the tree node under the cursor,
-- else the agent shown in the panes. Every action is addressed by agent id, so the Python client
-- uses the project root in that agent's meta.json (also from the System Agentic tree).
local client = require("tabs.agentic.client")
local store = require("tabs.agentic.store")
local state = require("tabs.agentic.state")

local M = {}

-- Agent meta for an action: `id` argument, tree cursor, or the selected agent.
function M.target(id)
  if id and id ~= "" then
    local meta = store.find(id)
    if not meta then
      vim.notify("No agent " .. id, vim.log.levels.WARN)
    end
    return meta
  end
  local meta = require("tabs.agentic.tree").cursor_agent()
  if meta then
    return store.find(meta.agent_id) or meta
  end
  local u = state.get()
  if u and u.agent_id then
    return store.find(u.agent_id)
  end
  vim.notify("No agent selected: put the cursor on an agent in the tree or pass an agent id.", vim.log.levels.WARN)
end

local function label(meta)
  return (meta.name or meta.agent_id) .. " (" .. meta.agent_id .. ")"
end

local function refresh()
  require("tabs.agentic.tree").refresh_all()
end

local function done(what, meta, after)
  return function (value, err)
    if err then
      vim.notify(what .. " " .. label(meta) .. ": " .. err, vim.log.levels.ERROR)
    else
      if after then
        after(value)
      end
      vim.notify(what .. " " .. label(meta), vim.log.levels.INFO)
    end
    refresh()
  end
end

function M.create(opts)
  opts = opts or {}
  local manager = opts.manager or require("tabs.agentic.tree").cursor_manager()
  return require("tabs.agentic.create").open({ manager = manager, name = opts.name })
end

-- AgentStart: launch the supervisor again for an agent that already exists.
function M.start(id)
  local meta = M.target(id)
  if not meta then
    return
  end
  if meta.read_only then
    return vim.notify("Agent " .. label(meta) .. " is read-only after a handoff.", vim.log.levels.WARN)
  end
  if meta.alive then
    return vim.notify(label(meta) .. " is already running.", vim.log.levels.INFO)
  end
  client.restart(meta.agent_id, function (_, err)
    if err then
      return vim.notify("AgentStart " .. label(meta) .. ": " .. err, vim.log.levels.ERROR)
    end
    vim.notify("Started " .. label(meta), vim.log.levels.INFO)
    local fresh = store.find(meta.agent_id)
    if fresh then
      require("tabs.agentic.read").restart(fresh)
    end
    refresh()
  end)
end

-- AgentMcpLog: open this agent's MCP client log in a read-only buffer.
function M.mcp_log(id)
  local meta = M.target(id)
  if meta then
    require("tabs.agentic.mcp_log").open(store.find(meta.agent_id) or meta)
  end
end

-- AgentStop: ask the supervisor to finish.
function M.stop(id)
  local meta = M.target(id)
  if meta then
    client.stop(meta.agent_id, done("Stop requested for", meta))
  end
end

-- AgentKill: terminate the supervisor immediately. The transcript stays until AgentDelete.
function M.kill(id)
  local meta = M.target(id)
  if not meta then
    return
  end
  client.kill(meta.agent_id, function (value, err)
    if err then
      vim.notify("AgentKill " .. label(meta) .. ": " .. err, vim.log.levels.ERROR)
    elseif value and value.killed == false then
      vim.notify("AgentKill " .. label(meta) .. ": supervisor was not running", vim.log.levels.INFO)
    else
      vim.notify("Killed " .. label(meta) .. "; transcript kept until :AgentDelete", vim.log.levels.INFO)
      state.notice("killed " .. (meta.name or meta.agent_id), vim.log.levels.WARN, nil)
    end
    require("tabs.agentic.read").update_meta(store.find(meta.agent_id) or meta)
    refresh()
  end)
end

-- AgentDelete: kill if alive and remove the agent directory (transcript included) after confirmation.
function M.delete(id)
  local meta = M.target(id)
  if not meta then
    return
  end
  local choice = vim.fn.confirm("Delete agent " .. label(meta) .. " and its transcript?", "&Delete\n&Cancel", 2)
  if choice ~= 1 then
    return
  end
  client.delete(meta.agent_id, function (_, err)
    if err then
      return vim.notify("AgentDelete " .. label(meta) .. ": " .. err, vim.log.levels.ERROR)
    end
    store.forget(meta.agent_id)
    for _, entry in ipairs(state.agentic_tabs()) do
      if entry.ui.agent_id == meta.agent_id then
        entry.ui.agent_id = nil
        if entry.tab == state.tab() then
          require("tabs.agentic.layout").show(nil)
        end
      end
    end
    require("tabs.agentic.read").wipe(meta.agent_id)
    vim.notify("Deleted " .. label(meta), vim.log.levels.INFO)
    refresh()
  end)
end

function M.rename(id, new_name)
  local meta = M.target(id)
  if not meta then
    return
  end
  local function apply(name)
    name = name and vim.trim(name) or ""
    if name == "" then
      return
    end
    client.rename(meta.agent_id, name, done("Renamed", meta, function (value)
      require("tabs.agentic.read").update_meta(value or { agent_id = meta.agent_id, name = name })
    end))
  end
  if new_name and new_name ~= "" then
    return apply(new_name)
  end
  vim.ui.input({ prompt = "Rename agent: ", default = meta.name or "" }, apply)
end

-- AgentMove: change the agent's manager folder.
function M.move(id, manager)
  local meta = M.target(id)
  if not meta then
    return
  end
  local function apply(target)
    target = target and vim.trim(target) or ""
    if target == "" then
      return
    end
    client.move(meta.agent_id, target, done("Moved", meta, function ()
      local fresh = store.find(meta.agent_id)
      if fresh then
        require("tabs.agentic.read").restart(fresh)
      end
    end))
  end
  if manager and manager ~= "" then
    return apply(manager)
  end
  vim.ui.input({ prompt = "Move to manager: ", default = meta.manager or "default" }, apply)
end

function M.pause(id)
  local meta = M.target(id)
  if meta then
    client.pause(meta.agent_id, done("Paused", meta))
  end
end

function M.resume(id)
  local meta = M.target(id)
  if meta then
    client.resume(meta.agent_id, done("Resumed", meta))
  end
end

function M.toggle_pause(id)
  local meta = M.target(id)
  if not meta then
    return
  end
  if meta.status == "paused" then
    M.resume(meta.agent_id)
  else
    M.pause(meta.agent_id)
  end
end

-- Pick an agent of this tab's tree (or `id`) for a second read buffer.
function M.second_read(id)
  local meta = id and id ~= "" and store.find(id) or require("tabs.agentic.tree").cursor_agent()
  local layout = require("tabs.agentic.layout")
  if meta then
    return layout.open_second_read(store.find(meta.agent_id) or meta)
  end
  local u, st = state.get()
  local agents = require("tabs.agentic.tree").agents(u, st)
  vim.ui.select(agents, {
    prompt = "Second read buffer",
    format_item = function (m)
      return (m.name or m.agent_id) .. "  [" .. tostring(m.status) .. "]"
    end,
  }, function (choice)
    if choice then
      layout.open_second_read(choice)
    end
  end)
end

-- Text of a range in the current buffer (charwise for a matching visual selection).
function M.range_text(args)
  local buf = vim.api.nvim_get_current_buf()
  local s, e = vim.fn.getpos("'<"), vim.fn.getpos("'>")
  if args.range > 0 and s[2] == args.line1 and e[2] == args.line2 and vim.fn.visualmode() ~= "V" then
    local ok, region = pcall(vim.fn.getregion, s, e, { type = vim.fn.visualmode() })
    if ok and type(region) == "table" then
      return table.concat(region, "\n")
    end
  end
  return table.concat(vim.api.nvim_buf_get_lines(buf, args.line1 - 1, args.line2, false), "\n")
end

-- Text from the read buffer: the range when given, else the current block.
local function read_text(args)
  local buf = vim.api.nvim_get_current_buf()
  if args.range > 0 then
    return M.range_text(args)
  end
  local lines = require("tabs.agentic.read").current_block(buf, vim.api.nvim_win_get_cursor(0)[1])
  return table.concat(lines, "\n")
end

-- Copy selected text / the current block of the read buffer into the selected agent's write buffer.
function M.copy_to_write(args)
  local text = read_text(args)
  if vim.trim(text) == "" then
    return vim.notify("Nothing to copy.", vim.log.levels.INFO)
  end
  local u = state.get()
  local write = require("tabs.agentic.write")
  write.append(write.buffer(u and u.agent_id or write.DRAFT), text)
  require("tabs.agentic.layout").focus_write()
end

-- Seed a new agent with selected text / the current block: draft write buffer + AgentCreate panel.
function M.seed(args)
  local text = read_text(args)
  if vim.trim(text) == "" then
    return vim.notify("Nothing to seed from.", vim.log.levels.INFO)
  end
  local write = require("tabs.agentic.write")
  write.append(write.buffer(write.DRAFT), text)
  require("tabs.agentic.layout").show(nil)
  M.create()
end

-- Completion of agent ids listed in this tab's tree.
function M.complete(arg_lead)
  local u, st = state.get()
  if not u or not state.is_agentic(st) then
    return {}
  end
  local out = {}
  local ok, agents = pcall(require("tabs.agentic.tree").agents, u, st)
  for _, meta in ipairs(ok and agents or {}) do
    if meta.agent_id:find(arg_lead, 1, true) == 1 then
      out[#out + 1] = meta.agent_id
    end
  end
  return out
end

return M
