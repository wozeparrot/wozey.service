local https = require('https')
local fs = require('fs')

local discordia = require('discordia')
discordia.extensions()
local client = discordia.Client()

-- load features
local prefix = "."
local features = {
    require('features/dynamic_voice_channels')
}

for i, feature in ipairs(features) do
    -- register feature commands
    client:on('messageCreate', function(message)
        -- don't do anything if its ourself
        if message.author == client.user then return end
        if message.member == nil then return end

        -- split into args
        local args = message.content:split(" ")

        -- find matching command
        local command = feature.commands[args[1]:gsub(prefix, "")]
        if command then
            -- execute if found
            command.exec(args:concat(" "))
        end
    end)

    -- register feature callbacks
    for callback, fn in pairs(feature.callbacks) do
        client:on(callback, fn)
    end
end

-- help command
client:on('messageCreate', function(message)
	-- don't do anything on our own messages
	if message.author == client.user then return end
    if message.member == nil then return end

    if message.content == prefix.."help" then
        message:reply("hi")
    end
end)

-- show when ready
client:on('ready', function()
	print('Logged in as '.. client.user.username)
end)

-- Main Function
local function main()
	local token_file = io.open(".token", "r")
	local token = token_file:read()
	token_file:close()
	client:run('Bot ' .. token)
end

main()
