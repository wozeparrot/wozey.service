local uv = require("uv")
local yield, resume, running = coroutine.yield, coroutine.resume, coroutine.running
local fs = require("fs")

local queued = {}

local function file_exists(name)
   local f = io.open(name, "r")
   if f then
       f:close()
       return true
   else
       return false
   end
end

local function update_queue(guild)
    fs.mkdir("./wrun/"..guild)

    if not file_exists("./wrun/"..guild.."/curr.wav") then
        if queued[guild][1] then
            assert(uv.spawn("youtube-dl", {
                args = { "-x", "--audio-format", "wav", "-o", "./wrun/"..guild.."/music_curr.%(ext)s", queued[guild][1].url },
                stdio = { 0, 1, 2 }
            }, function()
                queued[guild][1].dl = true
            end), "spawning youtube-dl downloader failed")
        end
    end
    if not file_exists("./wrun/"..guild.."/next.wav") then
        if queued[guild][2] then
            assert(uv.spawn("youtube-dl", {
                args = { "-x", "--audio-format", "wav", "-o", "./wrun/"..guild.."/music_next.%(ext)s", queued[guild][2].url }
            }, function()
                queued[guild][2].dl = true
            end), "spawning youtube-dl downloader failed")
        end
    end
end

return function(client) return {
    name = "Music",
    description = "Plays music in voice channels",
    commands = {
        ["muq"] = {
            description = "queues a url for playback",
            exec = function(message)
                local args = message.content:split(" ")

                if args[2] then
                    -- spawn youtube-dl process
                    local stdout = uv.new_pipe(false)
                    local handle, pid = assert(uv.spawn("youtube-dl", {
                        args = { "-e", args[2] },
                        stdio = { 0, stdout, 2 }
                    }, function() end), "is youtube-dl installed and on $PATH?")

                    -- read title from stdout of youtube-dl
                    local title = ""
                    local thread = running()
                    stdout:read_start(function(err, data)
                        assert(not err, err)
                        if data then
                            title = title..data
                        else
                            return assert(resume(thread))
                        end
                    end)
                    yield()

                    if title and title:trim() ~= "" then
                        if not queued[message.guild.id] then
                            queued[message.guild.id] = {}
                        end
                        table.insert(queued[message.guild.id], {
                            title = title,
                            url = args[2],
                            user = message.author.tag,
                            dl = false
                        })

                        message:reply({
                            embed = {
                                title = "Music - Queued",
                                description = title,
                                url = args[2]
                            }
                        })

                        update_queue(message.guild.id)
                    else
                        message:reply({
                            embed = {
                                title = "Music",
                                description = "Invalid URL!"
                            }
                        })
                    end
                else
                    message:reply({
                        embed = {
                            title = "Music",
                            description = "Invalid URL!"
                        }
                    })
                end
            end
        },
        ["mul"] = {
            description = "Lists currently queued music",
            exec = function(message)
                if not queued[message.guild.id] then
                    return
                end

                -- generate fields for queued songs
                local fields = {}
                for i, song in ipairs(queued[message.guild.id]) do
                    local name = ""
                    if i == 1 then
                        name = "*) "..song.title
                    else
                        name = ")  "..song.title
                    end
                    local value = ""
                    if song.dl then
                        value = "<> Requested By: "..song.user
                    else
                        value = ">< Requested By: "..song.user
                    end
                    table.insert(fields, {
                        name = name,
                        value = value
                    })
                end

                message:reply({
                    embed = {
                        title = "Music - List",
                        fields = fields
                    }
                })
            end
        },
        ["mup"] = {
            description = "Plays queued music",
            exec = function(message)
            end
        },
        ["mus"] = {
            description = "Stops playing queued music",
            exec = function(message)
            end
        },
    },
    callbacks = {
        ["voiceChannelLeave"] = function(user, channel)
	        if #channel.connectedMembers == 0 and channel.connection then
                channel.connection:close()
	        end
        end
    }
}end
