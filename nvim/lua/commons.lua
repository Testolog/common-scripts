-- trash place, where save everything, mb in future will refactor it for better
local const = require("constants")
local M = {}
M.border = function(hl_name)
    return {
        { "╭", hl_name },
        { "─", hl_name },
        { "╮", hl_name },
        { "│", hl_name },
        { "╯", hl_name },
        { "─", hl_name },
        { "╰", hl_name },
        { "│", hl_name },
    }
end

M.lsp_on_attach = function(client, bufnr)
    vim.api.nvim_set_option_value('omnifunc', 'v:lua.vim.lsp.omnifunc', { buf = bufnr })
end
M.contains = function(table, val)
    for i = 1, #table do
        if table[i] == val then
            return true
        end
    end
    return false
end

M.lua_libs_path = function(root, lua_version)
    local luarocks = vim.fn.join({ root, "lua_modules" }, "/")
    local share = vim.fn.join({ luarocks, "share", "lua", lua_version, }, "/")
    local lib = vim.fn.join({ luarocks, "lib", "lua", lua_version, }, "/")
    return {
        share = share,
        lib = lib
    }
end

M.tprint = function(tbl, indent)
    if tbl == nil then
        print("null")
    end
    if not indent then indent = 0 end
    local toprint = string.rep(" ", indent) .. "{\r\n"
    indent = indent + 2
    for k, v in pairs(tbl) do
        toprint = toprint .. string.rep(" ", indent)
        if (type(k) == "number") then
            toprint = toprint .. "[" .. k .. "] = "
        elseif (type(k) == "string") then
            toprint = toprint .. k .. "= "
        end
        if (type(v) == "number") then
            toprint = toprint .. v .. ",\r\n"
        elseif (type(v) == "string") then
            toprint = toprint .. "\"" .. v .. "\",\r\n"
        elseif (type(v) == "table") then
            toprint = toprint .. M.tprint(v, indent + 2) .. ",\r\n"
        else
            toprint = toprint .. "\"" .. tostring(v) .. "\",\r\n"
        end
    end
    toprint = toprint .. string.rep(" ", indent - 2) .. "}"
    return toprint
end

M.merge_table = function(base, semi)
    local result = {}
    if base == nil then
        return result
    end 
    for k, v in pairs(base) do
        result[k] = v
    end
    for k, v in pairs(semi) do
        if (type(v) == "table") then
            result[k] = M.merge_table(result[k], v)
        else
            result[k] = v
        end
    end
    return result
end


return M
