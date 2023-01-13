local log = require("discordia").Logger(3, "%F %T")

local markov = require("systemd/markov")

return function(client, config)
    local chain = markov.new()

    local f = io.lines("markov.txt")
    for line in f do
        chain:learn(line)
    end

    return {
        name = "Chatbot",
        description = "Attempts to be a different chattable bot",
        commands = {
            ["chat"] = {
                description = "Talk with the bot",
                exec = function(message)
                    local args = message.content:split(" ")

                    if not args[2] then
                        message:reply({
                            embed = {
                                title = "Chatbot",
                                description = "You didn't say anything!",
                            },
                            reference = { message = message, mention = true },
                        })
                        return
                    end

                    local text = message.content:gsub(";chat ", "", 1)
                    log:log(3, "[chatbot] " .. message.member.name .. " said: " .. text)

                    chain:learn(text)

                    local response = chain:generate()

                    log:log(3, "[chatbot] wozey responds: " .. response)

                    message:reply({
                        content = response,
                        reference = { message = message, mention = false },
                    })
                end,
            },
        },
        callbacks = {
            ["messageCreate"] = function(message)
                -- don't do anything if this message wasn't sent in a guild
                if not message.guild then
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
                if message.content:sub(1, 1) == config.prefix then
                    return
                end

                log:log(3, "[chatbot] " .. message.member.name .. " said: " .. message.content)

                chain:learn(message.content)
            end,
        },
    }
end
