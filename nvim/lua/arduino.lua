-- Arduino/ESP32: compile, upload, serial monitor. Uses arduino-cli.
-- Require: arduino-cli, ESP32 core (arduino-cli core install esp32:esp32).
-- Plug in ESP32 via USB; port is auto-detected or pick with :ArduinoPort.
-- Chip type (ESP32, ESP32-C3, etc.) set with :ArduinoChip or in .nvim_project.json arduino.fqbn.

local M = {}

local ESP32_CHIPS = {
    { value = "esp32:esp32:esp32", label = "ESP32 Dev Module" },
    { value = "esp32:esp32:esp32c3", label = "ESP32-C3 Dev Module" },
    { value = "esp32:esp32:esp32s2", label = "ESP32-S2 Dev Module" },
    { value = "esp32:esp32:esp32s3", label = "ESP32-S3 Dev Module" },
    { value = "esp32:esp32:esp32c6", label = "ESP32-C6 Dev Module" },
    { value = "esp32:esp32:esp32h2", label = "ESP32-H2 Dev Module" },
}

local function get_sketch_dir()
    local bufpath = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    local start_dir = (#bufpath > 0) and vim.fn.fnamemodify(bufpath, ":p:h") or vim.fn.getcwd()
    local const = require("constants")
    local found = vim.fs.find({ "*.ino", "platformio.ini" }, { upward = true, path = start_dir })
    if found and found[1] then
        local f = found[1]
        if f:match("platformio%.ini") then
            return vim.fn.fnamemodify(f, ":p:h")
        end
        return vim.fn.fnamemodify(f, ":p:h")
    end
    return start_dir
end

local function arduino_cli(args, opts)
    opts = opts or {}
    local cmd = vim.list_extend({ "arduino-cli" }, args)
    if opts.stdin then
        return vim.fn.system(cmd, opts.stdin), vim.v.shell_error
    end
    local out = vim.fn.system(cmd)
    return out, vim.v.shell_error
end

function M.board_list()
    local out, err = arduino_cli({ "board", "list" })
    if err ~= 0 then
        return nil, out or "arduino-cli board list failed"
    end
    local boards = {}
    for line in (out or ""):gmatch("[^\r\n]+") do
        local port = line:match("(/dev/[%w%.%-_]+)") or line:match("(COM%d+)")
        local fqbn = line:match("([%w]+:[%w]+:[%w]+)")
        if port then
            table.insert(boards, {
                port = port,
                fqbn = fqbn or "esp32:esp32:esp32",
                name = (line:match("([%w%s]+)%s+" .. (fqbn or "")) or "Board"):gsub("^%s+", ""):gsub("%s+$", ""),
            })
        end
    end
    return boards
end

function M.detect_esp32_port()
    local boards, err = M.board_list()
    if err or not boards or #boards == 0 then
        return nil, err or "no boards found (connect ESP32 via USB)"
    end
    for _, b in ipairs(boards) do
        if (b.fqbn or ""):match("esp32") or (b.name or ""):lower():match("esp32") then
            return b.port, b.fqbn
        end
    end
    return boards[1].port, boards[1].fqbn
end

-- Prefer user-chosen port (from :ArduinoPort) then first detected ESP32.
local function get_preferred_port()
    local port = vim.b.arduino_port
    if port and port ~= "" then
        return port, vim.b.arduino_fqbn
    end
    return M.detect_esp32_port()
end

-- Prefer buffer chip (ArduinoChip), then project .nvim_project.json arduino.fqbn, then default.
local function get_preferred_fqbn()
    if vim.b.arduino_fqbn and vim.b.arduino_fqbn ~= "" then
        return vim.b.arduino_fqbn
    end
    local const = require("constants")
    local bufpath = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    local start_dir = (#bufpath > 0) and vim.fn.fnamemodify(bufpath, ":p:h") or vim.fn.getcwd()
    local found = vim.fs.find(const.project_file_name, { upward = true, path = start_dir })
    if found and found[1] then
        local ok, util = pcall(require, "util")
        if ok and util and util.read_json then
            local project = util.read_json(found[1])
            if project and project.arduino and project.arduino.fqbn then
                return project.arduino.fqbn
            end
        end
    end
    return "esp32:esp32:esp32"
end

local function get_project_file_path()
    local const = require("constants")
    local bufpath = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    local start_dir = (#bufpath > 0) and vim.fn.fnamemodify(bufpath, ":p:h") or vim.fn.getcwd()
    local found = vim.fs.find(const.project_file_name, { upward = true, path = start_dir })
    if found and found[1] then
        return vim.fn.fnamemodify(found[1], ":p")
    end
    return nil
end

local function get_project_arduino_libraries()
    local path = get_project_file_path()
    if not path then return {} end
    local ok, util = pcall(require, "util")
    if not ok or not util or not util.read_json then return {} end
    local project = util.read_json(path)
    if not project or not project.arduino or not project.arduino.libraries then return {} end
    return type(project.arduino.libraries) == "table" and project.arduino.libraries or {}
end

local function ensure_libraries_installed(libs)
    if not libs or #libs == 0 then return end
    for _, name in ipairs(libs) do
        name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then
            local out, err = arduino_cli({ "lib", "install", name })
            if err ~= 0 then
                vim.notify("Arduino lib install failed for '" .. name .. "': " .. (out or ""), vim.log.levels.WARN)
            end
        end
    end
end

-- Write sketch.yaml so arduino-language-server sees FQBN and port.
function M.sync_sketch_yaml()
    local sketch_dir = get_sketch_dir()
    if not sketch_dir then return end
    local fqbn = get_preferred_fqbn()
    local port = get_preferred_port()
    if type(port) == "table" then port = port.port end
    local lines = { "default_fqbn: " .. (fqbn or "esp32:esp32:esp32") }
    if port and port ~= "" then
        table.insert(lines, "default_port: " .. port)
    end
    local path = vim.fn.fnamemodify(sketch_dir, ":p") .. "sketch.yaml"
    local f = io.open(path, "w")
    if f then
        f:write(table.concat(lines, "\n") .. "\n")
        f:close()
    end
end

function M.compile(fqbn, sketch_dir)
    fqbn = fqbn or get_preferred_fqbn()
    sketch_dir = sketch_dir or get_sketch_dir()
    M.sync_sketch_yaml()
    ensure_libraries_installed(get_project_arduino_libraries())
    vim.notify("Compiling " .. sketch_dir .. " ...", vim.log.levels.INFO)
    local out, err = arduino_cli({ "compile", "--fqbn", fqbn, sketch_dir })
    if err ~= 0 then
        vim.notify("Compile failed:\n" .. (out or ""), vim.log.levels.ERROR)
        return false
    end
    vim.notify("Compile OK", vim.log.levels.INFO)
    return true
end

function M.upload(fqbn, sketch_dir, port)
    fqbn = fqbn or get_preferred_fqbn()
    sketch_dir = sketch_dir or get_sketch_dir()
    if not port or port == "" then
        port = get_preferred_port()
    end
    if type(port) == "table" then
        port, fqbn = port.port, port.fqbn or fqbn
    end
    if not port or port == "" then
        local _, err = M.detect_esp32_port()
        vim.notify("Upload failed: " .. (err or "no port") .. " Use :ArduinoPort to pick a device.", vim.log.levels
        .ERROR)
        return false
    end
    vim.notify("Uploading to " .. port .. " ...", vim.log.levels.INFO)
    local out, err = arduino_cli({ "upload", "-p", port, "--fqbn", fqbn, sketch_dir })
    if err ~= 0 then
        vim.notify("Upload failed:\n" .. (out or ""), vim.log.levels.ERROR)
        return false
    end
    vim.notify("Upload OK", vim.log.levels.INFO)
    return true
end

M._monitor_job_id = nil

function M.monitor(port, baud)
    if not port or port == "" then
        port = get_preferred_port()
    end
    if type(port) == "table" then
        port = port.port
    end
    if not port or port == "" then
        local _, err = M.detect_esp32_port()
        vim.notify("Monitor: " .. (err or "no port") .. " Use :ArduinoPort to pick a device.", vim.log.levels.ERROR)
        return
    end
    baud = baud or "115200"
    local cmd = "arduino-cli monitor -p " .. vim.fn.shellescape(port) .. " -c baudrate=" .. baud
    vim.cmd("split")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local job_id = vim.fn.termopen(cmd, {
        on_exit = function (_, code, _)
            M._monitor_job_id = nil
        end,
    })
    M._monitor_job_id = job_id
    vim.cmd("startinsert")
end

function M.monitor_stop()
    if M._monitor_job_id and vim.fn.jobwait({ M._monitor_job_id }, 0)[1] == -1 then
        vim.fn.jobstop(M._monitor_job_id)
        M._monitor_job_id = nil
        vim.notify("Serial monitor stopped.", vim.log.levels.INFO)
    else
        M._monitor_job_id = nil
        vim.notify("No serial monitor running.", vim.log.levels.INFO)
    end
end

function M.upload_and_monitor()
    local port = get_preferred_port()
    local fqbn = get_preferred_fqbn()
    if not port then
        vim.notify("No ESP32 found on USB. Use :ArduinoPort to pick a device.", vim.log.levels.ERROR)
        return
    end
    if type(port) == "table" then
        port = port.port
    end
    if M.compile(fqbn, get_sketch_dir()) and M.upload(fqbn, get_sketch_dir(), port) then
        vim.defer_fn(function ()
            M.monitor(port)
        end, 500)
    end
end

function M.pick_port(callback)
    local boards, err = M.board_list()
    if err or not boards or #boards == 0 then
        vim.notify(err or "No boards found", vim.log.levels.WARN)
        return
    end
    local items = {}
    for _, b in ipairs(boards) do
        table.insert(items, { value = b, label = b.port .. "  (" .. (b.name or b.fqbn or "") .. ")" })
    end
    vim.ui.select(items, {
        prompt = "Select board (ESP32 / USB):",
        format_item = function (item)
            return item.label
        end,
    }, function (choice)
        if choice and callback then
            callback(choice.value)
        end
    end)
end

function M.lib_install(name)
    name = name or vim.fn.input("Library name to install: ")
    if not name or name == "" then return end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    vim.notify("Installing library: " .. name .. " ...", vim.log.levels.INFO)
    local out, err = arduino_cli({ "lib", "install", name })
    if err ~= 0 then
        vim.notify("Install failed: " .. (out or ""), vim.log.levels.ERROR)
    else
        vim.notify("Installed: " .. name, vim.log.levels.INFO)
    end
end

function M.lib_search()
    local query = vim.fn.input("Search libraries: ")
    if not query or query == "" then return end
    local out, err = arduino_cli({ "lib", "search", query })
    if err ~= 0 or not out or out == "" then
        vim.notify("Search failed or no results.", vim.log.levels.WARN)
        return
    end
    local items = {}
    for line in (out or ""):gmatch("[^\r\n]+") do
        local name = line:match("^([%w%p%s]+)%s%S") or line:match("^([%w%p]+)") or line
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" and not name:match("^Name") then
            table.insert(items, { value = name, label = line:gsub("^%s+", ""):gsub("%s+$", "") })
        end
    end
    if #items == 0 then
        vim.notify("No libraries found.", vim.log.levels.INFO)
        return
    end
    vim.ui.select(items, {
        prompt = "Install library:",
        format_item = function (item) return item.label end,
    }, function (choice)
        if choice then M.lib_install(choice.value) end
    end)
end

function M.lib_add_to_project(name)
    name = name or vim.fn.input("Library name to add to project: ")
    if not name or name == "" then return end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    local path = get_project_file_path()
    if not path then
        vim.notify("No .nvim_project.json found. Create one in your sketch directory first.", vim.log.levels.ERROR)
        return
    end
    local ok, util = pcall(require, "util")
    if not ok or not util or not util.read_json then
        vim.notify("Could not read project file.", vim.log.levels.ERROR)
        return
    end
    local project = util.read_json(path)
    project.arduino = project.arduino or {}
    project.arduino.libraries = project.arduino.libraries or {}
    for _, lib in ipairs(project.arduino.libraries) do
        if lib == name then
            vim.notify("Library already in project: " .. name, vim.log.levels.INFO)
            return
        end
    end
    table.insert(project.arduino.libraries, name)
    local cjson = require("cjson")
    local f = io.open(path, "w")
    if not f then
        vim.notify("Could not write project file.", vim.log.levels.ERROR)
        return
    end
    f:write(cjson.encode(project))
    f:close()
    vim.notify("Added to project libraries: " .. name, vim.log.levels.INFO)
    M.lib_install(name)
end

function M.pick_chip(callback)
    vim.ui.select(ESP32_CHIPS, {
        prompt = "Select ESP32 chip:",
        format_item = function (item)
            return item.label
        end,
    }, function (choice)
        if choice then
            vim.b.arduino_fqbn = choice.value
            M.sync_sketch_yaml()
            vim.notify("Chip: " .. choice.label .. " (" .. choice.value .. ")", vim.log.levels.INFO)
            if callback then
                callback(choice.value)
            end
        end
    end)
end

function M.register_commands()
    vim.api.nvim_create_user_command("ArduinoCompile", function ()
        M.compile(nil, get_sketch_dir())
    end, { desc = "Compile Arduino/ESP32 sketch" })

    vim.api.nvim_create_user_command("ArduinoUpload", function (opts)
        local port = opts.args
        if port == "" then
            port = nil
        end
        M.upload(nil, get_sketch_dir(), port)
    end, { nargs = "?", desc = "Upload to ESP32 (auto-detect USB port)" })

    vim.api.nvim_create_user_command("ArduinoMonitor", function (opts)
        local port = opts.args
        if port == "" then
            port = nil
        end
        M.monitor(port)
    end, { nargs = "?", desc = "Open serial monitor (see ESP32 output)" })

    vim.api.nvim_create_user_command("ArduinoUploadAndMonitor", function ()
        M.upload_and_monitor()
    end, { desc = "Upload sketch then open serial monitor" })

    vim.api.nvim_create_user_command("ArduinoPort", function ()
        M.pick_port(function (board)
            vim.notify("Selected: " .. board.port, vim.log.levels.INFO)
            vim.b.arduino_port = board.port
            vim.b.arduino_fqbn = board.fqbn
            M.sync_sketch_yaml()
        end)
    end, { desc = "Pick USB port for ESP32" })

    vim.api.nvim_create_user_command("ArduinoChip", function ()
        M.pick_chip()
    end, { desc = "Set ESP32 chip type (ESP32, ESP32-C3, S2, S3, etc.)" })

    vim.api.nvim_create_user_command("ArduinoMonitorStop", function ()
        M.monitor_stop()
    end, { desc = "Stop serial monitor" })

    vim.api.nvim_create_user_command("ArduinoLibInstall", function (opts)
        M.lib_install(opts.args ~= "" and opts.args or nil)
    end, { nargs = "?", desc = "Install Arduino library by name" })

    vim.api.nvim_create_user_command("ArduinoLibSearch", function ()
        M.lib_search()
    end, { desc = "Search and install Arduino library" })

    vim.api.nvim_create_user_command("ArduinoLibAdd", function (opts)
        M.lib_add_to_project(opts.args ~= "" and opts.args or nil)
    end, { nargs = "?", desc = "Add library to project (.nvim_project.json) and install" })

    vim.api.nvim_create_user_command("ArduinoSyncSketchYaml", function ()
        M.sync_sketch_yaml()
        vim.notify("sketch.yaml updated for arduino-language-server.", vim.log.levels.INFO)
    end, { desc = "Write sketch.yaml (FQBN/port) for Arduino Language Server" })
end

return M
