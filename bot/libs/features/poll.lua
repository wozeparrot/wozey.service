local https = require("https")
local json = require("json")

local chars = ("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):split("")
local reactions = {
    "🇦",
    "🇧",
    "🇨",
    "🇩",
    "🇪",
    "🇫",
    "🇬",
    "🇭",
    "🇮",
    "🇯",
    "🇰",
    "🇱",
    "🇲",
    "🇳",
    "🇴",
    "🇵",
    "🇶",
    "🇷",
    "🇸",
    "🇹",
    "🇺",
    "🇻",
    "🇼",
    "🇽",
    "🇾",
    "🇿"
}

return function(client, config) return {
        name = "Polls",
        description = "Create polls that people can vote on",
        required_perms = { 0x00002000 },
        commands = {
            ["poll_create"] = {
                description = "Create a poll",
                exec = function(message)
                    local title = message.content:gsub(";poll_create", "", 1)

                    local poll_msg = message:reply({
                        embed = {
                            title = "Poll: " .. title,
                        }
                    })
                    poll_msg:pin()
                end
            },
            ["poll_oadd"] = {
                description = "Add an option to a poll",
                exec = function(message)
                    local option = message.content:gsub(";poll_oadd ", "", 1)

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
                                    name = "Option: " .. chars[i],
                                    value = o.value,
                                    inline = true
                                })
                            end
                            table.insert(fields, {
                                name = "Option: " .. chars[#poll_msg.embed.fields + 1],
                                value = option,
                                inline = true
                            })
                        else
                            table.insert(fields, {
                                name = "Option: A",
                                value = option,
                                inline = true
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
                    local option = message.content:gsub(";poll_orem ", "", 1)

                    -- get old poll message
                    local poll_msg = message.channel:getPinnedMessages():find(function(a)
                        return a.author == client.user and a.embed
                    end)

                    if poll_msg then
                        local fields = {}
                        local adjusted_i = 1
                        for i, o in ipairs(poll_msg.embed.fields) do
                            if o.name:split("")[9] ~= option then
                                table.insert(fields, {
                                    name = "Option: " .. chars[adjusted_i],
                                    value = o.value,
                                    inline = true
                                })
                                adjusted_i = adjusted_i + 1
                            end
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
                                title = "Poll - Option Remove",
                                description = "Could not find poll"
                            },
                            reference = { message = poll_msg, mention = true }
                        })
                    end
                end
            },
            ["poll_curr"] = {
                description = "Link to the current poll",
                exec = function(message)
                    -- get old poll message
                    local poll_msg = message.channel:getPinnedMessages():find(function(a)
                        return a.author == client.user and a.embed
                    end)

                    if poll_msg then
                        local new_poll_msg = message.channel:send({
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
            },
            ["poll_send"] = {
                description = "Send a poll into a channel for voting",
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

                        for i, o in ipairs(poll_msg.embed.fields) do
                            new_poll_msg:addReaction(reactions[i])
                        end

                        poll_msg:unpin()
                        new_poll_msg:pin()

                        channel:getLastMessage():delete()
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
            },
        },
        callbacks = {}
    }
end
