local M = {}

-- Output order of project_type.
M.order = { "java", "yaml", "avsc", "json", "sql" }

-- Kind prompts: prompt name -> kinds that select it. Prompts not listed here are always copied.
M.prompt_kinds = {
  java = { "java" },
  data = { "yaml", "avsc", "json", "sql" },
}

M.java_build_files = { "pom.xml", "build.gradle", "build.gradle.kts" }

M.skip_dirs = {
  [".git"] = true, node_modules = true, target = true, build = true, dist = true, out = true,
  [".venv"] = true, venv = true, __pycache__ = true, [".idea"] = true, [".gradle"] = true,
  lua_modules = true, [".luarocks"] = true, [".mypy_cache"] = true, [".pytest_cache"] = true,
  [".ruff_cache"] = true, [".tox"] = true, [".cache"] = true,
}

M.max_depth = 8
M.max_entries = 50000

local by_extension = {
  yml = "yaml",
  yaml = "yaml",
  avsc = "avsc",
  json = "json",
  sql = "sql",
}

-- Kinds found under `root`, in M.order. `existing` is the stored project_type (java there is kept).
function M.detect(root, existing)
  local found = {}
  for _, kind in ipairs(existing or {}) do
    if kind == "java" then
      found.java = true
    end
  end
  for _, file in ipairs(M.java_build_files) do
    if vim.uv.fs_stat(vim.fs.joinpath(root, file)) then
      found.java = true
    end
  end

  local remaining = 0
  for _, kind in ipairs({ "yaml", "avsc", "json", "sql" }) do
    if not found[kind] then
      remaining = remaining + 1
    end
  end

  local seen = 0
  local ok = pcall(function ()
    for name, type in vim.fs.dir(root, {
      depth = M.max_depth,
      skip = function (dir_name)
        return not M.skip_dirs[vim.fs.basename(dir_name)]
      end,
    }) do
      seen = seen + 1
      if seen > M.max_entries then
        break
      end
      if type == "file" then
        local base = vim.fs.basename(name)
        local kind = by_extension[(base:match("%.([^.]+)$") or ""):lower()]
        if kind and not found[kind] and not (kind == "json" and base == ".nvim_project.json") then
          found[kind] = true
          remaining = remaining - 1
          if remaining <= 0 then
            break
          end
        end
      end
    end
  end)
  if not ok then
    vim.notify("system_project: kind scan stopped early in " .. root, vim.log.levels.WARN)
  end

  local kinds = {}
  for _, kind in ipairs(M.order) do
    if found[kind] then
      kinds[#kinds + 1] = kind
    end
  end
  for _, kind in ipairs(existing or {}) do
    if not vim.tbl_contains(kinds, kind) then
      kinds[#kinds + 1] = kind
    end
  end
  return kinds
end

-- Entries of `prompts` that apply to `kinds` (base and other unmapped prompts always apply).
function M.select_prompts(prompts, kinds)
  local out = {}
  for _, entry in ipairs(prompts or {}) do
    local wanted = M.prompt_kinds[entry.name]
    local keep = wanted == nil
    for _, kind in ipairs(wanted or {}) do
      if vim.tbl_contains(kinds, kind) then
        keep = true
        break
      end
    end
    if keep then
      out[#out + 1] = vim.deepcopy(entry)
    end
  end
  return out
end

return M
