-- ESP-IDF (idf.py): build, flash, monitor for C/C++ projects. Port: IDFPort picker or ArduinoPort.

local M = {}

M._monitor_job_id = nil

local function get_idf_root()
    local bufpath = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    local start_dir = (#bufpath > 0) and vim.fn.fnamemodify(bufpath, ":p:h") or vim.fn.getcwd()
    local found = vim.fs.find("CMakeLists.txt", { upward = true, path = start_dir })
    if found and found[1] then
        return vim.fn.fnamemodify(found[1], ":p:h")
    end
    return start_dir
end

-- Prefer IDF-chosen port (IDFPort), then Arduino port, then auto-detect.
local function get_port()
    local port = vim.b.idf_port
    if port and port ~= "" then
        return port
    end
    port = vim.b.arduino_port
    if port and port ~= "" then
        return port
    end
    local ok, arduino = pcall(require, "arduino")
    if ok and arduino and arduino.detect_esp32_port then
        local p = arduino.detect_esp32_port()
        if type(p) == "table" then return p.port end
        return p
    end
    return nil
end

function M.pick_port()
    local ok, arduino = pcall(require, "arduino")
    if not ok or not arduino or not arduino.board_list then
        vim.notify("Arduino module required for device list.", vim.log.levels.WARN)
        return
    end
    local boards, err = arduino.board_list()
    if err or not boards or #boards == 0 then
        vim.notify(err or "No boards found. Connect ESP32 via USB.", vim.log.levels.WARN)
        return
    end
    local items = {}
    for _, b in ipairs(boards) do
        table.insert(items, { value = b, label = b.port .. "  (" .. (b.name or b.fqbn or "") .. ")" })
    end
    vim.ui.select(items, {
        prompt = "Select device for IDF (flash/monitor):",
        format_item = function (item)
            return item.label
        end,
    }, function (choice)
        if choice then
            vim.b.idf_port = choice.port
            vim.notify("IDF port: " .. choice.port, vim.log.levels.INFO)
        end
    end)
end

function M.build()
    local root = get_idf_root()
    vim.notify("IDF build: " .. root .. " ...", vim.log.levels.INFO)
    vim.cmd("split")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.fn.termopen("cd " .. vim.fn.shellescape(root) .. " && idf.py build", {
        on_exit = function (_, code, _)
            vim.schedule(function ()
                if code == 0 then
                    vim.notify("IDF build OK", vim.log.levels.INFO)
                else
                    vim.notify("IDF build failed (exit " .. code .. ")", vim.log.levels.ERROR)
                end
            end)
        end,
    })
    vim.cmd("startinsert")
end

function M.flash(port)
    port = port or get_port()
    if not port or port == "" then
        vim.notify("No port. Use :IDFPort or :ArduinoPort to pick, or connect ESP32 via USB.", vim.log.levels.ERROR)
        return false
    end
    local root = get_idf_root()
    vim.notify("IDF flash to " .. port .. " ...", vim.log.levels.INFO)
    vim.cmd("split")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local cmd = "cd " .. vim.fn.shellescape(root) .. " && idf.py -p " .. vim.fn.shellescape(port) .. " flash"
    vim.fn.termopen(cmd, {
        on_exit = function (_, code, _)
            vim.schedule(function ()
                if code == 0 then
                    vim.notify("IDF flash OK", vim.log.levels.INFO)
                else
                    vim.notify("IDF flash failed (exit " .. code .. ")", vim.log.levels.ERROR)
                end
            end)
        end,
    })
    vim.cmd("startinsert")
    return true
end

function M.monitor(port)
    port = port or get_port()
    if not port or port == "" then
        vim.notify("No port. Use :IDFPort or :ArduinoPort to pick, or connect ESP32 via USB.", vim.log.levels.ERROR)
        return
    end
    local root = get_idf_root()
    local cmd = "cd " .. vim.fn.shellescape(root) .. " && idf.py -p " .. vim.fn.shellescape(port) .. " monitor"
    vim.cmd("split")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local job_id = vim.fn.termopen(cmd, {
        on_exit = function (_, _, _)
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
        vim.notify("IDF monitor stopped.", vim.log.levels.INFO)
    else
        M._monitor_job_id = nil
        vim.notify("No IDF monitor running.", vim.log.levels.INFO)
    end
end

function M.flash_and_monitor()
    local port = get_port()
    if not port or port == "" then
        vim.notify("No port. Use :IDFPort or :ArduinoPort to pick, or connect ESP32 via USB.", vim.log.levels.ERROR)
        return
    end
    local root = get_idf_root()
    vim.notify("IDF build, flash, monitor ...", vim.log.levels.INFO)
    vim.cmd("split")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local cmd = "cd " .. vim.fn.shellescape(root) .. " && idf.py -p " .. vim.fn.shellescape(port) .. " flash monitor"
    local job_id = vim.fn.termopen(cmd, {
        on_exit = function (_, _, _)
            M._monitor_job_id = nil
        end,
    })
    M._monitor_job_id = job_id
    vim.cmd("startinsert")
end

function M.register_commands()
    vim.api.nvim_create_user_command("IDFBuild", function ()
        M.build()
    end, { desc = "ESP-IDF: idf.py build" })

    vim.api.nvim_create_user_command("IDFFlash", function (opts)
        local port = opts.args ~= "" and opts.args or nil
        M.flash(port)
    end, { nargs = "?", desc = "ESP-IDF: idf.py flash to ESP32" })

    vim.api.nvim_create_user_command("IDFMonitor", function (opts)
        local port = opts.args ~= "" and opts.args or nil
        M.monitor(port)
    end, { nargs = "?", desc = "ESP-IDF: idf.py monitor (serial output)" })

    vim.api.nvim_create_user_command("IDFFlashAndMonitor", function ()
        M.flash_and_monitor()
    end, { desc = "ESP-IDF: build + flash + monitor (like Arduino Studio)" })

    vim.api.nvim_create_user_command("IDFMonitorStop", function ()
        M.monitor_stop()
    end, { desc = "ESP-IDF: stop serial monitor" })

    vim.api.nvim_create_user_command("IDFPort", function ()
        M.pick_port()
    end, { desc = "Pick USB port for IDF (flash/monitor); remembered per buffer" })
end

return M
