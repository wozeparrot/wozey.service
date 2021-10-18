local timer = require("timer")
local Color = require("discordia").Color
local Time = require("discordia").Time
local Stopwatch = require("discordia").Stopwatch

local working = {}
local playing = {}

local function get_role(member)
    local role = member.roles:find(function(a) return a.name == "ᴥお金ᴥ" end)
    -- if the role exists return it
    if role then
        return role
    end

    -- create role
    role = member.guild:createRole("ᴥお金ᴥ")
    role:setColor(Color.fromHex("000000"))

    member:addRole(role)

    return role
end

local function get_money(role)
    return tonumber(role:getColor():toHex():gsub("#", ""), 16)
end

local function set_money(role, money)
    role:setColor(Color.fromHex(string.format("%x", money)))
end

local function get_bet(message)
    local args = message.content:split(" ")

    local bet = tonumber(args[2])
    if bet then
        if bet <= get_money(get_role(message.member)) then
            return bet
        else
            message:reply({
                embed = {
                    title = "Economy - Bet",
                    description = "You Don't Have Enough Money For This Bet!"
                },
                reference = { message = message, mention = true }
            })
        end
    else
        message:reply({
            embed = {
                title = "Economy - Bet",
                description = "Invalid Bet!"
            },
            reference = { message = message, mention = true }
        })
    end

    return nil
end

return function(client) return {
    name = "Economy",
    description = "Simulated server economy",
    commands = {
        ["money"] = {
            description = "Returns the amount of money you currently have",
            exec = function(message)
                local role = get_role(message.member)
                message:reply({
                    embed = {
                        title = "Economy - Money",
                        description = "You Currently Have: $"..get_money(role)
                    },
                    reference = { message = message, mention = true }
                })
            end
        },
        ["work"] = {
            description = "Gives you money after working for one hour",
            exec = function(message)
                if working[message.author.id] ~= nil then
                    message:reply({
                        embed = {
                            title = "Economy - Work",
                            description = "You are currently working for another "..(Time.fromHours(1) - working[message.author.id]:getTime()):toString().."!"
                        },
                        reference = { message = message, mention = true }
                    })
                    return
                end
                working[message.author.id] = Stopwatch()
                working[message.author.id]:start()

                local role = get_role(message.member)

                timer.setTimeout(Time.fromHours(1):toMilliseconds(), coroutine.wrap(function()
                    local gain = 150 + math.random(0, 100)
                    set_money(role, get_money(role) + gain)

                    message:reply({
                        embed = {
                            title = "Economy - Work",
                            description = "You worked for one hour and got: $"..gain
                        },
                        reference = { message = message, mention = true }
                    })

                    working[message.author.id] = nil
                end))

                message:reply({
                    embed = {
                        title = "Economy - Work",
                        description = "You are now working!"
                    },
                    reference = { message = message, mention = true }
                })
            end
        },
        ["dice"] = {
            description = "Gamble money on dice rolls",
            exec = function(message)
                local bet = get_bet(message)
                if not bet then return end

                if playing[message.author.id] then
                    message:reply({
                        embed = {
                            title = "Economy - Dice",
                            description = "You are already playing a game"
                        },
                        reference = { message = message, mention = true }
                    })
                    return
                end
                playing[message.author.id] = true

                local role = get_role(message.member)

                local user_roll1 = math.random(1, 6)
                local user_roll2 = math.random(1, 6)

                message:reply("You rolled a "..user_roll1.." and a "..user_roll2)

                timer.sleep(1000)

                local they_roll1 = math.random(1, 6)
                local they_roll2 = math.random(1, 6)

                message:reply("They rolled a "..they_roll1.." and a "..they_roll2)

                timer.sleep(1000)

                if user_roll1 + user_roll2 > they_roll1 + they_roll2 then
                    message:reply("You won: $"..bet.."!")
                    set_money(role, get_money(role) + bet)
                end
                if user_roll1 + user_roll2 == they_roll1 + they_roll2 then
                    message:reply("You tied! The bet has been returned!")
                end
                if user_roll1 + user_roll2 < they_roll1 + they_roll2 then
                    message:reply("You lost: $"..bet.."!")
                    set_money(role, get_money(role) - bet)
                end

                playing[message.author.id] = false
            end
        },
        ["ecr"] = {
            description = "Resets the economy",
            owner_only = true,
            exec = function(message)
                for role in message.guild.roles:findAll(function(a) return a.name == "ᴥお金ᴥ" end) do
                    role:delete()
                end
                message:addReaction("✅")
            end
        },
    },
    callbacks = {}
}end
