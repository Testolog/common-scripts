local table = require("table")
local lua = {
    {
        "folke/lazydev.nvim",
        ft = "lua", -- only load on lua files
    },
    { "folke/neoconf.nvim", cmd = "Neoconf" },
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
    lua, python, java, rust
}
local res = {}
for _, elm in ipairs(ls) do
    for _, v in ipairs(elm) do
        table.insert(res, v)
    end
end
return res
