-- Read-only view of agent state on disk: $HOME/agentic/<project>/<branch>/<manager>/<agent_id>/meta.json.
-- Agents are found by walking for meta.json; depth carries no meaning. Writes go through tabs.agentic.client.
local M = {}

M.META = "meta.json"
M.MCP_LOG = "mcp.log"
M.PID = "supervisor.pid"
M.TRANSCRIPT = "transcript.md"
M.EVENTS = "events.jsonl"

local decode_opts = { luanil = { object = true, array = true } }
local cache = {}

function M.home()
  local override = vim.env.AGENTIC_HOME
  if override and override ~= "" then
    return vim.fs.normalize(override)
  end
  return vim.fs.joinpath(vim.uv.os_homedir(), "agentic")
end

local function segments(value)
  local out = {}
  for part in tostring(value or ""):gsub("\\", "/"):gmatch("[^/]+") do
    if part ~= "." and part ~= ".." then
      out[#out + 1] = part
    end
  end
  return out
end
M.segments = segments

local function parse_branch(code, stdout)
  if code ~= 0 then
    return "nogit"
  end
  local branch = vim.trim(stdout or "")
  if branch == "" then
    return "nogit"
  elseif branch == "HEAD" then
    return "detached"
  end
  return branch
end

-- `git rev-parse --abbrev-ref HEAD` in `root`: nogit outside git, detached on a detached HEAD.
function M.branch(root)
  local ok, proc = pcall(vim.system, { "git", "rev-parse", "--abbrev-ref", "HEAD" }, { cwd = root, text = true })
  if not ok then
    return "nogit"
  end
  local obj = proc:wait(5000)
  return parse_branch(obj.code, obj.stdout)
end

function M.branch_async(root, cb)
  local ok = pcall(vim.system, { "git", "rev-parse", "--abbrev-ref", "HEAD" }, { cwd = root, text = true }, function (obj)
    vim.schedule(function ()
      cb(parse_branch(obj.code, obj.stdout))
    end)
  end)
  if not ok then
    cb("nogit")
  end
end

function M.project_name(project, root)
  local name = project and project.name
  if type(name) == "string" and vim.trim(name) ~= "" then
    return vim.trim(name)
  end
  return vim.fs.basename(root)
end

function M.branch_dir(project_name, branch)
  local parts = segments(branch)
  if #parts == 0 then
    parts = { "nogit" }
  end
  return vim.fs.joinpath(M.home(), project_name, unpack(parts))
end

local function read_file(path)
  local fh = io.open(path, "r")
  if not fh then
    return nil
  end
  local data = fh:read("*a")
  fh:close()
  return data
end
M.read_file = read_file

function M.pid_alive(pid)
  if not pid or pid <= 0 then
    return false
  end
  local ok, _, name = vim.uv.kill(pid, 0)
  return ok == 0 or name == "EPERM"
end

-- Parsed meta.json of `dir` plus dir, pid, alive. nil when unreadable.
function M.read(dir)
  local text = read_file(vim.fs.joinpath(dir, M.META))
  if not text then
    return nil
  end
  local ok, meta = pcall(vim.json.decode, text, decode_opts)
  if not ok or type(meta) ~= "table" or not meta.agent_id then
    return nil
  end
  meta.dir = dir
  meta.pid = tonumber(vim.trim(read_file(vim.fs.joinpath(dir, M.PID)) or ""))
  meta.alive = M.pid_alive(meta.pid)
  cache[meta.agent_id] = meta
  return meta
end

-- Every agent below `base` (default the agentic home), at any depth. Skips dot dirs and mcp-auth.
function M.scan(base)
  base = base or M.home()
  local out = {}
  if vim.fn.isdirectory(base) ~= 1 then
    return out
  end
  local home = M.home()
  local function visit(dir, depth)
    if depth > 40 then
      return
    end
    if vim.uv.fs_stat(vim.fs.joinpath(dir, M.META)) then
      local meta = M.read(dir)
      if meta then
        out[#out + 1] = meta
      end
    end
    local names = {}
    for name, kind in vim.fs.dir(dir) do
      if kind == "directory" and name:sub(1, 1) ~= "." and not (dir == home and name == "mcp-auth") then
        names[#names + 1] = name
      end
    end
    table.sort(names)
    for _, name in ipairs(names) do
      visit(vim.fs.joinpath(dir, name), depth + 1)
    end
  end
  visit(base, 0)
  return out
end

-- Agents of one project and branch (stopped ones included).
function M.project_agents(project_name, branch)
  local out = {}
  for _, meta in ipairs(M.scan(M.branch_dir(project_name, branch))) do
    if meta.project_name == project_name and meta.branch == branch then
      out[#out + 1] = meta
    end
  end
  return out
end

-- Agents under the agentic home whose supervisor is alive, from every project and branch.
function M.running_agents()
  local out = {}
  for _, meta in ipairs(M.scan()) do
    if meta.alive then
      out[#out + 1] = meta
    end
  end
  return out
end

-- Fresh meta for `agent_id` (re-reads the cached dir, else walks the home).
function M.find(agent_id)
  local cached = cache[agent_id]
  if cached and vim.uv.fs_stat(vim.fs.joinpath(cached.dir, M.META)) then
    local meta = M.read(cached.dir)
    if meta and meta.agent_id == agent_id then
      return meta
    end
  end
  for _, meta in ipairs(M.scan()) do
    if meta.agent_id == agent_id then
      return meta
    end
  end
  cache[agent_id] = nil
end

function M.forget(agent_id)
  cache[agent_id] = nil
end

return M
