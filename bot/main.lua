local https = require("https")
local fs = require("fs")
local os = require("os")

local discordia = require("discordia")
discordia.extensions()
local client = discordia.Client()

-- CONFIG
local prefix = ";"
local features = {
    require("features/linker")(client),
    require("features/weeb")(client),
    require("features/economy")(client),
    require("features/dynamic_voice_channels")(client),
    require("features/poll")(client),
    require("features/music")(client),
    require("features/ai")(client)
}

-- MAIN
-- helper functions
local function feature_visible_for_user(feature, member)
    local user = member.user

    if feature.hidden then return false end

    if user == client.owner then return true else if feature.owner_only then return false end end

    if feature.required_perms then
        for i, perm in ipairs(feature.required_perms) do
            if not member:hasPermission(perm) then
                return false
            end
        end
    end

    return true
end

local function command_visible_for_user(command, member)
    local user = member.user

    if command.required_perms then
        for i, pem in ipairs(command.required_perms) do
            if not member:hasPermission(perm) then
                return false
            end
        end
    end

    return true
end

local function get_feature_by_name(name)
    for i, feature in ipairs(features) do
        if feature.name:lower() == name:lower() then
            return feature
        end
    end

    return nil
end

-- load features
for i, feature in ipairs(features) do
    -- register feature commands
    client:on('messageCreate', function(message)
        -- don't do anything if its ourself
        if message.author == client.user then return end
        if message.member == nil then return end

        -- check if they can access the feature
        if not feature_visible_for_user(feature, message.member) then return end

        -- split into args
        local args = message.content:split(" ")

        -- find matching command
        if not args[1]:startswith(prefix) then return end
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
	if message.author == client.user then return end
    if message.member == nil then return end

    local args = message.content:split(" ")

    if args[1] == prefix.."help" then
        -- no feature specified so just list features
        if args[2] == nil or get_feature_by_name(args[2]) == nil then
            -- generate embed fields
            local fields = {}
            for i, feature in ipairs(features) do
                if feature_visible_for_user(feature, message.member) then
                    table.insert(fields, {
                        name = feature.name,
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

            -- generate embed fields
            local fields = {}
            for name, command in pairs(feature.commands) do
                if command_visible_for_user(command, message.member) then
                    table.insert(fields, {
                        name = prefix..name,
                        value = command.description,
                        inline = true,
                    })
                end
            end

            message:reply({
                embed = {
                    title = "Help ("..feature.name..")",
                    description = feature.description,
                    fields = fields,
                },
                reference = { message = message, mention = true },
            })
        end
    end
end)

-- main function
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