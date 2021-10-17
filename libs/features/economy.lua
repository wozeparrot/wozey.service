local https = require("https")
local json = require("json")

return function(client) return {
    name = "Economy",
    description = "Fake money",
    commands = {
        ["money"] = {
            description = "Returns the amount of money you currently have",
            exec = function(message)
                local money_role = message.member.roles:find(function(a) a.name == "ᴥお金ᴥ" end)
                if money_role then
                    message:reply({
                        embed = {
                            title = "Economy - Money",
                            description = "You Currently Have: $"..tonumber(money_role.color:toHex(), 16)
                        }
                    })
                else
                    message:reply({
                        embed = {
                            title = "Economy - Money",
                            description = "You Currently Have: $0"
                        }
                    })
                end
            end
        }
    },
    callbacks = {}
}end
