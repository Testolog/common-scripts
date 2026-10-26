-- Thin wrapper over the Python agent client CLI (scripts/agentic, `agentic-client`).
-- Every subcommand prints one JSON value; `events` prints one JSON object per line.
local M = {}

local decode_opts = { luanil = { object = true, array = true } }

-- scripts/agentic of $COMMON_SCRIPT, else of the checkout this config ships from.
function M.scripts_dir()
  local system_project = require("system_project")
  for _, base in ipairs({ system_project.common_script(), system_project.shipped_root() }) do
    local dir = vim.fs.joinpath(base, "scripts", "agentic")
    if vim.fn.isdirectory(dir) == 1 then
      return dir
    end
  end
  return vim.fs.joinpath(system_project.shipped_root(), "scripts", "agentic")
end

local function agentic_home()
  local override = vim.env.AGENTIC_HOME
  if override and override ~= "" then
    return vim.fs.normalize(override)
  end
  return vim.fs.joinpath(vim.uv.os_homedir(), "agentic")
end

-- Command prefix: vim.g.agentic_client_cmd, `agentic-client` on PATH, the installer venv, or python3 -m.
function M.command()
  if type(vim.g.agentic_client_cmd) == "table" then
    return vim.deepcopy(vim.g.agentic_client_cmd)
  end
  local exe = vim.fn.exepath("agentic-client")
  if exe ~= "" then
    return { exe }
  end
  local venv = vim.fs.joinpath(agentic_home(), ".venv", "bin", "python")
  local python = vim.fn.executable(venv) == 1 and venv or "python3"
  return { python, "-m", "agentic_client" }
end

local function env()
  local path = M.scripts_dir()
  if vim.env.PYTHONPATH and vim.env.PYTHONPATH ~= "" then
    path = path .. ":" .. vim.env.PYTHONPATH
  end
  return { PYTHONPATH = path, COMMON_SCRIPT = require("system_project").common_script() }
end

local function decode_last(stdout)
  local last
  for line in (stdout or ""):gmatch("[^\n]+") do
    last = line
  end
  if not last then
    return nil
  end
  local ok, value = pcall(vim.json.decode, last, decode_opts)
  if ok then
    return value
  end
end

local function result(obj)
  local value = decode_last(obj.stdout)
  if type(value) == "table" and value.ok == false then
    return nil, value.error or "agentic client failed"
  end
  if obj.code ~= 0 then
    local stderr = vim.trim(obj.stderr or "")
    local tail = stderr:match("([^\n]+)$") or stderr
    return nil, tail ~= "" and tail or ("agentic client exited with " .. tostring(obj.code))
  end
  return value
end

-- Run `args`. With `cb`, run asynchronously and call cb(value, err) on the main loop.
-- Without `cb`, wait (opts.timeout ms, default 30000) and return value, err.
function M.run(args, opts, cb)
  opts = opts or {}
  local cmd = vim.list_extend(M.command(), args)
  local sys_opts = { text = true, env = env(), stdin = opts.stdin, cwd = opts.cwd }
  if cb then
    local ok, err = pcall(vim.system, cmd, sys_opts, function (obj)
      vim.schedule(function ()
        cb(result(obj))
      end)
    end)
    if not ok then
      vim.schedule(function ()
        cb(nil, "cannot run agentic client: " .. tostring(err))
      end)
    end
    return
  end
  local ok, proc = pcall(vim.system, cmd, sys_opts)
  if not ok then
    return nil, "cannot run agentic client: " .. tostring(proc)
  end
  return result(proc:wait(opts.timeout or 30000))
end

-- Follow `events ID --offset N`. on_event(event) runs on the main loop. Returns the job id or nil.
function M.events(agent_id, offset, on_event, on_exit)
  local cmd = vim.list_extend(M.command(), { "events", agent_id, "--offset", tostring(offset or 0) })
  local partial = ""
  local ok, job = pcall(vim.fn.jobstart, cmd, {
    env = env(),
    on_stdout = function (_, data)
      data[1] = partial .. data[1]
      partial = table.remove(data)
      for _, line in ipairs(data) do
        if line ~= "" then
          local decoded, event = pcall(vim.json.decode, line, decode_opts)
          if decoded and type(event) == "table" then
            on_event(event)
          end
        end
      end
    end,
    on_exit = function (_, code)
      if on_exit then
        on_exit(code)
      end
    end,
  })
  if ok and job > 0 then
    return job
  end
end

local function csv(list)
  return table.concat(list, ",")
end

-- spec: { root, name, mode, model (string or table), manager, prompts (list|nil = all), skills, message }
function M.start(spec, cb)
  local args = { "start", "--root", spec.root, "--name", spec.name, "--mode", spec.mode or "ask" }
  if spec.model then
    local model = type(spec.model) == "table" and vim.json.encode(spec.model) or spec.model
    vim.list_extend(args, { "--model", model })
  end
  if spec.manager and spec.manager ~= "" then
    vim.list_extend(args, { "--manager", spec.manager })
  end
  if spec.prompts then
    vim.list_extend(args, { "--prompts", csv(spec.prompts) })
  end
  if spec.skills then
    vim.list_extend(args, { "--skills", csv(spec.skills) })
  end
  if spec.message and spec.message ~= "" then
    vim.list_extend(args, { "--message", spec.message })
  end
  return M.run(args, {}, cb)
end

function M.send(agent_id, text, cb)
  return M.run({ "send", agent_id }, { stdin = text }, cb)
end

for _, name in ipairs({ "pause", "resume", "stop", "kill", "delete", "restart" }) do
  M[name] = function (agent_id, cb)
    return M.run({ name, agent_id }, {}, cb)
  end
end

function M.rename(agent_id, name, cb)
  return M.run({ "rename", agent_id, name }, {}, cb)
end

function M.move(agent_id, manager, cb)
  return M.run({ "move", agent_id, manager }, {}, cb)
end

function M.allow_read(agent_id, directory, cb)
  return M.run({ "allow-read", agent_id, directory }, {}, cb)
end

function M.attach_nvim(agent_id, cb)
  return M.run({ "attach-nvim", agent_id, tostring(vim.fn.getpid()) }, {}, cb or function () end)
end

function M.detach_nvim(agent_id, cb)
  return M.run({ "detach-nvim", agent_id }, {}, cb or function () end)
end

function M.lsp_result(agent_id, request_id, text, cb)
  return M.run({ "lsp-result", agent_id, request_id }, { stdin = text }, cb or function () end)
end

function M.list_agents(root, running, cb)
  local args = { "list" }
  if root then
    vim.list_extend(args, { "--root", root })
  end
  if running then
    args[#args + 1] = "--running"
  end
  return M.run(args, {}, cb)
end

function M.list_models(root, cb)
  return M.run({ "models", "--root", root }, { timeout = 60000 }, cb)
end

function M.update_cursor_models(cb)
  return M.run({ "update-cursor-models" }, { timeout = 60000 }, cb)
end

function M.mcp_status(root, cb)
  return M.run({ "mcp", "--root", root }, {}, cb)
end

return M
