local M = {}

local FORMAT_OPTIONS = {
    { value = "json", label = "JSON (jq)" },
    { value = "yaml", label = "YAML" },
    { value = "sql", label = "SQL" },
    { value = "python", label = "Python (ruff / pyproject.toml)" },
}

local SQL_DIALECTS = {
    { value = "bigquery", label = "Bigquery" },
    { value = "db2", label = "DB2" },
    { value = "db2i", label = "DB2i" },
    { value = "duckdb", label = "Duckdb" },
    { value = "hive", label = "Hive" },
    { value = "mariadb", label = "Mariadb" },
    { value = "mysql", label = "Mysql" },
    { value = "n1ql", label = "N1ql" },
    { value = "plsql", label = "PSSQL" },
    { value = "postgresql", label = "postgresql" },
    { value = "redshift", label = "Redshift" },
    { value = "spark", label = "Spark" },
    { value = "sqlite", label = "SQLite" },
    { value = "sql", label = "SQL" },
    { value = "tidb", label = "TiDB" },
    { value = "trino", label = "Trino" },
    { value = "transactsql", label = "Transact sql" },
    { value = "tsql", label = "TS sql" },
    { value = "singlestoredb", label = "Singlestore db" },
    { value = "snowflake", label = "Snowflake" },
}

local function get_range_text(bufnr, line1, line2)
    local lines = vim.api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false)
    return table.concat(lines, "\n")
end

local function set_range_text(bufnr, line1, line2, text)
    local start_row = line1 - 1
    local end_row = line2
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row, false)
    local end_col = #lines[#lines]
    local new_lines = vim.split(text, "\n", { plain = true })
    vim.api.nvim_buf_set_text(bufnr, start_row, 0, end_row - 1, end_col, new_lines)
end

local function format_json(text)
    local out = vim.fn.system({ "jq", "." }, text)
    if vim.v.shell_error ~= 0 then
        return nil, out or "jq failed"
    end
    return vim.trim(out)
end

local function format_yaml(text)
    local ok, out = pcall(vim.fn.system, { "yq", "-P" }, text)
    if ok and vim.v.shell_error == 0 and out and vim.trim(out) ~= "" then
        return vim.trim(out)
    end
    -- fallback: python yaml if available
    local py =
    "import yaml,sys; print(yaml.dump(yaml.safe_load(sys.stdin), default_flow_style=False, allow_unicode=True, sort_keys=False))"
    out = vim.fn.system({ "python3", "-c", py }, text)
    if vim.v.shell_error == 0 then
        return vim.trim(out)
    end
    return nil, out or "YAML format failed (install yq or python pyyaml)"
end

local function format_sql(text, dialect)
    dialect = dialect or "spark"
    local out = vim.fn.system({ "sql-formatter", "-l", dialect }, text)
    if vim.v.shell_error ~= 0 then
        return nil, out or "sql-formatter failed"
    end
    return vim.trim(out)
end

local function format_python(text, bufnr)
    local const = require("constants")
    local bufpath = vim.api.nvim_buf_get_name(bufnr)
    local start_dir = (#bufpath > 0) and vim.fn.fnamemodify(bufpath, ":p:h") or vim.fn.getcwd()
    local found = vim.fs.find(const.project_file_name, { upward = true, path = start_dir })
    local root = start_dir
    if found and found[1] then
        root = vim.fn.fnamemodify(found[1], ":p:h")
    end
    local out = vim.fn.system(
        { "sh", "-c", "cd " .. vim.fn.shellescape(root) .. " && ruff format --stdin-filename _stdin.py" },
        text
    )
    if vim.v.shell_error ~= 0 then
        return nil, out or "ruff format failed"
    end
    return vim.trim(out)
end

local formatters = {
    json = format_json,
    yaml = format_yaml,
    sql = format_sql,
    python = function (text, bufnr)
        return format_python(text, bufnr)
    end,
}

function M.run(bufnr, line1, line2)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    vim.cmd("wall")

    local text = get_range_text(bufnr, line1, line2)
    if not text or text == "" then
        vim.notify("Format selection: no text in range", vim.log.levels.WARN)
        return
    end

    vim.ui.select(
        FORMAT_OPTIONS,
        {
            prompt = "Format selection as:",
            format_item = function (item)
                return item.label
            end,
        },
        function (choice)
            if not choice then
                return
            end
            if choice.value == "sql" then
                vim.ui.select(
                    SQL_DIALECTS,
                    {
                        prompt = "SQL dialect:",
                        format_item = function (item)
                            return item.label
                        end,
                    },
                    function (dialect_choice)
                        if not dialect_choice then
                            return
                        end
                        local result, err = format_sql(text, dialect_choice.value)
                        if err then
                            vim.notify("Format selection (SQL " .. dialect_choice.label .. "): " .. err,
                                vim.log.levels.ERROR)
                            return
                        end
                        set_range_text(bufnr, line1, line2, result)
                        vim.notify("Formatted as SQL (" .. dialect_choice.label .. ")", vim.log.levels.INFO)
                    end
                )
                return
            end
            local fmt = formatters[choice.value]
            if not fmt then
                return
            end
            local result, err
            if choice.value == "python" then
                result, err = fmt(text, bufnr)
            else
                result, err = fmt(text)
            end
            if err then
                vim.notify("Format selection (" .. choice.label .. "): " .. err, vim.log.levels.ERROR)
                return
            end
            set_range_text(bufnr, line1, line2, result)
            vim.notify("Formatted as " .. choice.label, vim.log.levels.INFO)
        end
    )
end

return M
