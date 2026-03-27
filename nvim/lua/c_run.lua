-- Compile and run current C/C++ file. Uses gcc/g++, output to temp then execute in terminal.

local M = {}

local function get_current_file()
  local path = vim.api.nvim_buf_get_name(0)
  if not path or path == "" or vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  return vim.fn.fnamemodify(path, ":p")
end

local function run_in_terminal(cmd)
  vim.cmd("split")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.fn.termopen(cmd, {
    on_exit = function(_, code, _)
      if code ~= 0 then
        vim.schedule(function()
          vim.notify("Process exited with code " .. code, vim.log.levels.WARN)
        end)
      end
    end,
  })
  vim.cmd("startinsert")
end

function M.run()
  local path = get_current_file()
  if not path then
    vim.notify("No file to run (save the buffer first).", vim.log.levels.ERROR)
    return
  end
  local ext = vim.fn.fnamemodify(path, ":e"):lower()
  local is_cpp = (ext == "cpp" or ext == "cc" or ext == "cxx" or ext == "c++")
  local compiler = is_cpp and "g++" or "gcc"
  local out = vim.fn.tempname()
  local cmd = string.format("%s -o %s %s && %s", compiler, vim.fn.shellescape(out), vim.fn.shellescape(path), vim.fn.shellescape(out))
  vim.notify("Compiling and running ...", vim.log.levels.INFO)
  run_in_terminal(cmd)
end

function M.register_commands()
  vim.api.nvim_create_user_command("CRun", function()
    M.run()
  end, { desc = "Compile and run current C/C++ file" })
end

return M
