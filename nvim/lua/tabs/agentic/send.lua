-- AgentSend (Standard and System Standard): put a visual selection, with its source path and line
-- range, into the write buffer of a new or existing agent of the same project and branch. Never submits.
local state = require("tabs.agentic.state")
local store = require("tabs.agentic.store")

local M = {}

-- Agentic mode that pairs with a Standard mode.
M.TARGET = { standard = "agentic", system_standard = "system_agentic" }

function M.format(path, line1, line2, filetype, text)
  local range = line1 == line2 and ("line " .. line1) or ("lines " .. line1 .. "-" .. line2)
  local fence = text:find("```", 1, true) and "````" or "```"
  return table.concat({
    "From `" .. path .. "` " .. range .. ":",
    "",
    fence .. (filetype or ""),
    text,
    fence,
  }, "\n")
end

local function pick(text)
  local u, st = state.get()
  local branch = u.branch or store.branch(st.root)
  local agents = store.project_agents(store.project_name(st.project, st.root), branch)
  table.sort(agents, function (a, b)
    return (a.updated_at or "") > (b.updated_at or "")
  end)
  local items = { { create = true } }
  vim.list_extend(items, agents)
  vim.ui.select(items, {
    prompt = "AgentSend: create a new context or pick one (" .. branch .. ")",
    format_item = function (item)
      if item.create then
        return "+ Create new agent"
      end
      return string.format("%s %s  [%s]  %s", item.alive and "●" or "○", item.name or item.agent_id,
        tostring(item.status), tostring(item.manager))
    end,
  }, function (choice)
    if not choice then
      return vim.notify("AgentSend cancelled; nothing was written.", vim.log.levels.INFO)
    end
    local write = require("tabs.agentic.write")
    local layout = require("tabs.agentic.layout")
    if choice.create then
      write.append(write.buffer(write.DRAFT), text)
      layout.show(nil)
      require("tabs.agentic.actions").create()
    else
      layout.show(store.find(choice.agent_id) or choice)
      write.append(write.buffer(choice.agent_id), text)
      layout.focus_write()
    end
  end)
end

function M.run(args)
  if args.range == 0 then
    return vim.notify("AgentSend: nothing is selected.", vim.log.levels.WARN)
  end
  local text = require("tabs.agentic.actions").range_text(args)
  if vim.trim(text) == "" then
    return vim.notify("AgentSend: nothing is selected.", vim.log.levels.WARN)
  end
  local runtime = require("tabs.runtime")
  local st = runtime.state()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" then
    path = "[No Name]"
  elseif st and st.root and path:sub(1, #st.root + 1) == st.root .. "/" then
    path = path:sub(#st.root + 2)
  end
  local block = M.format(path, args.line1, args.line2, vim.bo[buf].filetype, text)
  local mode = M.TARGET[st and st.mode or "standard"] or "agentic"
  local tab = runtime.open(mode, st and st.root, { reuse = true })
  if not tab then
    return
  end
  vim.schedule(function ()
    pick(block)
  end)
end

return M
