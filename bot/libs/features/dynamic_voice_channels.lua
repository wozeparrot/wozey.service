return function(client, state)
    return {
        name = "Dynamic Voice Channels",
        description = "Manages temporary voice channels",
        hidden = true,
        commands = {},
        callbacks = {
            ["voiceChannelJoin"] = function(user, channel)
                local guild = channel.guild
                local category = channel.category

                if category ~= nil then
                    if channel.name == "dcontrol" then
                        -- create new dynamic channel
                        local new_channel = guild:createVoiceChannel("dyn-" .. string.random(4, 65, 90))
                        new_channel:setCategory(category.id)
                        new_channel:moveDown()

                        -- set proper permissions on new_channel
                        category.permissionOverwrites:forEach(function(overwrite)
                            local new_channel_perms = new_channel:getPermissionOverwriteFor(overwrite:getObject())
                            new_channel_perms:setPermissions(
                                overwrite:getAllowedPermissions(),
                                overwrite:getDeniedPermissions()
                            )
                        end)

                        -- move user to new_channel
                        user:setVoiceChannel(new_channel.id)
                    end
                end
            end,
            ["voiceChannelLeave"] = function(user, channel)
                if #channel.connectedMembers == 0 then
                    if channel.name:sub(1, 4) == "dyn-" then
                        channel:delete()
                    end
                end
            end,
        },
    }
end
