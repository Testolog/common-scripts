-- Answers `lsp_request` events with a language server Neovim already runs. Never starts a server.
-- `function` is an LSP method (textDocument/rename, ...) for the lsp_* tools, or a client name
-- (lua_ls, jdtls, ...) for the language-server entries; then the first argument names the method.
local client = require("tabs.agentic.client")
local state = require("tabs.agentic.state")

local M = {}

M.SHORT = {
  hover = "textDocument/hover",
  definition = "textDocument/definition",
  references = "textDocument/references",
  rename = "textDocument/rename",
}

local has_011 = vim.fn.has("nvim-0.11") == 1

local function reply(meta, ev, text)
  client.lsp_result(meta.agent_id, ev.id, text)
end

local function method_of(word)
  if type(word) ~= "string" then
    return nil
  end
  if word:find("/", 1, true) then
    return word
  end
  return M.SHORT[word:lower():gsub("^lsp_", "")]
end

-- { file, line, col, rest } from argv words ("file:line:col" ... or file line col ...) or an object.
local function parse_position(args)
  if type(args) == "table" and not vim.islist(args) then
    return {
      file = args.file or args.path or args.uri,
      line = tonumber(args.line),
      col = tonumber(args.column or args.col or args.character or 1),
      rest = { args.new_name or args.newName or args.name },
    }
  end
  args = args or {}
  local first = args[1]
  if type(first) ~= "string" then
    return nil
  end
  local file, line, col = first:match("^(.-):(%d+):(%d+)$")
  local rest_from = 2
  if not file then
    file, line, col = first:match("^(.-):(%d+)$")
    if file then
      col = 1
    else
      file, line, col = first, args[2], args[3]
      rest_from = 4
    end
  end
  return { file = file, line = tonumber(line), col = tonumber(col) or 1, rest = vim.list_slice(args, rest_from) }
end

local function supports(lsp_client, method, bufnr)
  if has_011 then
    return lsp_client:supports_method(method, bufnr)
  end
  return lsp_client.supports_method(method, { bufnr = bufnr })
end

local function request(lsp_client, method, params, handler, bufnr)
  if has_011 then
    return lsp_client:request(method, params, handler, bufnr)
  end
  return lsp_client.request(method, params, handler, bufnr)
end

local function filetype_of(path)
  return vim.filetype.match({ filename = path }) or ""
end

-- Buffer for `path`, loaded without FileType autocmds so no server is auto-started.
local function buffer_for(path)
  local bufnr = vim.fn.bufadd(path)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    vim.cmd(("silent noautocmd call bufload(%d)"):format(bufnr))
  end
  if vim.bo[bufnr].filetype == "" then
    local ft = filetype_of(path)
    if ft ~= "" then
      vim.api.nvim_buf_call(bufnr, function ()
        vim.cmd("noautocmd setlocal filetype=" .. ft)
      end)
    end
  end
  return bufnr
end

local function within(path, root)
  if not root or root == "" then
    return false
  end
  root = vim.fs.normalize(root)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

-- obsidian-ls is the vault note server. It attaches across a vault, including pom.xml, and does not
-- answer hover, definition, or references for those files.
local function relevant(lsp_client, ft)
  if lsp_client.name == "obsidian-ls" and ft ~= "markdown" then
    return false
  end
  local fts = lsp_client.config and lsp_client.config.filetypes
  if fts and ft ~= "" and not vim.tbl_contains(fts, ft) then
    return false
  end
  return true
end

