local table = require("table")
local common = {
    { "rafamadriz/friendly-snippets" },
}
local lua = {
    {
        "folke/lazydev.nvim",
        ft = "lua", -- only load on lua files
    },
    { "folke/neoconf.nvim", cmd = "Neoconf" },
    {
        "L3MON4D3/LuaSnip",
        dependencies = { "rafamadriz/friendly-snippets" },
        version = "2.*",
        build = "make install_jsregexp"
    }
}
local python = {

}
local java = {
    {
        'nvim-java/nvim-java',
    }
}

local rust = {
    {
        "mrcjkb/rustaceanvim",
        lazy = false
    }
}
local ls = {
    common, lua, python, java, rust
}
local res = {}
for _, elm in ipairs(ls) do
    for _, v in ipairs(elm) do
        table.insert(res, v)
    end
end
return res
