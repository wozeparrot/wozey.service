return function(client, state)
    return {
        name = "Impersonation Blocker",
        description = "Blocks people from changing their name to impersonate another person",
        hidden = true,
        commands = {},
        callbacks = {
            ["memberUpdate"] = function(member)
                if member.user ~= client.owner then
                    if member.nickname ~= nil then
                        if string.match(member.nickname, client.owner.name) then
                            member:setNickname(nil)
                            member.user:send("You are not allowed to impersonate the bot owner!")
                        end
                    end
                end
            end,
        },
    }
end
