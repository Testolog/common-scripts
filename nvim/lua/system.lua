local M = {}

function M.lua_libs_path(root, lua_version)
  local luarocks = vim.fn.join({ root, "lua_modules" }, "/")
  local share = vim.fn.join({ luarocks, "share", "lua", tostring(lua_version) }, "/")
  local lib = vim.fn.join({ luarocks, "lib", "lua", tostring(lua_version) }, "/")
  return { share = share, lib = lib }
end

function M.user_command(project_settings)
  vim.api.nvim_create_user_command("JsonFormat", function()
    vim.cmd("%!jq")
  end, { desc = "json format with jq" })

  vim.api.nvim_create_user_command("SQLFormat", function()
    vim.cmd("%!sql-formatter -l sql")
  end, { desc = "format sql file" })

  vim.api.nvim_create_user_command("Escape", require("escape").escape, { desc = "escape text" })

  vim.api.nvim_create_user_command("UnEscape", function(input)
    return vim.fn.execute(
      string.format("python -c \"print('%s'.encode('utf-8').decode('unicode_escape'))\"", input.args)
    )
  end, { desc = "un escape string" })

  vim.api.nvim_create_user_command("Quit", function()
    vim.cmd("qa!")
  end, { desc = "Quit" })

  vim.api.nvim_create_user_command("SSHKeyLoad", function()
    vim.fn.system('eval "$(ssh-agent -s)"')
    print(project_settings.ssh_key)
    vim.fn.system("ssh-add " .. project_settings.ssh_key)
  end, {})

  vim.api.nvim_create_user_command("FormatSelection", function(opts)
    require("format_selection").run(opts.buf or vim.api.nvim_get_current_buf(), opts.line1, opts.line2)
  end, { range = true, desc = "format selected lines as JSON, YAML, SQL, or Python (picker)" })

  require("arduino").register_commands()
  require("error_log").setup()
  require("c_run").register_commands()
  require("idf").register_commands()
end

function M.auto_commands(project_settings)
  vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("format_selection", { clear = true }),
    once = true,
    callback = function()
      require("format_selection")
    end,
  })

  vim.api.nvim_create_autocmd("TermOpen", {
    group = vim.api.nvim_create_augroup("custom_configuration", { clear = true }),
    callback = function()
      vim.opt.number = false
      vim.opt.relativenumber = false
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("custom_configuration", { clear = true }),
    pattern = "pom.xml",
    callback = function()
      vim.cmd("Maven")
    end,
  })

  vim.api.nvim_create_user_command("AppendPy", function()
    local ok, snacks = pcall(require, "snacks")
    if not ok then
      return vim.notify("Snacks.nvim not found!", vim.log.levels.ERROR)
    end

    local function add_pythonpath(picker, item)
      picker:close()
      if not item or not item.file then return end
      local path = item.file
      local current_env = vim.fn.getenv("PYTHONPATH")
      if current_env == vim.NIL then current_env = "" end
      local is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
      local sep = is_windows and ";" or ":"
      local new_env = (current_env ~= "" and (current_env .. sep) or "") .. path
      vim.fn.setenv("PYTHONPATH", new_env)
      vim.cmd("LspRestart")
      vim.notify("PYTHONPATH appended & LSP restarted:\n" .. path, vim.log.levels.INFO)
    end

    snacks.picker.explorer({
      cwd = vim.fn.expand("~"),
      layout = { preset = "default", preview = false },
      exclude = {
        "__pycache__", "node_modules", ".git", ".venv", ".mypy_cache",
        ".pytest_cache", ".ruff_cache", "build", "dist", "egg-info",
      },
      hidden = false,
      win = {
        input = { keys = { ["<C-e>"] = { "add_pythonpath", mode = { "i", "n" } } } },
        list = { keys = { ["<C-e>"] = "add_pythonpath" } },
      },
      actions = { add_pythonpath = add_pythonpath },
    })
  end, {})
end

function M.filetype()
  vim.filetype.add({
    pattern = {
      ["*.jsonc"] = "json",
      ["*.ino"] = "arduino",
      ["*.pde"] = "arduino",
    },
  })
end

function M.tmux_rename(settings)
  if vim.env.TMUX ~= nil then
    vim.fn.system(string.format("tmux rename-window '%s'", settings.name))
  end
end

return M
