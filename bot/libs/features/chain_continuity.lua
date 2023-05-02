local message_chains = {}

return function(client, state)
	return {
		name = "Chain Continuity",
		description = "Continues message chains",
		config_name = "chain_continuity",
		configs = {
			["min_length"] = 3,
		},
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
				-- don't do anything if the message is empty
				if message.content == "" then
					return
				end

				if message_chains[message.channel.id] == nil then
					message_chains[message.channel.id] = {}
				end

				-- keep the chain at a limited size
				if #message_chains[message.channel.id] >= 3 then
					table.remove(message_chains[message.channel.id], 1)
				end

				table.insert(message_chains[message.channel.id], message.content:lower())

				-- don't do anything if we don't have enough messages
				if #message_chains[message.channel.id] < 3 then
					return
				end

				-- check if all messages are the same
				local same = true
				for _, old_message in ipairs(message_chains[message.channel.id]) do
					if old_message ~= message_chains[message.channel.id][1] then
						same = false
					end
				end

				-- continue the chain also flush the chain buffer
				if same then
					message_chains[message.channel.id] = {}

					-- 50% chance to not continue the chain
					if math.random(0, 100) < 50 then
						return
					end

					local funny_message = ""
					-- convert each letter of the message to uppercase or lowercase randomly
					for i = 1, #message.content do
						if math.random(0, 1) == 0 then
							funny_message = funny_message .. message.content:sub(i, i):upper()
						else
							funny_message = funny_message .. message.content:sub(i, i):lower()
						end
					end
					message.channel:send(funny_message)
				end
			end,
		},
	}
end
