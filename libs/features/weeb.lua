local https = require("https")
local json = require("json")

return function(client) return {
    name = "Weeb",
    description = "Miscellaneous Weeb Stuff",
    commands = {
        ["animeq"] = {
            description = "Sends a random anime quote",
            exec = function(message)
                -- don't do anything if its ourself
                if message.author == client.user then return end
                if message.member == nil then return end

                -- stored response string
                local response = ""
                -- generate request
                local req = https.request("https://animechan.vercel.app/api/random", function(res)
                    -- append to response string
                    res:on("data", function(chunk)
                        response = response..chunk
                    end)
                    -- run stuff
                    res:on("end", coroutine.wrap(function()
                        -- parse returned json
                        local quote = json.parse(response)

                        message:reply({
                            embed = {
                                title = quote.character.." - "..quote.anime,
                                description = quote.quote
                            },
                            reference = { message = message, mention = false },
                        })
                    end))
                end)
                -- finish request
                req:done()
            end
        }
    },
    callbacks = {}
}end
