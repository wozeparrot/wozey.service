local https = require("https")
local json = require("json")

-- prestore query for lower mem usage
local query = [[
    query ($search: String) {
        Media (search: $search, type: MANGA) {
            title { romaji }
            description
            id
        }
    }
]]

return function(client) return {
    name = "Manga Linker",
    description = "Links to mentioned (wrap title with $[]) manga in chats",
    commands = {},
    callbacks = {
        ["messageCreate"] = function(message)
            -- don't do anything if its ourself
            if message.author == client.user then return end
            if message.member == nil then return end

            -- match for curly braces to search
            for match in message.content:gmatch("$%b{}") do
                if match ~= "${}" then
                    -- post data for api request
                    local post_data = json.stringify({
                        ["query"] = query,
                        ["variables"] = { search = match:gsub("{", ""):gsub("}", ""):gsub("$", "") }
                    })
                    -- stored response string
                    local response = ""
                    -- generate request
                    local req = https.request({
                        hostname = "graphql.anilist.co",
                        method = "POST",
                        headers = {
                            ["Content-Type"] = "application/json",
                            ["Content-Length"] = #post_data,
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
                            if json_response.errors then
                                message:addReaction("❌")
                                return
                            end
                            -- link
                            local manga = json_response.data.Media

                            if not manga.description then
                                manga.description = ""
                            end

                            message:reply({
                                embed = {
                                    title = manga.title.romaji,
                                    description = table.concat(table.slice(manga.description:split(" "), 1, 40, 1), " "):gsub("<br>", ""):gsub("<i>", "*"):gsub("</i>", "*").."...",
                                    url = "https://anilist.co/manga/"..manga.id,
                                    type = "image",
                                    image = { url = "https://img.anili.st/media/"..manga.id }
                                },
                                reference = { message = message, mention = false },
                            })
                        end))
                    end)
                    -- write post data
                    req:write(post_data)
                    -- finish request
                    req:done()
                end
            end
        end
    }
}end
