return function(client) return {
    name = "Dynamic Voice Channels",
    description = "Manages temporary voice channels",
    commands = {
        "play" = {
            description = "queues a url for playback",
            exec = function(message) {
                message:reply("queued")
            }
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
