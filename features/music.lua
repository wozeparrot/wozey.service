return function(client) return {
    name = "Music",
    description = "Plays music in voice channels",
    commands = {
        ["play"] = {
            description = "queues a url for playback",
            exec = function(message)
                message:reply("queued")
            end
        }
    },
    callbacks = {
        ["voiceChannelLeave"] = function(user, channel)
	        if #channel.connectedMembers == 0 and channel.connection then
                channel.connection:close()
	        end
        end
    }
}end
