local http = require("http")
local json = require("json")
local url = require("url")
local timer = require("timer")

local log = require("discordia").Logger(3, "%F %T")

return function(client, config) return {
        name = "AI",
        description = "Attempts to be a chattable bot",
        config_name = "ai",
        configs = {
            ["toxic_automod"] = true,
        },
        commands = {
            ["ai"] = {
                description = "Talk with the bot",
                exec = function(message)
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
                        ["user"] = message.member.name,
                        ["id"] = message.member.id
                    })
                    log:log(3, "[ai] " .. message.member.name .. " said: " .. message.content:gsub(";ai ", "", 1))

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
                            response = response .. chunk
                        end)
                        -- run stuff
                        res:on("end", coroutine.wrap(function()
                            -- parse returned json
                            local json_response = json.parse(response)
                            if json_response == nil then
                                message:addReaction("🛑")
                                return
                            end

                            if json_response.reply == nil or json_response.reply == "" then
                                message:addReaction("❌")
                                return
                            end

                            log:log(3, "[ai] wozey responds: " .. json_response.reply)

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

                    message.channel:broadcastTyping()
                end
            },
            ["air"] = {
                description = "Reset chat history with the bot",
                exec = function(message)
                    -- generate post data
                    local post_data = json.stringify({
                        ["id"] = message.member.id
                    })

                    -- generate request
                    local req = http.request({
                        hostname = "localhost",
                        port = 6769,
                        path = "/reset_ch",
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
            ["dtoxic"] = {
                description = "Debugs the toxicity detector by printing out the scores for some text",
                exec = function(message)
                    -- generate post data
                    local post_data = json.stringify({
                        ["text"] = message.content:gsub(";dtoxic ", "", 1),
                        ["user"] = message.member.name,
                    })

                    local response = ""
                    -- generate request
                    local req = http.request({
                        hostname = "localhost",
                        port = 6769,
                        path = "/toxic",
                        method = "POST",
                        headers = {
                            ["Content-Type"] = "application/json",
                            ["Content-Length"] = #post_data,
                            ["Accept"] = "application/json"
                        },
                    }, function(res)
                        -- append to response string
                        res:on("data", function(chunk)
                            response = response .. chunk
                        end)
                        -- run stuff
                        res:on("end", coroutine.wrap(function()
                            -- parse returned json
                            local json_response = json.parse(response)
                            if json_response == nil then return end

                            local fields = {}
                            for label, score in pairs(json_response) do
                                table.insert(fields, {
                                    name = label,
                                    value = string.format("%f", score),
                                    inline = true,
                                })
                            end

                            message:reply({
                                embed = {
                                    fields = fields,
                                },
                                reference = { message = message, mention = true },
                            })
                        end))
                    end)
                    -- write post data
                    req:write(post_data)
                    -- finish request
                    req:done()
                end
            },
        },
        callbacks = {
            ["messageCreate"] = function(message)
                -- don't do anything if this module is disabled
                if not config[message.guild.id].ai.toxic_automod then return end

                -- don't do anything if its ourself
                if message.author == client.user then return end
                if message.member == nil then return end
                -- also don't do anything if its another bot
                if message.author.bot then return end
                -- don't check on our own commands
                if message.content:sub(1, 1) == config.prefix then return end

                -- TOXICITY DETECTOR
                -- generate post data
                local post_data = json.stringify({
                    ["text"] = message.content,
                    ["user"] = message.member.name,
                })

                local response = ""
                -- generate request
                local req = http.request({
                    hostname = "localhost",
                    port = 6769,
                    path = "/toxic",
                    method = "POST",
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["Content-Length"] = #post_data,
                        ["Accept"] = "application/json"
                    },
                }, function(res)
                    -- append to response string
                    res:on("data", function(chunk)
                        response = response .. chunk
                    end)
                    -- run stuff
                    res:on("end", coroutine.wrap(function()
                        -- parse returned json
                        local json_response = json.parse(response)
                        if json_response == nil then return end

                        if json_response["severe_toxicity"] >= 0.7 or
                            (
                            json_response["toxicity"] >= 0.95 and json_response["obscene"] >= 0.8 and
                                json_response["insult"] >= 0.8) or
                            (json_response["toxicity"] >= 0.85 and json_response["threat"] >= 0.85) then
                            message:reply({
                                content = "Whoa there! Thats really toxic. Can't have that around here!",
                                reference = { message = message, mention = true },
                            })
                        else if json_response["identity_attack"] >= 0.8 and json_response["toxicity"] >= 0.85 then
                                message:reply({
                                    content = "Whoa there! Thats kinda bad. Can't have that around here!",
                                    reference = { message = message, mention = true },
                                })
                            end
                        end
                    end))
                end)
                -- write post data
                req:write(post_data)
                -- finish request
                req:done()
            end
        }
    }
end
