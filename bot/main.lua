local fs = require("fs")
local os = require("os")
local json = require("json")
_G.json = json

--@type discordia
local discordia = require("discordia")
discordia.extensions()
local client = discordia.Client({
	bitrate = 128000,
	cacheAllMembers = true,
	gatewayIntents = 3276799,
	logLevel = 4,
})

local s = require("systemd/state")

-- STATE
local default_state = s.new()
default_state.s.config = {
	global = {
		prefix = ";",
	},
}
local state = {}

-- FEATURES (Comment to disable globally)
local features = {
	require("features/ai")(client, state),
	require("features/chatbot")(client, state),
	require("features/dynamic_voice_channels")(client, state),
	require("features/impersonation")(client, state),
	require("features/linker")(client, state),
	require("features/music_player")(client, state),
	require("features/poll")(client, state),
	require("features/proc")(client, state),
	require("features/quick_tools")(client, state),
	require("features/touch_grass")(client, state),
	require("features/weeb")(client, state),
	require("features/xkcd")(client, state),
}

-- MAIN
-- helper functions
local function feature_visible_for_user(feature, member)
	local user = member.user

	if feature.hidden then
		return false
	end

	if user == client.owner then
		return true
	else
		if feature.owner_only then
			return false
		end
	end

	if feature.required_perms then
		for _, perm in ipairs(feature.required_perms) do
			if not member:hasPermission(perm) then
				return false
			end
		end
	end

	return true
end

local function command_visible_for_user(command, member)
	local user = member.user

	if user == client.owner then
		return true
	else
		if command.owner_only then
			return false
		end
	end

	if command.required_perms then
		for _, perm in ipairs(command.required_perms) do
			if not member:hasPermission(perm) then
				return false
			end
		end
	end

	return true
end

local function get_feature_by_name(name)
	for _, feature in ipairs(features) do
		if feature.name:lower() == name:lower() then
			return feature
		end

		if feature.config_name ~= nil then
			if feature.config_name:lower() == name:lower() then
				return feature
			end
		end
	end

	return nil
end

-- load features
for _, feature in ipairs(features) do
	-- register feature configs
	if feature.config_name ~= nil and feature.configs ~= nil then
		default_state.s.config[feature.config_name] = {}
		for key, value in pairs(feature.configs) do
			default_state.s.config[feature.config_name][key] = value
		end
	end

	-- register feature commands
	client:on("messageCreate", function(message)
		-- must be a guild message
		if message.member == nil then
			return
		end
		-- also don't do anything if its another bot
		if message.author.bot and message.author ~= client.user then
			return
		end

		-- check if they can access the feature
		if not feature_visible_for_user(feature, message.member) then
			return
		end

		-- split into args
		local args = message.content:split(" ")

		-- find matching command
		local prefix = state[message.guild.id].s.config.global.prefix
		if not args[1]:startswith(prefix) then
			return
		end
		local command = feature.commands[args[1]:gsub(prefix, "")]
		if command then
			if command_visible_for_user(command, message.member) then
				command.exec(message)
			end
		end
	end)

	-- register feature callbacks
	for callback, fn in pairs(feature.callbacks) do
		client:on(callback, fn)
	end
end

-- help command
client:on("messageCreate", function(message)
	-- don't do anything on our own messages
	if message.author == client.user then
		return
	end
	-- must be a guild message
	if message.member == nil then
		return
	end
	-- also don't do anything if its another bot
	if message.author.bot then
		return
	end

	local args = message.content:split(" ")

	if args[1] == state[message.guild.id].s.config.global.prefix .. "help" then
		-- no feature specified so just list features
		if args[2] == nil then
			-- generate embed fields
			local fields = {}
			for _, feature in ipairs(features) do
				if feature_visible_for_user(feature, message.member) then
					local name = feature.name
					if feature.config_name ~= nil then
						name = name .. " (" .. feature.config_name .. ")"
					end
					table.insert(fields, {
						name = name,
						value = feature.description,
					})
				end
			end

			-- send message
			message:reply({
				embed = {
					title = "Help (Features)",
					description = "A list of all available features. Do ;help <feature> for feature specific help.",
					fields = fields,
				},
				reference = { message = message, mention = true },
			})
		else -- feature specified so print feature specific help
			local feature = get_feature_by_name(args[2])

			if feature == nil then
				message:reply({
					embed = {
						title = "Error",
						description = "Feature not found.",
					},
					reference = { message = message, mention = true },
				})
				return
			end

			-- generate embed fields
			local fields = {}
			for name, command in pairs(feature.commands) do
				if command_visible_for_user(command, message.member) then
					table.insert(fields, {
						name = state[message.guild.id].s.config.global.prefix .. name,
						value = command.description,
						inline = true,
					})
				end
			end

			message:reply({
				embed = {
					title = "Help (" .. feature.name .. ")",
					description = feature.description,
					fields = fields,
				},
				reference = { message = message, mention = true },
			})
		end
	end
end)

-- state management
client:onSync("ready", function()
	for _, guild in pairs(client.guilds) do
		state[guild.id] = s.new()
		state[guild.id]:decode(default_state:encode())

		for _, channel in pairs(guild.textChannels) do
			if channel.name == "__wozey" then
				if channel.topic ~= nil and channel.topid ~= "" then
					local root_msg = channel:getMessage(channel.topic)
					if root_msg ~= nil then
						local inital_state_message = channel:getMessage(root_msg.embed.fields[1].value)
						if inital_state_message ~= nil then
							state[guild.id]:decodeString(inital_state_message.content)
						end
					end
				end
				break
			end
		end
	end
end)

client:on("messageCreate", function(message)
	-- don't do anything on our own messages
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

	-- check if this is the __wozey channel
	if message.channel.name ~= "__wozey" then
		return
	end

	if message.content == state[message.guild.id].s.config.global.prefix .. "init" then
		if message.channel.topic == nil or message.channel.topic == "" then
			local root_msg = message.channel:send("uwu")
			message.channel:setTopic(root_msg.id)

			local encoded = state[message.guild.id]:encodeString()
			local inital_state_message = message.channel:send(encoded)

			root_msg:setEmbed({
				title = "wozey.service",
				description = "This is the root message for this server's wozey.service state. Do not delete this message. Do not change the channel topic.",
				fields = {
					{
						name = "Initial State Message",
						value = inital_state_message.id,
					},
				},
			})
			root_msg:setContent("")
		end

		message:delete()
	end
end)

-- main function
local function main()
	-- cleanup old runtime stuff
	os.execute("rm -r ./wrun")
	fs.mkdirSync("./wrun")

	-- run
	local token_file = io.open(".token", "r")
	if not token_file then
		print("No token file found. Please create a file called .token with your bot token in it.")
		return
	end
	local token = token_file:read()
	token_file:close()
	client:run("Bot " .. token)

	-- set some stuff
	client:setActivity("Send ;help...")
end

main()
