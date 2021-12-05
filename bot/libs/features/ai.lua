local http = require("http")
local json = require("json")
local url = require("url")
local time = require("discordia").Time

local log = require("discordia").Logger(3, "%F %T")

local chat_history = {}
local chatting = false

local function char_to_hex(c)
    return string.format("%%%02X", string.byte(c))
end
  
local function urlencode(url)
    if url == nil then
        return
    end
    url = url:gsub("\n", "\r\n")
    url = url:gsub("([^%w _%%%-%.~])", char_to_hex)
    url = url:gsub(" ", "+")
    return url
end

return function(client) return {
    name = "AI",
    description = "Attempts to be a chattable bot",
    commands = {
        ["ai"] = {
            description = "Talk with the bot",
            exec = function(message)
                -- check if we are already chatting
                if chatting then
                    message:addReaction("⭕")
                    return
                end
                chatting = true

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

                -- sanity fixes
                if chat_history[message.guild.id] == nil then
                    chat_history[message.guild.id] = ""
                end

                -- generate context
                local context = chat_history[message.guild.id].."\n\n"..message.member.name..": "..message.content:gsub(";ai ", "", 1).."\nwozey:"
                log:log(3, "[ai] "..message.member.name.." said: "..message.content:gsub(";ai ", "", 1))

                -- stored response string
                local response = ""
                -- generate request
                local req = http.request({
                    hostname = "api.vicgalle.net",
                    port = 5000,
                    path = "/generate?token_max_length=512&temperature=1.0&top_p=0.8&stop_sequence=%0A&context="..urlencode(context),
                    method = "POST",
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
                        local json_response = json.parse(response)

                        if json_response.text == nil or json_response.text:match("^%s*(.-)%s*$") == "" then
                            message:addReaction("❌")
                            return
                        end

                        log:log(3, "[ai] wozey responds: "..json_response.text:match("^%s*(.-)%s*$"))
                        -- update chat history
                        chat_history[message.guild.id] = chat_history[message.guild.id].."\n\n"..message.member.name..": "..message.content:gsub(";ai ", "", 1).."\nwozey: "..json_response.text:match("^%s*(.-)%s*$")

                        message:reply({
                            content = json_response.text,
                            reference = { message = message, mention = false },
                        })

                        chatting = false
                    end))
                end)
                -- finish request
                req:done()
            end
        },
    },
    callbacks = {}
}end