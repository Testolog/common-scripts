local M = {}

M.treesitter = {
  lang = {
    "c", "lua", "vim", "vimdoc", "python", "query", "markdown", "markdown_inline",
    "xml", "java", "json", "yaml", "toml", "sql", "bash",
  },
}
M.not_attached_lsp = {
  "pyright", "ruff", "lua_ls", "rust_analyzer",
}
M.project_file_name = ".nvim_project.json"

return M
