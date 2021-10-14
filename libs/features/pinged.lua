local timer = require("timer")

local dead = {}
local enabled = {}

return function(client) return {
    name = "Pinged",
    description = "Yells at you if you ping the bot (disabled by default)",
    commands = {
        ["pinged"] = {
            description = "Sets pinged mode",
            owner_only = true,
            exec = function(message)
                local args = message.content:split(" ")

                if args[2] and (args[2] == "true" or args[2] == "false") then
                    if args[2] == "true" then
                        enabled[message.guild.id] = true
                    end
                    if args[2] == "false" then
                        enabled[message.guild.id] = false
                    end

                    message:reply({
                        embed = {
                            title = "Pinged",
                            description = "Set To: "..args[2],
                        },
                        reference = { message = message, mention = true }
                    })
                else
                    message:reply({
                        embed = {
                            title = "Pinged",
                            description = "Invalid State!"
                        },
                        reference = { message = message, mention = true }
                    })
                end
            end
        }
    },
    callbacks = {
        ["messageCreate"] = function(message)
            if not enabled[message.guild.id] then return end

            -- don't do anything if its ourself
            if message.author == client.user then return end
            if message.member == nil then return end

            -- don't do anything if the user is a bot
            if message.author.bot then return end

            -- if they are dead do not do anything
            if not dead[message.guild.id] then
                dead[message.guild.id] = {}
            end

            if dead[message.guild.id][message.member] then return end

            -- match for curly braces to search
            if message.mentionedUsers:find(function(a)
                return a == client.user
            end) then
                table.insert(dead[message.guild.id], message.member)
                coroutine.wrap(function()
                    message:reply({
                        content = "WHO HATH SUMMONED ME?"
                    })
                    timer.sleep(3000, coroutine.running())
                    message:reply({
                        content = "I SEE..."
                    })
                    timer.sleep(1700, coroutine.running())
                    message:reply({
                        content = "IT WAS YOU "..message.author.mentionString
                    })
                    timer.sleep(1700, coroutine.running())
                    message:reply({
                        content = "PREPARE TO DIE"
                    })
                    timer.sleep(2000, coroutine.running())

                    local count_msg = message:reply({
                        content = "3"
                    })
                    timer.sleep(1000, coroutine.running())   
                    count_msg:setContent("2")
                    timer.sleep(1000, coroutine.running())   
                    count_msg:setContent("1")
                    timer.sleep(1000, coroutine.running())   
                    
                    count_msg:setContent("YOU ARE DEAD NOW")
                    timer.setTimeout(30000, coroutine.wrap(function()
                        dead[message.guild.id] = nil
                        message:reply({
                            content = "I HAVE REVIVED YOU "..message.author.mentionString.."... DON'T PING ME AGAIN"
                        })
                    end))
                end)()
            end

            for i, m in ipairs(dead[message.guild.id]) do
                if m == message.member then
                    message:reply({
                        content = m.mentionString.." IS DEAD (from pinging "..client.user.mentionString..")",
                        reference = { message = message, mention = false }
                    })
                    message:delete()
                end
            end
        end
    }
}end
