rockspec_format = "3.0"
package = "nvim_testolog"
version = "dev-1"
source = {
   url = "git+https://github.com/testolog/common-scripts"
}
description = {
   homepage = "https://github.com/testolog/common-scripts",
   license = "*** please specify a license ***"
}
-- config = {
--     variables = {
--         LINK_FLAGS="~/.luaver/lua/5.1/bin/lua"
--     }
-- }
build = {
   type = "builtin",
   modules = {
      commons = "lua/commons.lua",
      ["configs.catppuccin_opts"] = "lua/configs/catppuccin_opts.lua",
      ["configs.cmp_opts"] = "lua/configs/cmp_opts.lua",
      ["configs.gitsigns_opts"] = "lua/configs/gitsigns_opts.lua",
      ["configs.telescope_opts"] = "lua/configs/telescope_opts.lua",
      constants = "lua/constants.lua",
      keymapping = "lua/keymapping.lua",
      languages = "lua/languages.lua",
      main = "lua/main.lua",
      options = "lua/options.lua",
      ["plugins.langs"] = "lua/plugins/langs.lua",
      ["plugins.tools"] = "lua/plugins/tools.lua",
      ["plugins.ui"] = "lua/plugins/ui.lua",
      ["plugins.utility"] = "lua/plugins/utility.lua",
      system = "lua/system.lua"
   }
}
dependencies = {
    "lua-cjson",
    "luafilesystem"
    -- "toml"
}
