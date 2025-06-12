local java = require('java')
local lspconfig = require('lspconfig')
java.setup {
    jdk = {
        -- install jdk using mason.nvim
        auto_install = false,
    }
}
lspconfig.jdtls.setup {
    settings = {
        java = {
            configuration = {
                runtimes = {
                    {
                        name = "11",
                        path = "/Users/rnad/Library/Java/JavaVirtualMachines/corretto-11.0.25/Contents/Home",
                        default = true,
                    },
                    {
                        name = "17",
                        path = "/opt/homebrew/Cellar/openjdk@17/17.0.14",
                        default = false,
                    },
                    {
                        name = "21",
                        path = "/opt/homebrew/Cellar/openjdk@21/21.0.6",
                        default = false,
                    }
                }
            }
        }
    }
}
