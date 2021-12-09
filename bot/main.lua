local https = require("https")
local fs = require("fs")
local os = require("os")

local discordia = require("discordia")
discordia.extensions()
local client = discordia.Client()

-- load features
local prefix = ";"
local features = {
    require("features/pinged")(client),
    require("features/linker")(client),
    require("features/weeb")(client),
    require("features/economy")(client),
    require("features/dynamic_voice_channels")(client),
    require("features/poll")(client),
    require("features/music")(client),
    require("features/ai")(client)
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
            if command.owner_only or feature.owner_only then
                if message.author == client.owner then
                    -- execute if found
                    command.exec(message)
                end
            else
                if command.required_perms and message.author ~= client.owner then
                    for i, perm in ipairs(command.required_perms) do
                        if not message.member:hasPermission(perm) then
                            return
                        end
                    end
                end
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
            if not feature.hidden then
                if feature.owner_only then
                    if message.author == client.owner then
                        -- generate fields for commands
                        local fields = {}
                        for name, command in pairs(feature.commands) do
                            if not command.owner_only then
                                table.insert(fields, {
                                    name = prefix..name,
                                    value = command.description,
                                    inline = true
                                })
                            else
                                if message.author == client.owner then
                                    table.insert(fields, {
                                        name = prefix..name.."*",
                                        value = command.description,
                                        inline = true
                                    })
                                end
                            end
                        end

                        message:reply({
                            embed = {
                                title = feature.name.."*",
                                description = feature.description,
                                fields = fields
                            },
                            reference = { message = message, mention = true },
                        })
                    end
                else
                    if feature.required_perms and message.author ~= client.owner then
                        local has_perms = true
                        for i, perm in ipairs(feature.required_perms) do
                            if not message.member:hasPermission(perm) then
                                has_perms = false
                                break
                            end
                        end

                        if has_perms then
                            -- generate fields for commands
                            local fields = {}
                            for name, command in pairs(feature.commands) do
                                if not command.owner_only then
                                    table.insert(fields, {
                                        name = prefix..name,
                                        value = command.description,
                                        inline = true
                                    })
                                else
                                    if message.author == client.owner then
                                        table.insert(fields, {
                                            name = prefix..name.."*",
                                            value = command.description,
                                            inline = true
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
                                reference = { message = message, mention = true },
                            })
                        end
                    else
                        -- generate fields for commands
                        local fields = {}
                        for name, command in pairs(feature.commands) do
                            if not command.owner_only then
                                table.insert(fields, {
                                    name = prefix..name,
                                    value = command.description,
                                    inline = true
                                })
                            else
                                if message.author == client.owner then
                                    table.insert(fields, {
                                        name = prefix..name.."*",
                                        value = command.description,
                                        inline = true
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
                            reference = { message = message, mention = true },
                        })
                    end
                end
            end
        end
    end
end)

-- Main Function
local function main()
    -- cleanup old runtime stuff
    os.execute("rm -r ./wrun")
    fs.mkdirSync("./wrun")

	-- run
    local token_file = io.open(".token", "r")
	local token = token_file:read()
	token_file:close()
	client:run("Bot "..token)

    -- set some stuff
    client:setGame("Send ;help... UwU")
end

main()