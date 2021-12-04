local https = require("https")
local json = require("json")

return function(client) return {
    name = "Weeb",
    description = "Miscellaneous Weeb Stuff",
    commands = {
        ["animeq"] = {
            description = "Sends a random anime quote",
            exec = function(message)
                -- stored response string
                local response = ""
                -- generate request
                local req = https.request({
                    hostname = "animechan.vercel.app/api/random",
                    method = "GET",
                    headers = {
                        ["Accept"] = "application/json"
                    },
                }, function(res)
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
