-- AgentCreate panel (nui.nvim): name, manager, prompts and skills multi-select, Ask/Edit, model.
-- Models are the union of the project `models`, the Cursor catalog stored in the system project
-- (`cursor_models.json`, refreshed only by :CursorUpdateModelList), and each local base_url's
-- GET /models. A local server that is not listening is reported.
local Popup = require("nui.popup")
local Input = require("nui.input")
local Menu = require("nui.menu")
local client = require("tabs.agentic.client")
local state = require("tabs.agentic.state")

local M = {}

local function entries(project, keys)
  local out = {}
  for _, key in ipairs(keys) do
    for _, item in ipairs(type(project[key]) == "table" and project[key] or {}) do
      if type(item) == "table" and item.name then
        out[#out + 1] = { name = item.name, source = key, path = item.path, selected = true }
      end
    end
  end
  return out
end

local function project_models(project)
  local out = {}
  for _, m in ipairs(type(project.models) == "table" and project.models or {}) do
    if type(m) == "table" and m.name then
      out[#out + 1] = {
        label = string.format("%s  (%s, %s)", m.name, tostring(m.vendor), tostring(m.context_limit or "?")),
        value = m.name,
        vendor = m.vendor,
        base_url = m.base_url,
      }
    end
  end
  return out
end

local function default_model(models)
  for _, m in ipairs(models) do
    if m.vendor == "cursor" and type(m.value) == "string" and m.value:find("optimize_for=balanced", 1, true) then
      return m
    end
  end
  for _, m in ipairs(models) do
    if m.vendor == "cursor" then
      return m
    end
  end
  return models[1]
end

local function cursor_id_label(raw)
  if type(raw) == "table" then
    local id = raw.id or raw.name
    return id, raw.label or id
  end
  return raw, raw
end

local function cursor_model(id, label)
  return {
    label = (label or id) .. "  (cursor)",
    value = id,
    vendor = "cursor",
  }
end

-- Merge `agentic-client models` output into the panel's model list and notes.
local function merge_models(form, value)
  local seen = {}
  local models = {}
  for _, m in ipairs(project_models({ models = value.project or {} })) do
    if m.vendor ~= "cursor" then
      models[#models + 1] = m
      seen[tostring(m.value) .. "|" .. tostring(m.vendor)] = true
    end
  end
  local catalog, explicit, picked = {}, false, {}
  for _, m in ipairs(value.project or {}) do
    if m.vendor == "cursor" and m.name and m.name ~= "auto" then
      explicit = true
      picked[m.name] = true
    end
  end
  for _, raw in ipairs(value.cursor or {}) do
    local id, label = cursor_id_label(raw)
    if id and not seen["catalog|" .. id] then
      seen["catalog|" .. id] = true
      catalog[#catalog + 1] = { id = id, label = label or id, selected = (not explicit) or picked[id] == true }
    end
  end
  form.catalog = catalog
  form.cursor_explicit = explicit
  for _, item in ipairs(catalog) do
    if item.selected and not seen[item.id .. "|cursor"] then
      seen[item.id .. "|cursor"] = true
      models[#models + 1] = cursor_model(item.id, item.label)
    end
  end
  for _, m in ipairs(value.project or {}) do
    if m.vendor == "cursor" and m.name and m.name ~= "auto" and not seen[m.name .. "|cursor"] then
      seen[m.name .. "|cursor"] = true
      models[#models + 1] = cursor_model(m.name, m.name)
    end
  end
  local limits = {}
  for _, m in ipairs(value.project or {}) do
    if m.base_url then
      limits[m.base_url] = limits[m.base_url] or m.context_limit
    end
  end
  for base_url, names in pairs(value["local"] or {}) do
    for _, name in ipairs(names) do
      if not seen[name .. "|openai"] then
        seen[name .. "|openai"] = true
        models[#models + 1] = {
          label = string.format("%s  (openai @ %s)", name, base_url),
          value = { name = name, vendor = "openai", base_url = base_url, context_limit = limits[base_url] or 32768 },
          vendor = "openai",
          base_url = base_url,
        }
      end
    end
  end
  form.models = models
  form.notes = {}
  for source, err in pairs(value.errors or {}) do
    if source == "cursor" then
      form.notes[#form.notes + 1] = "Cursor CLI: " .. err
    else
      local msg = tostring(err)
      if not msg:lower():find("not running", 1, true) then
        msg = "local server is not running at " .. source .. " (" .. msg .. ")"
      end
      form.notes[#form.notes + 1] = "Local " .. source .. ": " .. msg
      form.down = form.down or {}
      form.down[source] = true
    end
  end
  local current = form.model
  local keep = false
  for _, m in ipairs(models) do
    if current and vim.deep_equal(m.value, current.value) then
      form.model = m
      keep = true
    end
  end
  if not keep then
    form.model = default_model(models)
  end
end

local function render(form)
  local buf = form.popup.bufnr
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local rows, lines = {}, {}
  local function add(text, row)
    lines[#lines + 1] = text
    rows[#lines] = row
  end
  add("  Name:     " .. (form.name ~= "" and form.name or "<press Enter to set>"), { kind = "name" })
  add("  Manager:  " .. form.manager, { kind = "manager" })
  add("  Mode:     " .. form.mode .. "  (Enter picks one)", { kind = "mode" })
  local model = form.model
  local model_label = model and model.label or "<none>"
  if model and model.base_url and form.down and form.down[model.base_url] then
    model_label = model_label .. "  [local server is not running]"
  end
  add("  Prompts (system_prompt, then project_prompt):", nil)
  for i, p in ipairs(form.prompts) do
    add(string.format("    [%s] %s  (%s)", p.selected and "x" or " ", p.name, p.source), { kind = "prompt", index = i })
  end
  if #form.prompts == 0 then
    add("    (none in .nvim_project.json)", nil)
  end
  add("  Skills (system_skills, then project_skills):", nil)
  for i, s in ipairs(form.skills) do
    add(string.format("    [%s] %s  (%s)", s.selected and "x" or " ", s.name, s.source), { kind = "skill", index = i })
  end
  if #form.skills == 0 then
    add("    (none in .nvim_project.json)", nil)
  end
  add("", nil)
  add("  Model:    " .. model_label .. (form.loading and "  …" or "") .. "  (Enter picks one)", { kind = "model" })
  for _, note in ipairs(form.notes or {}) do
    add("  ! " .. note, nil)
  end
  if form.draft ~= "" then
    add("  Write buffer already holds the AgentSend text (not submitted).", nil)
  end
  add("", nil)
  add("  [ Create ]   [ Cancel ]      <CR>/<Space> edit or toggle · <C-s> create · q cancel", { kind = "actions" })
  form.rows = rows
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local height = math.min(#lines, math.floor(vim.o.lines * 0.8))
  pcall(function ()
    form.popup:update_layout({ size = { width = form.width, height = height } })
  end)
end

local function refocus(form)
  if form.popup.winid and vim.api.nvim_win_is_valid(form.popup.winid) then
    vim.api.nvim_set_current_win(form.popup.winid)
  end
end

local function ask(form, title, default, on_submit)
  local input = Input({
    relative = "editor",
    position = "50%",
    size = { width = 50 },
    border = { style = "rounded", text = { top = " " .. title .. " ", top_align = "left" } },
    zindex = 60,
  }, {
    default_value = default or "",
    on_submit = function (value)
      on_submit(value)
      vim.schedule(function ()
        refocus(form)
        render(form)
      end)
    end,
    on_close = function ()
      vim.schedule(function ()
        refocus(form)
      end)
    end,
  })
  input:mount()
  input:map("n", { "<Esc>", "q" }, function ()
    input:unmount()
  end, { noremap = true })
end

local function choose_mode(form)
  local items = { Menu.item("Ask", { mode = "ask" }), Menu.item("Edit", { mode = "edit" }) }
  local menu = Menu({
    relative = "editor",
    position = "50%",
    size = { width = 24, height = 2 },
    border = { style = "rounded", text = { top = " Mode ", top_align = "left" } },
    zindex = 60,
  }, {
    lines = items,
    keymap = { focus_next = { "j", "<Down>", "<Tab>" }, focus_prev = { "k", "<Up>", "<S-Tab>" },
      close = { "<Esc>", "q" }, submit = { "<CR>", "<Space>" } },
    on_submit = function (item)
      form.mode = item.mode
      vim.schedule(function ()
        refocus(form)
        render(form)
      end)
    end,
    on_close = function ()
      vim.schedule(function ()
        refocus(form)
      end)
    end,
  })
  menu:mount()
end

local function choose_model(form)
  if #form.models == 0 then
    return vim.notify("No models: add one to models in .nvim_project.json", vim.log.levels.WARN)
  end
  local items = {}
  for i, m in ipairs(form.models) do
    items[#items + 1] = Menu.item(m.label, { index = i })
  end
  local menu = Menu({
    relative = "editor",
    position = "50%",
    size = { width = math.min(90, form.width), height = math.min(#items, 15) },
    border = { style = "rounded", text = { top = " Model ", top_align = "left" } },
    zindex = 60,
  }, {
    lines = items,
    keymap = { focus_next = { "j", "<Down>", "<Tab>" }, focus_prev = { "k", "<Up>", "<S-Tab>" },
      close = { "<Esc>", "q" }, submit = { "<CR>", "<Space>" } },
    on_submit = function (item)
      form.model = form.models[item.index]
      vim.schedule(function ()
        refocus(form)
        render(form)
      end)
    end,
    on_close = function ()
      vim.schedule(function ()
        refocus(form)
      end)
    end,
  })
  menu:mount()
end

local function save_cursor_models(form)
  local path = vim.fs.joinpath(form.root, require("constants").project_file_name)
  local json = require("util.json")
  local ok, data = pcall(json.read_file, path)
  if not ok then
    return vim.notify("Could not read " .. path .. ": " .. tostring(data), vim.log.levels.ERROR)
  end
  local models = {}
  for _, m in ipairs(type(data.models) == "table" and data.models or {}) do
    if type(m) ~= "table" or m.vendor ~= "cursor" then
      models[#models + 1] = m
    end
  end
  for _, item in ipairs(form.catalog or {}) do
    if item.selected then
      models[#models + 1] = { name = item.id, vendor = "cursor", context_limit = 200000 }
    end
  end
  data.models = models
  local wrote, err = json.write_file(path, data)
  if not wrote then
    return vim.notify("Could not write " .. path .. ": " .. tostring(err), vim.log.levels.ERROR)
  end
  form.cursor_explicit = true
  local _, st = state.get()
  if st and st.project then
    st.project.models = models
  end
  local kept = {}
  for _, m in ipairs(form.models or {}) do
    if m.vendor ~= "cursor" then
      kept[#kept + 1] = m
    end
  end
  for _, item in ipairs(form.catalog) do
    if item.selected then
      kept[#kept + 1] = cursor_model(item.id, item.label)
    end
  end
  form.models = kept
  local still = false
  for _, m in ipairs(kept) do
    if form.model and vim.deep_equal(m.value, form.model.value) then
      form.model = m
      still = true
    end
  end
  if not still then
    form.model = default_model(kept)
  end
  vim.notify("Saved " .. #models .. " models in " .. vim.fs.basename(path), vim.log.levels.INFO)
end

local function choose_catalog(form)
  if not form.catalog or #form.catalog == 0 then
    return vim.notify("No Cursor models reported yet.", vim.log.levels.WARN)
  end
  local popup = Popup({
    enter = true,
    focusable = true,
    relative = "editor",
    position = "50%",
    size = { width = math.min(78, form.width), height = math.min(#form.catalog + 2, 22) },
    zindex = 60,
    border = { style = "rounded", text = { top = " Cursor models for this project ", top_align = "left" } },
    buf_options = { modifiable = false, filetype = "agentic_create" },
    win_options = { cursorline = true, wrap = false },
  })
  local function draw()
    local lines = { "  [x] kept for AgentCreate    Enter toggles    q saves and closes" }
    for _, item in ipairs(form.catalog) do
      lines[#lines + 1] = string.format("  [%s] %s", item.selected and "x" or " ", item.label)
    end
    vim.bo[popup.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
    vim.bo[popup.bufnr].modifiable = false
  end
  popup:mount()
  draw()
  local function toggle()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local item = form.catalog[row - 1]
    if not item then
      return
    end
    item.selected = not item.selected
    draw()
  end
  local function close()
    popup:unmount()
    save_cursor_models(form)
    vim.schedule(function ()
      refocus(form)
      render(form)
    end)
  end
  popup:map("n", { "<CR>", "<Space>" }, toggle, { noremap = true })
  popup:map("n", { "q", "<Esc>" }, close, { noremap = true })
end

local function selected_names(list)
  local names, all = {}, true
  for _, item in ipairs(list) do
    if item.selected then
      names[#names + 1] = item.name
    else
      all = false
    end
  end
  return all and nil or names
end

local function create(form)
  if form.busy then
    return
  end
  local name = vim.trim(form.name)
  if name == "" then
    name = "agent-" .. os.date("%H%M%S")
  end
  if not form.model then
    return vim.notify("Pick a model first.", vim.log.levels.WARN)
  end
  form.busy = true
  client.start({
    root = form.root,
    name = name,
    mode = form.mode,
    model = form.model.value,
    manager = form.manager,
    prompts = selected_names(form.prompts),
    skills = selected_names(form.skills),
  }, function (value, err)
    form.busy = false
    if err then
      return vim.notify("AgentCreate: " .. err, vim.log.levels.ERROR)
    end
    form.popup:unmount()
    local store = require("tabs.agentic.store")
    local meta = store.read(value.dir) or store.find(value.agent_id)
    if form.tab and vim.api.nvim_tabpage_is_valid(form.tab) then
      vim.api.nvim_set_current_tabpage(form.tab)
    end
    require("tabs.agentic.write").adopt_draft(value.agent_id)
    if meta then
      require("tabs.agentic.layout").show(meta, { focus = "write" })
    end
    vim.notify("Agent " .. name .. " started (" .. value.agent_id .. ")", vim.log.levels.INFO)
    if form.on_created then
      form.on_created(meta or value)
    end
  end)
end

local function activate(form)
  local row = form.rows[vim.api.nvim_win_get_cursor(0)[1]]
  if not row then
    return
  end
  if row.kind == "name" then
    ask(form, "Name", form.name, function (v)
      form.name = v
    end)
  elseif row.kind == "manager" then
    ask(form, "Manager (folder path)", form.manager, function (v)
      v = vim.trim(v)
      form.manager = v ~= "" and v or "default"
    end)
  elseif row.kind == "mode" then
    choose_mode(form)
  elseif row.kind == "model" then
    choose_model(form)
  elseif row.kind == "prompt" then
    form.prompts[row.index].selected = not form.prompts[row.index].selected
    render(form)
  elseif row.kind == "skill" then
    form.skills[row.index].selected = not form.skills[row.index].selected
    render(form)
  elseif row.kind == "actions" then
    local col = vim.api.nvim_win_get_cursor(0)[2]
    if col >= 15 and col < 28 then
      form.popup:unmount()
    else
      create(form)
    end
  end
end

-- Open the panel for the current agentic tab. opts: { manager?, on_created? }.
function M.open(opts)
  opts = opts or {}
  local _, st = state.get()
  if not st or not st.root then
    return vim.notify("AgentCreate: no tab root", vim.log.levels.WARN)
  end
  local project = st.project or {}
  local draft_buf = require("tabs.agentic.write").buffer(require("tabs.agentic.write").DRAFT)
  local width = math.min(100, math.max(70, math.floor(vim.o.columns * 0.6)))
  local form = {
    tab = state.tab(),
    root = st.root,
    name = opts.name or "",
    manager = opts.manager or "default",
    mode = "ask",
    prompts = entries(project, { "system_prompt", "project_prompt" }),
    skills = entries(project, { "system_skills", "project_skills" }),
    models = project_models(project),
    notes = {},
    loading = true,
    width = width,
    draft = require("tabs.agentic.write").text(draft_buf),
    on_created = opts.on_created,
  }
  form.model = default_model(form.models)
  form.popup = Popup({
    enter = true,
    focusable = true,
    relative = "editor",
    position = "50%",
    size = { width = width, height = 20 },
    zindex = 50,
    border = {
      style = "rounded",
      text = { top = " AgentCreate · " .. vim.fs.basename(st.root) .. " ", top_align = "center" },
    },
    buf_options = { modifiable = false, filetype = "agentic_create" },
    win_options = { cursorline = true, wrap = false },
  })
  form.popup:mount()
  local map = function (lhs, fn)
    form.popup:map("n", lhs, fn, { noremap = true, nowait = true })
  end
  map("<CR>", function () activate(form) end)
  map("<Space>", function () activate(form) end)
  map("<C-s>", function () create(form) end)
  map("q", function () form.popup:unmount() end)
  map("<Esc>", function () form.popup:unmount() end)
  render(form)
  client.list_models(st.root, function (value, err)
    form.loading = false
    if err then
      form.notes = { "models: " .. err }
    elseif value then
      merge_models(form, value)
    end
    render(form)
  end)
  return form
end

return M
