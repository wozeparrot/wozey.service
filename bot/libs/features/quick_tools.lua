local log = require("discordia").Logger(3, "%F %T")

return function(client, state)
    return {
        name = "Quick Tools",
        description = "Simple stateless utility tools",
        config_name = "quick_tools",
        commands = {
            ["qt_bdel"] = {
                description = "Bulk delete messages",
                owner_only = true,
                exec = function(message)
                    local args = message.content:split(" ")

                    if not args[2] then
                        message:reply({
                            embed = {
                                title = "Bulk Delete",
                                description = "You didn't specify the amount of message to delete",
                            },
                            reference = { message = message, mention = true },
                        })
                        return
                    end

                    local count = tonumber(args[2])
                    message.channel:bulkDelete(message.channel:getMessagesBefore(message.id, count))
                    message:delete()
                end,
            },
        },
        callbacks = {},
    }
end
