local https = require("https")
local fs = require("fs")
local os = require("os")

local discordia = require("discordia")
discordia.extensions()
local client = discordia.Client()

-- load features
local prefix = ";"
local features = {
    require("features/dynamic_voice_channels")(client),
    require("features/music")(client),
    require("features/anime")(client)
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
        if not args[1]:startswith(prefix) then return end
        local command = feature.commands[args[1]:gsub(prefix, "")]
        if command then
            if command.owner_only then
                if message.author == client.owner then
                    -- execute if found
                    command.exec(message)
                end
            else
                -- execute if found
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
	if message.author == client.user then return end
    if message.member == nil then return end

    if message.content == prefix.."help" then
        -- loop over features, one help embed per feature
        for i, feature in ipairs(features) do
            -- generate fields for commands
            local fields = {}
            for name, command in pairs(feature.commands) do
                if not command.owner_only then
                    table.insert(fields, {
                        name = prefix..name,
                        value = command.description
                    })
                else
                    if message.author == client.owner then
                        table.insert(fields, {
                            name = prefix..name.."*",
                            value = command.description
                        })
                    end
                end
            end

            message:reply({
                embed = {
                    title = feature.name,
                    description = feature.description,
                    fields = fields
                },
                reference = {message = message, mention = true},
            })
        end
    end
end)

-- Main Function
local function main()
    -- cleanup old runtime stuff
    os.execute("rm -r ./wrun")
    fs.mkdirSync("./wrun")

	local token_file = io.open(".token", "r")
	local token = token_file:read()
	token_file:close()
	client:run("Bot "..token)
end

main()
