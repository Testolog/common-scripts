local opts = {
    ensure_installed = { "python", "help", "bash", "terraform", "c", "lua",  "query" },
    sync_install = false,
    auto_install = true,

    highlight = {
        disable = { "txt" },
        enable = true,
        additional_vim_regex_highlighting = false,
    },
}
return opts
