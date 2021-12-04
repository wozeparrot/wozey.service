local http = require("https")
local json = require("json")
local url = require("url")
local time = require("discordia").Time

return function(client) return {
    name = "Weeb",
    description = "Miscellaneous Weeb Stuff",
    commands = {
        ["animeq"] = {
            description = "Sends a random anime quote",
            exec = function(message)
                -- don't do anything if its ourself
                if message.author == client.user then return end
                if message.member == nil then return end

                -- stored response string
                local response = ""
                -- generate request
                local req = http.get({
                    hostname = "animechan.vercel.app",
                    path = "/api/random",
                    method = "GET",
                    headers = {
                        ["Accept"] = "application/json"
                    },
                }, function(res)
                    -- append to response string
                    res:on("data", function(chunk)
                        response = response..chunk
                    end)
                    -- run stuff
                    res:on("end", coroutine.wrap(function()
                        -- parse returned json
                        local quote = json.parse(response)

                        message:reply({
                            content = "\""..quote.quote.."\" - "..quote.character.." ("..quote.anime..")",
                            reference = { message = message, mention = false },
                        })
                    end))
                end)
                -- finish request
                req:done()
            end
        },
        ["waifu"] = {
            description = "Sends a random pic of a waifu",
            exec = function(message)
                -- don't do anything if its ourself
                if message.author == client.user then return end
                if message.member == nil then return end

                -- stored response string
                local response = ""
                -- generate request
                local req = http.get({
                    hostname = "api.waifu.pics",
                    path = "/sfw/waifu",
                    method = "GET",
                    headers = {
                        ["Accept"] = "application/json"
                    },
                }, function(res)
                    -- append to response string
                    res:on("data", function(chunk)
                        response = response..chunk
                    end)
                    -- run stuff
                    res:on("end", coroutine.wrap(function()
                        -- parse returned json
                        local waifu = json.parse(response)

                        message:reply({
                            embed = {
                                type = "image",
                                image = {
                                    url = waifu.url
                                }
                            },
                            reference = { message = message, mention = false },
                        })
                    end))
                end)
                -- finish request
                req:done()
            end
        },
        ["animet"] = {
            description = "Attempts to find the source of an anime screenshot",
            exec = function(message)
                -- don't do anything if its ourself
                if message.author == client.user then return end
                if message.member == nil then return end

                local args = message.content:split(" ")
                if not args[2] then
                    message:reply({
                        embed = {
                            title = "Miscellaneous Weeb Stuff",
                            description = "Invalid Screenshot URL!"
                        },
                        reference = { message = message, mention = true }
                    })
                end

                -- stored response string
                local response = ""
                -- generate request
                local req = http.get({
                    hostname = "api.trace.moe",
                    path = "/search?anilistInfo&cutBorders&url="..args[2],
                    method = "GET",
                    headers = {
                        ["Accept"] = "application/json"
                    },
                }, function(res)
                    -- append to response string
                    res:on("data", function(chunk)
                        response = response..chunk
                    end)
                    -- run stuff
                    res:on("end", coroutine.wrap(function()
                        -- parse returned json
                        local json_response = json.parse(response)

                        -- if there is an error don't link it
                        if json_response.error ~= "" then
                            message:addReaction("❌")
                            return
                        end

                        local match = json_response.result[1]
                        -- check if match similarity is above 0.7
                        if match.similarity <= 0.7 then
                            message:addReaction("❌")
                            return
                        end
                        
                        local episode = 1
                        if match.episode ~= nil then
                            episode = match.episode
                        end

                        message:reply({
                            embed = {
                                title = match.anilist.title.romaji,
                                description = "Episode "..episode.." at "..time.fromSeconds(match.from):toString(),
                                url = "https://anilist.co/anime/"..match.anilist.id
                            },
                            reference = { message = message, mention = false },
                        })
                    end))
                end)
                -- finish request
                req:done()
            end
        }
    },
    callbacks = {}
}end
