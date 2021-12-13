local https = require("https")
local fs = require("fs")
local os = require("os")
local json = require("json")

local discordia = require("discordia")
discordia.extensions()
local client = discordia.Client()

-- CONFIG
local config = {
    prefix = ";",
    default = {},
}

-- FEATURES (Comment to disable globally)
local features = {
    require("features/linker")(client, config),
    require("features/weeb")(client, config),
    require("features/economy")(client, config),
    require("features/dynamic_voice_channels")(client, config),
    require("features/poll")(client, config),
    require("features/music")(client, config),
    require("features/ai")(client, config),
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

    if user == client.owner then return true else if command.owner_only then return false end end

    if command.required_perms then
        for i, perm in ipairs(command.required_perms) do
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
    -- register feature configs
    if feature.config_name ~= nil and feature.configs ~= nil then
        config.default[feature.config_name] = {}
        for key, value in pairs(feature.configs) do
            config.default[feature.config_name][key] = value
        end
    end

    -- register feature commands
    client:on('messageCreate', function(message)
        -- don't do anything if its ourself
        if message.author == client.user then return end
        if message.member == nil then return end
        -- also don't do anything if its another bot
        if message.author.bot then return end

        -- check if they can access the feature
        if not feature_visible_for_user(feature, message.member) then return end

        -- split into args
        local args = message.content:split(" ")

        -- find matching command
        if not args[1]:startswith(config.prefix) then return end
        local command = feature.commands[args[1]:gsub(config.prefix, "")]
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
    -- also don't do anything if its another bot
    if message.author.bot then return end

    local args = message.content:split(" ")

    if args[1] == config.prefix.."help" then
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
                        name = config.prefix..name,
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

-- data and config management
function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

local config_channels = {}
client:onSync("ready", function()
    for _, guild in pairs(client.guilds) do
        config[guild.id] = deepcopy(config.default)
        for _, channel in pairs(guild.textChannels) do
            if channel.name == "__wozey-data-store" then
                if channel.topic ~= nil and channel.topic ~= "" then
                    config[guild.id] = json.parse(channel.topic)
                end
                config_channels[guild.id] = channel
                break
            end
        end
    end
end)

client:on("messageCreate", function(message)
    -- don't do anything on our own messages
	if message.author == client.user then return end
    if message.member == nil then return end
    -- also don't do anything if its another bot
    if message.author.bot then return end

    if message.content == config.prefix.."default_config" then
        message:reply("```\n"..json.stringify(config.default).."\n```")
    end

    if message.content == config.prefix.."reload_config" then
        local channel = config_channels[message.guild.id]
        if channel.topic ~= nil and channel.topic ~= "" then
            config[message.guild.id] = json.parse(channel.topic)
        else
            config[message.guild.id] = {table.unpack(config.default)}
        end
        message:addReaction("✅")
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