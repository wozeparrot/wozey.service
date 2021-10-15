local https = require("https")
local json = require("json")

local chars = ("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):split("")

return function(client) return {
    name = "Polls",
    description = "Create polls that people can vote on",
    commands = {
        ["poll_create"] = {
            description = "Create a poll",
            exec = function(message)
                local title = message.content:gsub(";poll_create", "", 1)

                local poll_msg = message:reply({
                    embed = {
                        title = "Poll: "..title,
                    }
                })
                poll_msg:pin()
            end
        },
        ["poll_oadd"] = {
            description = "Add an option to a poll",
            exec = function(message)
                local option = message.content:gsub(";poll-oadd ", "", 1)

                -- get old poll message
                local poll_msg = message.channel:getPinnedMessages():find(function(a)
                    return a.author == client.user and a.embed
                end)

                if poll_msg then
                    -- generate new poll message
                    local fields = {}
                    if poll_msg.embed.fields then
                        for i, o in ipairs(poll_msg.embed.fields) do
                            table.insert(fields, {
                                name = "Option: "..chars[i],
                                value = o.value
                            })
                        end
                        table.insert(fields, {
                            name = "Option: "..chars[#poll_msg.embed.fields + 1],
                            value = option
                        })
                    else
                        table.insert(fields, {
                            name = "Option: A",
                            value = option
                        })
                    end
                    local new_poll_msg = poll_msg:reply({
                        embed = {
                            title = poll_msg.embed.title,
                            fields = fields
                        },
                        reference = { message = poll_msg, mention = false }
                    })
                    poll_msg:unpin()
                    new_poll_msg:pin()
                else
                    message:reply({
                        embed = {
                            title = "Poll - Option Add",
                            description = "Could not find poll"
                        },
                        reference = { message = poll_msg, mention = true }
                    })
                end
            end
        },
        ["poll_orem"] = {
            description = "Remove an option from a poll",
            exec = function(message)
                -- get old poll message
                local poll_msg = message.channel:getPinnedMessages():find(function(a)
                    return a.author == client.user and a.embed
                end)

                if poll_msg then
                else
                    message:reply({
                        embed = {
                            title = "Poll - Option Remove",
                            description = "Could not find poll"
                        },
                        reference = { message = poll_msg, mention = true }
                    })
                end
            end
        },
        ["poll_send"] = {
            description = "Send a poll into a chennel for voting",
            exec = function(message)
                local channel = message.mentionedChannels.first

                -- get old poll message
                local poll_msg = message.channel:getPinnedMessages():find(function(a)
                    return a.author == client.user and a.embed
                end)

                if poll_msg then
                    local new_poll_msg = channel:send({
                        embed = poll_msg.embed
                    })

                    poll_msg:unpin()
                    new_poll_msg:pin()
                else
                    message:reply({
                        embed = {
                            title = "Poll - Send",
                            description = "Could not find poll"
                        },
                        reference = { message = poll_msg, mention = true }
                    })
                end
            end
        }
    },
    callbacks = {}
}end
