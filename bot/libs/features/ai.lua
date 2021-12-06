local http = require("http")
local json = require("json")
local url = require("url")
local time = require("discordia").Time

local log = require("discordia").Logger(3, "%F %T")

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

                local args = message.content:split(" ")

                if not args[2] then
                    message:reply({
                        embed = {
                            title = "AI",
                            description = "You didn't say anything!"
                        },
                        reference = { message = message, mention = true }
                    })
                    return
                end

                -- generate post data
                local post_data = json.stringify({
                    ["text"] = message.content:gsub(";ai ", "", 1),
                    ["id"] = message.member.id
                })
                log:log(3, "[ai] "..message.member.name.." said: "..message.content:gsub(";ai ", "", 1))

                -- stored response string
                local response = ""
                -- generate request
                local req = http.request({
                    hostname = "localhost",
                    port = 6769,
                    path = "/chat",
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
                        if json_response == nil then
                            message:addReaction("🛑")
                            return
                        end
                        
                        if json_response.error then
                            if json_response.error == "fr" then
                                message:addReaction("⚪")
                                return
                            end
                        end

                        if json_response.reply == nil or json_response.reply == "" then
                            message:addReaction("❌")
                            return
                        end

                        log:log(3, "[ai] wozey responds: "..json_response.reply)

                        message:reply({
                            content = json_response.reply,
                            reference = { message = message, mention = false },
                        })
                    end))
                end)
                -- write post data
                req:write(post_data)
                -- finish request
                req:done()
            end
        },
        ["air"] = {
            description = "Reset chat history with the bot",
            exec = function(message)
                -- don't do anything if its ourself
                if message.author == client.user then return end
                if message.member == nil then return end

                -- generate post data
                local post_data = json.stringify({
                    ["id"] = message.member.id
                })

                -- generate request
                local req = http.request({
                    hostname = "localhost",
                    port = 6769,
                    path = "/reset",
                    method = "POST",
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["Content-Length"] = #post_data,
                        ["Accept"] = "application/json"
                    },
                }, function(res) end)
                -- write post data
                req:write(post_data)
                -- finish request
                req:done()

                message:addReaction("✅")
            end
        },
    },
    callbacks = {}
}end