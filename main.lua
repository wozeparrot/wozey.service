local util = require('util')

local https = require('https')
local fs = require('fs')

local discordia = require('discordia')
local client = discordia.Client()

client:on('ready', function()
	print('Logged in as '.. client.user.username)
end)

client:on('messageCreate', function(message)
	-- don't do anything on our own messages
	if message.author == client.user then return end
    if message.member == nil then return end

	local content = message.content

	-- bot owner specific commands
	if message.author == client.owner then
	end
end)

client:on('voiceChannelJoin', function(user, channel)
	---dynamic voice channels---
	local guild = channel.guild
	local category = channel.category

	if category ~= nil then
		if channel.name == "dcontrol" then
			-- create new dynamic channel
			local new_channel = guild:createVoiceChannel("dyn-" .. util.rstring(4))
			new_channel:setCategory(category.id)
			new_channel:moveDown()
				
			-- set proper permissions on new_channel
			local category_perms = category:getPermissionOverwriteFor(guild.defaultRole)
			local new_channel_perms = new_channel:getPermissionOverwriteFor(guild.defaultRole)
			new_channel_perms:setPermissions(category_perms:getAllowedPermissions(), category_perms:getDeniedPermissions())

			-- move user to new_channel
			user:setVoiceChannel(new_channel.id)
		end
	end
end)

client:on('voiceChannelLeave', function(user, channel)
	-- delete empty dynamic voice channels
	if #channel.connectedMembers == 0 then
		if channel.name:sub(1, 4) == 'dyn-' then
			channel:delete()
		end
	end
end)

-- Main Function
local function main()
	local token_file = io.open(".token", "r")
	local token = token_file:read()
	token_file:close()
	client:run('Bot ' .. token)
end

main()
