-- Agentic tree (nui.nvim). A project tab lists $HOME/agentic/<project>/<branch>/ grouped by manager.
-- The System Agentic tab lists every running agent under $HOME/agentic, grouped by project, branch, manager.
-- Both show MCP status for the tab root and tree notices (handoffs, MCP and LSP errors).
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local client = require("tabs.agentic.client")
local store = require("tabs.agentic.store")
local state = require("tabs.agentic.state")

local M = {}

M.REFRESH_MS = 3000

local timer

local function fmt_time(iso)
  if type(iso) ~= "string" then
    return "?"
  end
  return (iso:gsub("T", " "):gsub("[+-]%d%d%d%d$", ""))
end

local function model_name(meta)
  local model = meta.model
  if type(model) == "table" then
    return string.format("%s (%s)", tostring(model.name), tostring(model.vendor))
  end
  return tostring(model)
end

local function sort_agents(list)
  table.sort(list, function (a, b)
    return (a.created_at or "") < (b.created_at or "")
  end)
  return list
end

local function agent_node(u, meta)
  local fmt = require("tabs.agentic.read").fmt_tokens
  local details = {
    { "created", fmt_time(meta.created_at) },
    { "modified", fmt_time(meta.updated_at) },
    { "tokens", tostring(meta.tokens or 0) .. " (" .. tostring(meta.tokens_source or "estimate") .. ")" },
    { "context", tostring(meta.context_limit or "?") },
    { "model", model_name(meta) },
    { "mode", tostring(meta.mode) },
    { "manager", tostring(meta.manager) },
    { "root", tostring(meta.project_root) },
    { "id", tostring(meta.agent_id) },
  }
  if meta.parent then
    details[#details + 1] = { "parent", tostring(meta.parent) }
  end
  if meta.handoff_to then
    details[#details + 1] = { "handoff", "→ " .. tostring(meta.handoff_to) .. " (read-only)" }
  end
  local children = {}
  for _, d in ipairs(details) do
    children[#children + 1] = NuiTree.Node({
      id = "detail:" .. meta.agent_id .. ":" .. d[1],
      kind = "detail",
      label = d[1],
      value = d[2],
    })
  end
  local node = NuiTree.Node({
    id = "agent:" .. meta.agent_id,
    kind = "agent",
    meta = meta,
    selected = u.agent_id == meta.agent_id,
    stats = fmt(meta.tokens) .. "/" .. fmt(meta.context_limit),
  }, children)
  return node
end

-- Group agents into nested manager folders under `prefix`.
local function manager_nodes(u, agents, prefix)
  local root = { children = {}, order = {}, agents = {} }
  for _, meta in ipairs(sort_agents(agents)) do
    local cursor = root
    local path = prefix
    local manager = {}
    for _, seg in ipairs(store.segments(meta.manager or "default")) do
      path = path .. "/" .. seg
      manager[#manager + 1] = seg
      if not cursor.children[seg] then
        cursor.children[seg] = {
          name = seg,
          path = path,
          manager = table.concat(manager, "/"),
          children = {},
          order = {},
          agents = {},
        }
        cursor.order[#cursor.order + 1] = seg
      end
      cursor = cursor.children[seg]
    end
    cursor.agents[#cursor.agents + 1] = meta
  end
  local function build(group)
    local out = {}
    table.sort(group.order)
    for _, name in ipairs(group.order) do
      local child = group.children[name]
      out[#out + 1] = NuiTree.Node({ id = "grp:" .. child.path, kind = "manager", label = name, manager = child.manager },
        build(child))
    end
    for _, meta in ipairs(group.agents) do
      out[#out + 1] = agent_node(u, meta)
    end
    return out
  end
  return build(root)
end

local function group_by(list, key)
  local groups, order = {}, {}
  for _, meta in ipairs(list) do
    local k = tostring(meta[key] or "?")
    if not groups[k] then
      groups[k] = {}
      order[#order + 1] = k
    end
    table.insert(groups[k], meta)
  end
  table.sort(order)
  return groups, order
end

local function mcp_nodes(u)
  local children = {}
  local mcp = u.mcp
  if mcp == nil then
    children[#children + 1] = NuiTree.Node({ id = "mcp:loading", kind = "info", label = "loading…" })
  elseif mcp.error_text then
    children[#children + 1] = NuiTree.Node({ id = "mcp:client", kind = "error", label = "client: " .. mcp.error_text })
  else
    if mcp.error then
      children[#children + 1] = NuiTree.Node({ id = "mcp:parse", kind = "error", label = "parse error: " .. tostring(mcp.error) })
    end
    for _, server in ipairs(mcp.servers or {}) do
      local status = tostring(server.status)
      local active = server.active == true or status == "connect"
      local label = string.format("[%s] %s  %s", active and "x" or " ", server.name, status)
      if server.reason and server.reason ~= "" then
        label = label .. " — " .. server.reason
      end
      local err = u.mcp_errors[server.name]
      if err then
        label = label .. "  error: " .. err
      end
      children[#children + 1] = NuiTree.Node({
        id = "mcp:" .. server.name,
        kind = (status == "unsupported" or err) and "error" or (status == "connect" and "ok" or "info"),
        mcp = true,
        server = server.name,
        active = active,
        label = label,
      })
    end
    for name, err in pairs(u.mcp_errors) do
      local listed = false
      for _, server in ipairs(mcp.servers or {}) do
        listed = listed or server.name == name
      end
      if not listed then
        children[#children + 1] = NuiTree.Node({ id = "mcp:err:" .. name, kind = "error", label = name .. "  error: " .. err })
      end
    end
    if #children == 0 then
      children[#children + 1] = NuiTree.Node({ id = "mcp:none", kind = "info", label = "no servers in " .. tostring(mcp.path or "~/.cursor/mcp.json") })
    end
  end
  return NuiTree.Node({
    id = "section:mcp",
    kind = "section",
    label = "MCP  [x] Enter turns a server on or off for this project",
  }, children)
end

local function notice_nodes(visible)
  local children = {}
  for i, n in ipairs(state.notices()) do
    if not n.agent_id or visible[n.agent_id] then
      children[#children + 1] = NuiTree.Node({
        id = "notice:" .. i .. ":" .. n.time,
        kind = n.level >= vim.log.levels.WARN and "error" or "info",
        notice = n,
        label = n.time .. " " .. tostring(n.text or ""):gsub("\n", " "),
      })
    end
  end
  if #children == 0 then
    return nil
  end
  return NuiTree.Node({ id = "section:notices", kind = "section", label = "Notices  Enter opens the messages" }, children)
end

-- Agents this tab's tree lists.
function M.agents(u, st)
  if state.is_system(st) then
    return store.running_agents()
  end
  u.branch = u.branch or store.branch(st.root)
  return store.project_agents(store.project_name(st.project, st.root), u.branch)
end

local function build_nodes(u, st)
  local agents = M.agents(u, st)
  local visible = {}
  for _, meta in ipairs(agents) do
    visible[meta.agent_id] = true
  end
  u.visible = visible
  local nodes = {}
  if state.is_system(st) then
    local projects, porder = group_by(agents, "project_name")
    local children = {}
    for _, project in ipairs(porder) do
      local branches, border = group_by(projects[project], "branch")
      local bnodes = {}
      for _, branch in ipairs(border) do
        local prefix = project .. "@" .. branch
        bnodes[#bnodes + 1] = NuiTree.Node({ id = "grp:" .. prefix, kind = "branch", label = branch },
          manager_nodes(u, branches[branch], prefix))
      end
      children[#children + 1] = NuiTree.Node({ id = "grp:" .. project, kind = "project", label = project }, bnodes)
    end
    if #children == 0 then
      children[1] = NuiTree.Node({ id = "info:none", kind = "info", label = "no running agents" })
    end
    nodes[#nodes + 1] = NuiTree.Node({ id = "root", kind = "root", label = "Running agents (all projects)" }, children)
  else
    local name = store.project_name(st.project, st.root)
    local children = manager_nodes(u, agents, "")
    if #children == 0 then
      children[1] = NuiTree.Node({ id = "info:none", kind = "info", label = "no agents yet — press a to create one" })
    end
    nodes[#nodes + 1] = NuiTree.Node({ id = "root", kind = "root", label = name .. " @ " .. tostring(u.branch) }, children)
  end
  nodes[#nodes + 1] = mcp_nodes(u)
  local notices = notice_nodes(visible)
  if notices then
    nodes[#nodes + 1] = notices
  end
  return nodes
end

local HL = {
  root = "Title",
  project = "Directory",
  branch = "Special",
  manager = "Directory",
  section = "Title",
  detail = "Comment",
  info = "Comment",
  error = "DiagnosticWarn",
  ok = "DiagnosticOk",
}

local function prepare_node(node)
  local line = NuiLine()
  line:append(string.rep("  ", node:get_depth() - 1))
  if node:has_children() then
    line:append(node:is_expanded() and "▾ " or "▸ ", "Comment")
  else
    line:append("  ")
  end
  if node.kind == "agent" then
    local meta = node.meta
    line:append(meta.alive and "● " or "○ ", meta.alive and "DiagnosticOk" or "Comment")
    line:append(tostring(meta.name or meta.agent_id), node.selected and "Search" or "Normal")
    line:append("  " .. tostring(meta.status or "?"), "Comment")
    line:append("  " .. node.stats, "Number")
    line:append("  " .. tostring(meta.mode or ""), "Comment")
    if meta.read_only then
      line:append("  read-only", "WarningMsg")
    end
  elseif node.kind == "detail" then
    line:append(string.format("%-9s", node.label), "Comment")
    line:append(node.value, "Normal")
  else
    line:append(node.label, HL[node.kind] or "Normal")
  end
  return line
end

function M.buffer()
  local u = state.get()
  if u.tree_buf and vim.api.nvim_buf_is_valid(u.tree_buf) then
    return u.tree_buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "agentic_tree"
  pcall(vim.api.nvim_buf_set_name, buf, "agentic://tree/" .. state.tab())
  u.tree_buf = buf
  u.tree = NuiTree({ bufnr = buf, nodes = {}, prepare_node = prepare_node })
  require("tabs.agentic.keymaps").tree_buffer(buf)
  return buf
end

function M.configure_window(win)
  local wo = vim.wo[win]
  wo.winfixwidth = true
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.wrap = false
  wo.cursorline = true
  wo.spell = false
  wo.winbar = "%#Title# Agents %* ? keys"
end

local function restore_expansion(u, tree, nodes)
  local function walk(list)
    for _, node in ipairs(list) do
      local id = node:get_id()
      local collapsible = node.kind ~= "agent"
      if (collapsible and not u.collapsed[id]) or (not collapsible and u.expanded[id]) then
        node:expand()
      end
      if node:has_children() then
        walk(tree:get_nodes(id))
      end
    end
  end
  walk(nodes)
end

-- Rebuild and render the tree of `tab` (default current). Keeps expansion and the cursor node.
function M.refresh(tab)
  tab = tab or state.tab()
  local u, st = state.get(tab)
  if not u or not state.is_agentic(st) or not u.tree then
    return
  end
  if u.mcp == nil and not u.mcp_loading then
    M.load_mcp(tab)
  end
  local ok, nodes = pcall(build_nodes, u, st)
  if not ok then
    nodes = { NuiTree.Node({ id = "error", kind = "error", label = "tree error: " .. tostring(nodes) }) }
  end
  local win = state.valid_win(u.tree_win, tab) and u.tree_win or nil
  local cursor_id
  if win then
    local okn, node = pcall(u.tree.get_node, u.tree)
    cursor_id = okn and node and node:get_id() or nil
  end
  u.tree:set_nodes(nodes)
  restore_expansion(u, u.tree, u.tree:get_nodes())
  u.tree:render()
  if win and cursor_id then
    local _, linenr = u.tree:get_node(cursor_id)
    if linenr then
      pcall(vim.api.nvim_win_set_cursor, win, { linenr, 0 })
    end
  end
  if win then
    local title = state.is_system(st) and "System agents" or ("Agents · " .. tostring(u.branch))
    vim.wo[win].winbar = "%#Title# " .. title:gsub("%%", "%%%%") .. " %* ? keys"
  end
end

function M.refresh_all()
  for _, entry in ipairs(state.agentic_tabs()) do
    if entry.ui.tree then
      M.refresh(entry.tab)
    end
  end
end

function M.load_mcp(tab)
  local u, st = state.get(tab)
  if not u then
    return
  end
  u.mcp_loading = true
  client.mcp_status(st.root, function (value, err)
    u.mcp_loading = false
    u.mcp = err and { error_text = err } or (value or { servers = {} })
    M.refresh(tab)
  end)
end

-- Re-read the branch (async). A changed branch swaps the directory the project tree lists.
function M.check_branch(tab)
  local u, st = state.get(tab)
  if not u or state.is_system(st) or not st.root then
    return
  end
  store.branch_async(st.root, function (branch)
    if branch ~= u.branch then
      u.branch = branch
      state.notice("branch is now " .. branch .. "; tree shows " .. store.branch_dir(store.project_name(st.project, st.root), branch))
    end
    M.refresh(tab)
  end)
end

function M.start_timer()
  if timer then
    return
  end
  timer = vim.uv.new_timer()
  timer:start(M.REFRESH_MS, M.REFRESH_MS, vim.schedule_wrap(function ()
    local tab = state.tab()
    local u, st = state.get(tab)
    if u and state.is_agentic(st) and state.valid_win(u.tree_win, tab) then
      if state.is_system(st) then
        M.refresh(tab)
      else
        M.check_branch(tab)
      end
    end
  end))
end

-- Node under the cursor in the current tab's tree window, if the cursor is there.
function M.cursor_node()
  local u = state.get()
  if not u or not u.tree or vim.api.nvim_get_current_win() ~= u.tree_win then
    return nil
  end
  local ok, node = pcall(u.tree.get_node, u.tree)
  return ok and node or nil
end

-- Agent meta under the cursor (an agent node or one of its detail rows).
function M.cursor_agent()
  local node = M.cursor_node()
  if not node then
    return nil
  end
  if node.kind == "detail" then
    local u = state.get()
    node = u.tree:get_node(node:get_parent_id())
  end
  return node and node.kind == "agent" and node.meta or nil
end

-- Manager path under the cursor (manager folder or the manager of the agent there).
function M.cursor_manager()
  local node = M.cursor_node()
  if not node then
    return nil
  end
  if node.kind == "manager" then
    return node.manager
  end
  local meta = M.cursor_agent()
  return meta and meta.manager or nil
end

function M.toggle(node)
  local u = state.get()
  node = node or M.cursor_node()
  if not node or not node:has_children() then
    return
  end
  local id = node:get_id()
  if node:is_expanded() then
    node:collapse()
    u.collapsed[id] = true
    u.expanded[id] = nil
  else
    node:expand()
    u.collapsed[id] = nil
    u.expanded[id] = true
  end
  u.tree:render()
end

function M.expand(open)
  local node = M.cursor_node()
  if not node then
    return
  end
  if node:has_children() and node:is_expanded() ~= open then
    M.toggle(node)
  elseif not open and node:get_parent_id() then
    local u = state.get()
    local _, linenr = u.tree:get_node(node:get_parent_id())
    if linenr then
      vim.api.nvim_win_set_cursor(0, { linenr, 0 })
    end
  end
end

-- Write isActive for the MCP row under the cursor into this tab's project file.
function M.toggle_mcp(node)
  node = node or M.cursor_node()
  if not node or not node.mcp or not node.server then
    return
  end
  local u, st = state.get()
  if not st or not st.root then
    return vim.notify("This tab has no project to store the MCP flag.", vim.log.levels.WARN)
  end
  local path = vim.fs.joinpath(st.root, require("constants").project_file_name)
  local active = not node.active
  local ok, err = require("tabs.agentic.mcp").set_active(path, node.server, active)
  if not ok then
    return vim.notify("Could not update " .. path .. ": " .. tostring(err), vim.log.levels.ERROR)
  end
  vim.notify(string.format("%s is %s for this project. A new agent uses it.", node.server, active and "on" or "off"),
    vim.log.levels.INFO)
  u.mcp = nil
  M.load_mcp()
end

-- <CR>: open an agent in the panes, toggle an MCP server for this project, or toggle a folder.
function M.activate()
  local node = M.cursor_node()
  if node and (node.notice or node.id == "section:notices") then
    require("tabs.agentic.notices").open(node.notice)
    return
  end
  if node and node.mcp then
    M.toggle_mcp(node)
    return
  end
  local meta = M.cursor_agent()
  if meta then
    require("tabs.agentic.layout").show(store.find(meta.agent_id) or meta)
    return
  end
  M.toggle()
end

M.HELP = {
  "<CR>/o  open agent / turn the MCP row on or off / open Notices in a panel / toggle folder",
  "l / h   expand (agent stats) / collapse",
  "a       AgentCreate (manager under cursor)",
  "S       AgentStart (an agent that already exists)",
  "s       AgentStop      X  AgentKill      d  AgentDelete",
  "r       AgentRename    m  AgentMove (change manager)",
  "p       pause / resume",
  "v       open a second read buffer",
  "L       AgentMcpLog (read-only MCP client log)",
  "R       refresh (re-reads MCP status)",
  "q       close tree",
}

function M.help()
  vim.notify(table.concat(M.HELP, "\n"), vim.log.levels.INFO, { title = "Agentic tree" })
end

return M