-- Attached clients for `bufnr`; else attach an already-running client that covers the file.
local function clients_for(bufnr, path, name, method)
  local ft = vim.bo[bufnr].filetype
  local filter = { bufnr = bufnr }
  if name then
    filter.name = name
  end
  local found = {}
  for _, c in ipairs(vim.lsp.get_clients(filter)) do
    if relevant(c, ft) then
      found[#found + 1] = c
    end
  end
  if #found == 0 then
    for _, c in ipairs(vim.lsp.get_clients(name and { name = name } or nil)) do
      if relevant(c, ft) then
        local fts = c.config and c.config.filetypes
        local ft_ok = fts and vim.tbl_contains(fts, ft)
        local root_ok = within(path, c.config and c.config.root_dir) or within(path, c.root_dir)
        for _, folder in ipairs(c.workspace_folders or {}) do
          root_ok = root_ok or within(path, vim.uri_to_fname(folder.uri))
        end
        if ft_ok and root_ok and vim.lsp.buf_attach_client(bufnr, c.id) then
          found[#found + 1] = c
        end
      end
    end
  end
  local usable = {}
  for _, c in ipairs(found) do
    if supports(c, method, bufnr) then
      usable[#usable + 1] = c
    end
  end
  return usable, found
end

local function location_lines(result, root)
  local out = {}
  local list = result
  if type(result) == "table" and (result.uri or result.targetUri) then
    list = { result }
  end
  for _, loc in ipairs(list or {}) do
    local uri = loc.uri or loc.targetUri
    local range = loc.range or loc.targetSelectionRange or loc.targetRange
    if uri and range then
      local fname = vim.uri_to_fname(uri)
      if root and within(fname, root) then
        fname = fname:sub(#vim.fs.normalize(root) + 2)
      end
      out[#out + 1] = string.format("%s:%d:%d", fname, range.start.line + 1, range.start.character + 1)
    end
  end
  return out
end

local function changed_uris(edit)
  local uris = {}
  for uri in pairs(edit.changes or {}) do
    uris[uri] = true
  end
  for _, change in ipairs(edit.documentChanges or {}) do
    if change.textDocument then
      uris[change.textDocument.uri] = true
    end
  end
  return vim.tbl_keys(uris)
end

local function format_result(method, result, lsp_client, root)
  if result == nil then
    return "The language server returned no result."
  end
  if method == "textDocument/hover" then
    local contents = vim.lsp.util.convert_input_to_markdown_lines(result.contents or {})
    return table.concat(contents, "\n")
  end
  if method == "textDocument/definition" or method == "textDocument/references"
    or method == "textDocument/declaration" or method == "textDocument/implementation"
    or method == "textDocument/typeDefinition" then
    local list = location_lines(result, root)
    return #list > 0 and table.concat(list, "\n") or "No locations."
  end
  if method == "textDocument/rename" then
    vim.lsp.util.apply_workspace_edit(result, lsp_client.offset_encoding)
    local files = {}
    for _, uri in ipairs(changed_uris(result)) do
      local bufnr = vim.uri_to_bufnr(uri)
      if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].modified then
        vim.api.nvim_buf_call(bufnr, function ()
          vim.cmd("silent update")
        end)
      end
      files[#files + 1] = vim.uri_to_fname(uri)
    end
    return "Renamed through " .. lsp_client.name .. " in " .. #files .. " file(s):\n" .. table.concat(files, "\n")
  end
  return vim.inspect(result)
end

-- Handle one lsp_request event for the agent described by `meta` (its project root resolves paths).
function M.handle(meta, ev)
  local fn = ev["function"]
  local args = ev.arguments
  local client_name, method
  if type(fn) == "string" and fn:find("/", 1, true) then
    method = fn
  else
    client_name = fn
    local words = type(args) == "table" and vim.islist(args) and args or nil
    method = words and method_of(words[1])
    if not method then
      return reply(meta, ev, string.format(
        "%s: pass the method first (hover, definition, references, rename, or textDocument/...), then file:line:column.",
        tostring(fn)))
    end
    args = vim.list_slice(words, 2)
  end
  local pos = parse_position(args)
  if not pos or not pos.file or not pos.line then
    return reply(meta, ev, "Expected file:line:column (1-based) as the first argument.")
  end
  local root = meta.project_root
  local path = pos.file:sub(1, 1) == "/" and pos.file or vim.fs.joinpath(root or vim.fn.getcwd(), pos.file)
  path = vim.fs.normalize(path)
  if not vim.uv.fs_stat(path) then
    return reply(meta, ev, "File not found: " .. path)
  end
  local ok, bufnr = pcall(buffer_for, path)
  if not ok then
    return reply(meta, ev, "Could not load " .. path .. ": " .. tostring(bufnr))
  end
  local usable, attached = clients_for(bufnr, path, client_name, method)
  if #usable == 0 then
    local msg
    if #attached == 0 then
      msg = string.format("No language server is attached to %s%s. Neovim does not start one for agents; use sd, dasel, or git apply.",
        path, client_name and (" (" .. client_name .. ")") or "")
    else
      msg = string.format("The attached server (%s) does not support %s. Use sd, dasel, or git apply.",
        table.concat(vim.tbl_map(function (c) return c.name end, attached), ", "), method)
    end
    state.notice("lsp: " .. msg, vim.log.levels.WARN, meta.agent_id)
    return reply(meta, ev, msg)
  end
  local lsp_client = usable[1]
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    position = { line = pos.line - 1, character = math.max(pos.col - 1, 0) },
  }
  if method == "textDocument/references" then
    params.context = { includeDeclaration = true }
  elseif method == "textDocument/rename" then
    local new_name = pos.rest[1]
    if type(new_name) ~= "string" or new_name == "" then
      return reply(meta, ev, "lsp_rename needs the new name after file:line:column.")
    end
    params.newName = new_name
  end
  request(lsp_client, method, params, function (err, result)
    if err then
      return reply(meta, ev, lsp_client.name .. " error: " .. tostring(err.message or vim.inspect(err)))
    end
    local done, text = pcall(format_result, method, result, lsp_client, root)
    reply(meta, ev, done and text or ("Could not apply the result: " .. tostring(text)))
  end, bufnr)
end

return M
