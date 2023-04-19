return function(client, state)
	return {
		name = "Touch Grass",
		description = "Tells people to touch grass",
		hidden = true,
		commands = {},
		callbacks = {
			["messageCreate"] = function(message)
				-- don't do anything if its ourself
				if message.author == client.user then
					return
				end
				if message.member == nil then
					return
				end
				-- also don't do anything if its another bot
				if message.author.bot then
					return
				end
				-- don't check on our own commands
				if message.content:sub(1, 1) == state[message.guild.id].s.config.global.prefix then
					return
				end

				-- check if message contains "touch grass" or "touching grass"
				if message.content:lower():find("touch grass") or message.content:lower():find("touching grass") then
					-- send message
					message:reply({
						content = "https://cdn.discordapp.com/attachments/966039307536175174/1086036941293752330/grass.mov",
						reference = { message = message, mention = false },
					})
				end
			end,
		},
	}
end
