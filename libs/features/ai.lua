local http = require("https")
local json = require("json")
local url = require("url")
local time = require("discordia").Time

local chat_history = {}

return function(client) return {
    name = "AI",
    description = "Attempts to be a chattable bot",
    commands = {
        ["ai"] = {
            description = "Talk with the bot",
            exec = function(message)
                -- don't do anything if its ourself
                if message.author == client.user then return end
                if message.member == nil then return end

                if not args[2] then
                    message:reply({
                        embed = {
                            title = "AI",
                            description = "You didn't say anything!"
                        },
                        reference = { message = message, mention = true }
                    })
                    return
                }

                -- some sanity fixes
                if chat_history[message.guild.id] == nil then
                    chat_history[message.guild.id] = {}
                end
                if chat_history[message.guild.id][message.member.id] == nil then
                    chat_history[message.guild.id][message.member.id] = ""
                end

                -- generate post data
                local context = chat_history[message.guild.id][message.member.id].."\n\nPerson: "..args[2].."\nwozey: "
                local post_data = json.stringify({
                    ["context"] = context,
                    ["token_max_length"] = 128,
                    ["temperature"] = 0.8,
                    ["top_p"] = 1.0,
                    ["stop_sequence"] = "\n"
                })

                -- stored response string
                local response = ""
                -- generate request
                local req = http.request({
                    hostname = "api.vicgalle.net",
                    port = 5000,
                    path = "/generate",
                    method = "POST",
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["Content-Length"] = #post_data,
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
                        local json_response = json.parse(response)

                        if json_response.text == nil then
                            message:addReaction("❌")
                            return
                        end

                        message:reply({
                            content = json_response.text,
                            reference = { message = message, mention = false },
                        })
                    end))
                end)
                -- write post data
                req:write(post_data)
                -- finish request
                req:done()
            end
        }
    },
    callbacks = {}
}end
