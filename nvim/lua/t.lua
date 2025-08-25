-- local json = require("dkjson")
-- print(vim.env.LUA_PATH)
-- print(vim.env.VIMRUNTIME)
-- local person = {
--     name = "John Doe",
--     age = 30,
--     isEmployed = true
-- }
--
-- local jsonString = json.encode(person, { indent = true })
-- print(jsonString)
local cjson = require "cjson"
local function data()
    print("data")
end
data()
