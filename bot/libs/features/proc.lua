local log = require("discordia").Logger(3, "%F %T")
local enums = require("discordia").enums

return function(client, state)
    return {
        name = "Process Management",
        description = "Manages semi-permanent processes (chats)",
        config_name = "proc",
        commands = {
            ["proc_create"] = {
                description = "Create a new process",
                owner_only = true,
                exec = function(message)
                    local args = message.content:split(" ")

                    if not args[2] then
                        message:reply({
                            embed = {
                                title = "Process Create",
                                description = "You didn't specify the name of the process",
                            },
                            reference = { message = message, mention = true },
                        })
                        return
                    end

                    local name = args[2]

                    local category = message.guild:createCategory("/proc/" .. name)
                    -- remove read and connect permissions for everyone
                    local category_perms = category:getPermissionOverwriteFor(message.guild.defaultRole)
                    category_perms:denyPermissions(enums.permission.readMessages)
                    category_perms:denyPermissions(enums.permission.connect)

                    category:moveDown(10000)
                    category:moveUp(1)

                    local channel = category:createTextChannel("mem")
                    local channel_perms = channel:getPermissionOverwriteFor(message.guild.defaultRole)
                    channel_perms:denyPermissions(enums.permission.readMessages)

                    channel = category:createVoiceChannel("fd/1")
                    channel_perms = channel:getPermissionOverwriteFor(message.guild.defaultRole)
                    channel_perms:denyPermissions(enums.permission.connect)

                    message:addReaction("✅")
                end,
            },
            ["proc_delete"] = {
                description = "Delete a process",
                owner_only = true,
                exec = function(message)
                    local args = message.content:split(" ")

                    if not args[2] then
                        message:reply({
                            embed = {
                                title = "Process Delete",
                                description = "You didn't specify the name of the process",
                            },
                            reference = { message = message, mention = true },
                        })
                        return
                    end

                    local name = args[2]

                    local category = message.guild.categories:find(function(c)
                        return c.name == "/proc/" .. name
                    end)

                    if not category then
                        message:reply({
                            embed = {
                                title = "Process Delete",
                                description = "Process not found",
                            },
                            reference = { message = message, mention = true },
                        })
                        return
                    end

                    for _, channel in pairs(category.textChannels) do
                        channel:delete()
                    end

                    for _, channel in pairs(category.voiceChannels) do
                        channel:delete()
                    end

                    category:delete()

                    message:addReaction("✅")
                end,
            },
        },
        callbacks = {},
    }
end
