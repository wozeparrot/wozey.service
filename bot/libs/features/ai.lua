local http = require("http")
local json = require("json")
local uv = require("uv")
local ffi = require("ffi")

local log = require("discordia").Logger(3, "%F %T")

local ai_state = {}

local function ensure_state_exists(guild)
    if not ai_state[guild.id] then
        ai_state[guild.id] = {}
    end

    local running = coroutine.running()
    if not ai_state[guild.id].sock then
        ai_state[guild.id].sock = uv.new_tcp()
        ai_state[guild.id].sock:connect("127.0.0.1", 6768, function(err)
            if err then
                log:log(1, "failed to connect to compute server (Is it online?): %s", err)
                ai_state[guild.id].sock:shutdown()
                ai_state[guild.id].sock = nil
            end

            coroutine.resume(running)
        end)
        -- set tcp no delay
        ai_state[guild.id].sock:nodelay(true)
    end
    -- wait for the socket to connect
    coroutine.yield()
end

return function(client, state)
    return {
        name = "AI",
        description = "Extends the server with the POWER of AI",
        config_name = "ai",
        configs = {
            ["toxic_automod"] = false,
        },
        commands = {
            ["aivc"] = {
                description = "Talk with the bot in a voice channel",
                exec = function(message)
                    -- open a libuv socket to the compute server
                    ensure_state_exists(message.guild)
                    local sock = ai_state[message.guild.id].sock
                    if not sock then
                        message:addReaction("🛑")
                        return
                    end

                    if message.guild.connection then
                        message:reply({
                            embed = {
                                title = "AI - `aivc`",
                                description = "I'm already in a voice channel!",
                            },
                            reference = { message = message, mention = true },
                        })
                        return
                    end

                    local voice_channel = message.member.voiceChannel
                    if not voice_channel then
                        message:reply({
                            embed = {
                                title = "AI - `aivc`",
                                description = "You're not in a voice channel!",
                            },
                            reference = { message = message, mention = true },
                        })
                        return
                    end

                    local connection = voice_channel:join()
                    if not connection then
                        message:reply({
                            embed = {
                                title = "AI - `aivc`",
                                description = "I couldn't join the voice channel!",
                            },
                            reference = { message = message, mention = true },
                        })
                        return
                    end

                    -- subscribe to the voice data emitter
                    connection:on("userVoiceData", function(user, pcm)
                        if user == client.owner then
                            sock:write(ffi.string(pcm, 960 * 2 * 2))
                        end
                    end)

                    -- read from the socket for detected commands
                    sock:read_start(function(err, chunk)
                        assert(not err, err)

                        if chunk then
                            local data = json.parse(chunk)
                            if data then
                                if data["command"] == "play one" then
                                    coroutine.wrap(function()
                                        message.channel:send(";play hell clown core topic")
                                    end)()
                                elseif data["command"] == "play despacito" then
                                    coroutine.wrap(function()
                                        message.channel:send(";play despacito justin bieber audio")
                                    end)()
                                elseif data["command"] == "play three" then
                                    coroutine.wrap(function()
                                        message.channel:send(";play never gonna give you up")
                                    end)()
                                elseif data["command"] == "stop" then
                                    coroutine.wrap(function()
                                        message.channel:send(";stop stop")
                                    end)()
                                end
                            end
                        end
                    end)

                    -- subscribe to the leave event
                    connection:on("leftVoiceChannel", function(channel, _)
                        if channel ~= voice_channel then
                            return
                        end
                        sock:shutdown()
                        ai_state[message.guild.id].sock = nil
                    end)

                    -- need to send some data to get the callback to fire
                    connection:playPCM(
                        (function(freq, amp)
                            local h = freq * 2 * math.pi / 48000
                            local a = amp * 32767
                            local t = 0
                            return function()
                                local s = math.tan(t) * a
                                t = t + h
                                return s, s
                            end
                        end)(440, 1),
                        100
                    )
                end,
            },
            ["aivcs"] = {
                description = "Stop talking with the bot in a voice channel",
                exec = function(message)
                    if not message.guild.connection then
                        message:reply({
                            embed = {
                                title = "AI - `aivcs`",
                                description = "I'm not in a voice channel!",
                            },
                            reference = { message = message, mention = true },
                        })
                        return
                    end

                    ensure_state_exists(message.guild)
                    if ai_state[message.guild.id].sock then
                        ai_state[message.guild.id].sock:shutdown()
                        ai_state[message.guild.id].sock = nil
                    end
                    message.guild.connection:close()
                end,
            },
            ["ai"] = {
                description = "Talk with the bot",
                exec = function(message)
                    local args = message.content:split(" ")

                    if not args[2] then
                        message:reply({
                            embed = {
                                title = "AI - `ai`",
                                description = "You didn't say anything!",
                            },
                            reference = { message = message, mention = true },
                        })
                        return
                    end

                    -- generate post data
                    local post_data = json.stringify({
                        ["text"] = message.content:gsub(";ai ", "", 1),
                        ["user"] = message.member.name,
                        ["id"] = message.member.id,
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
                            ["Accept"] = "application/json",
                        },
                    }, function(res)
                        -- append to response string
                        res:on("data", function(chunk)
                            response = response .. chunk
                        end)
                        -- run stuff
                        res:on(
                            "end",
                            coroutine.wrap(function()
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

                                if message.guild.connection then
                                    message.guild.connection:playFFmpeg("compute/output.wav")
                                end
                            end)
                        )
                    end)
                    -- write post data
                    req:write(post_data)
                    -- finish request
                    req:done()

                    message.channel:broadcastTyping()
                end,
            },
            ["air"] = {
                description = "Reset chat history with the bot",
                exec = function(message)
                    -- generate post data
                    local post_data = json.stringify({
                        ["id"] = message.member.id,
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
                            ["Accept"] = "application/json",
                        },
                    }, function(res)
                    end)
                    -- write post data
                    req:write(post_data)
                    -- finish request
                    req:done()

                    message:addReaction("✅")
                end,
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
                            ["Accept"] = "application/json",
                        },
                    }, function(res)
                        -- append to response string
                        res:on("data", function(chunk)
                            response = response .. chunk
                        end)
                        -- run stuff
                        res:on(
                            "end",
                            coroutine.wrap(function()
                                -- parse returned json
                                local json_response = json.parse(response)
                                if json_response == nil then
                                    return
                                end

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
                            end)
                        )
                    end)
                    -- write post data
                    req:write(post_data)
                    -- finish request
                    req:done()
                end,
            },
        },
        callbacks = {
            ["messageCreate"] = function(message)
                -- don't do anything if this message wasn't sent in a guild
                if not message.guild then
                    return
                end

                -- don't do anything if this module is disabled
                if not state[message.guild.id].s.config.ai.toxic_automod then
                    return
                end

                -- don't do anything if its ourself
                if message.author == client.user then
                    return
                end
                if message.member == nil then
                    return
                end
                -- also don't do anything if its another bot
                if message.author.bot then
                    return
                end
                -- don't check on our own commands
                if message.content:sub(1, 1) == state[message.guild.id].s.config.global.prefix then
                    return
                end

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
                        ["Accept"] = "application/json",
                    },
                }, function(res)
                    -- append to response string
                    res:on("data", function(chunk)
                        response = response .. chunk
                    end)
                    -- run stuff
                    res:on(
                        "end",
                        coroutine.wrap(function()
                            -- parse returned json
                            local json_response = json.parse(response)
                            if json_response == nil then
                                return
                            end

                            if
                                json_response["severe_toxicity"] >= 0.7
                                or (json_response["toxicity"] >= 0.95 and json_response["obscene"] >= 0.8 and json_response["insult"] >= 0.8)
                                or (json_response["toxicity"] >= 0.85 and json_response["threat"] >= 0.85)
                            then
                                message:reply({
                                    content = "Whoa there! Thats really toxic. Can't have that around here!",
                                    reference = { message = message, mention = true },
                                })
                            else
                                if json_response["identity_attack"] >= 0.8 and json_response["toxicity"] >= 0.85 then
                                    message:reply({
                                        content = "Whoa there! Thats kinda bad. Can't have that around here!",
                                        reference = { message = message, mention = true },
                                    })
                                end
                            end
                        end)
                    )
                end)
                -- write post data
                req:write(post_data)
                -- finish request
                req:done()
            end,
        },
    }
end
