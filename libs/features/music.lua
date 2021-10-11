local uv = require("uv")
local yield, resume, running = coroutine.yield, coroutine.resume, coroutine.running
local fs = require("fs")
local path = require("path")

local queued = {}
local status = {}
local nexted = {}
local waitmu = {}

local function update_queue(guild)
    fs.mkdirSync("./wrun/"..guild)

    -- fetch current song
    if not fs.existsSync("./wrun/"..guild.."/music_curr.opus") then
        if queued[guild][1] and queued[guild][1].dl == 0 then
            queued[guild][1].dl = 2
            queued[guild][1].dl_handle = assert(uv.spawn("youtube-dl", {
                args = { "-x", "--audio-format", "opus", "--audio-quality", "0", "--no-playlist", "-o", "./wrun/"..guild.."/music_curr_pre.%(ext)s", queued[guild][1].url },
                stdio = { nil, 1, 2 }
            }, function(code, signal)
                if code == 0 and signal == 0 then
                    uv.close(queued[guild][1].dl_handle)
                    queued[guild][1].dl_handle = assert(uv.spawn("ffmpeg-normalize", {
                        args = { "-c:a", "libopus", "-b:a", "160k", "-t", "-18", "./wrun/"..guild.."/music_curr_pre.opus", "-o", "./wrun/"..guild.."/music_curr.opus" },
                        stdio = { nil, 1, 2 }
                    }, function(code, signal)
                        if code == 0 and signal == 0 then
                            uv.close(queued[guild][1].dl_handle)
                            os.execute("rm ./wrun/"..guild.."/music_curr_pre.opus")
                            queued[guild][1].dl = 1
                        end
                    end), "is ffmpeg-normalize installed and on $PATH?")
                end
            end), "is youtube-dl installed and on $PATH?")
        end
    end
    -- prefetch next song
    if not fs.existsSync("./wrun/"..guild.."/music_next.opus") then
        if queued[guild][2] and queued[guild][2].dl == 0 then
            queued[guild][2].dl = 2
            queued[guild][2].dl_handle = assert(uv.spawn("youtube-dl", {
                args = { "-x", "--audio-format", "opus", "--audio-quality", "0", "--no-playlist", "-o", "./wrun/"..guild.."/music_next_pre.%(ext)s", queued[guild][2].url },
                stdio = { nil, 1, 2 }
            }, function(code, signal)
                if code == 0 and signal == 0 then
                    uv.close(queued[guild][2].dl_handle)
                    queued[guild][2].dl_handle = assert(uv.spawn("ffmpeg-normalize", {
                        args = { "-c:a", "libopus", "-b:a", "160k", "-t", "-18", "./wrun/"..guild.."/music_next_pre.opus", "-o", "./wrun/"..guild.."/music_next.opus" },
                        stdio = { nil, 1, 2 }
                    }, function(code, signal)
                        if code == 0 and signal == 0 then
                            os.execute("rm ./wrun/"..guild.."/music_next_pre.opus")
                            queued[guild][2].dl = 1
                        end
                    end), "is ffmpeg-normalize installed and on $PATH?")
                end
            end), "is youtube-dl installed and on $PATH?")
        end
    end
end

local function next_song(guild, force)
    -- if there is no next song just reset to a clean state
    if not queued[guild][2] then
        if queued[guild][1].dl == 2 then
            uv.process_kill(queued[guild][1].dl_handle, "sigterm")
        end

        os.execute("rm -r ./wrun/"..guild)
        queued[guild] = nil
        nexted[guild] = false
        return
    end

    -- don't switch if we are still downloading the next song
    if queued[guild][2].dl ~= 1 and not force then
        return
    end

    -- force switch
    if force then
        if queued[guild][1].dl == 2 then
            uv.process_kill(queued[guild][1].dl_handle, "sigterm")
            queued[guild][1].dl = 0
        end
        if queued[guild][2].dl == 2 then
            uv.process_kill(queued[guild][2].dl_handle, "sigterm")
            queued[guild][2].dl = 0
        end

        -- remove curr and clean directory
        table.remove(queued[guild], 1)
        os.execute("rm -r ./wrun/"..guild)

        -- fetch new next
        update_queue(guild)

        return
    end

    -- move next to curr
    fs.renameSync("./wrun/"..guild.."/music_next.opus", "./wrun/"..guild.."/music_curr.opus")
    table.remove(queued[guild], 1)

    -- fetch new next
    update_queue(guild)
end

return function(client) return {
    name = "Music",
    description = "Plays music in voice channels",
    commands = {
        ["muq"] = {
            description = "queues a song for playback",
            exec = function(message)
                local args = message.content:split(" ")

                if args[2] then
                    -- spawn youtube-dl process
                    local stdout = uv.new_pipe(false)
                    local handle, pid = assert(uv.spawn("youtube-dl", {
                        args = { "-e", "--no-playlist", args[2] },
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

                    -- queue song
                    if title and title:trim() ~= "" then
                        if not queued[message.guild.id] then
                            queued[message.guild.id] = {}
                        end
                        table.insert(queued[message.guild.id], {
                            title = title,
                            url = args[2],
                            user = message.author.tag,
                            dl = 0,
                            dl_handle = nil
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
                    message:reply({
                        embed = {
                            title = "Music - List",
                            description = "No Music Queued!"
                        }
                    })
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
                    table.insert(fields, {
                        name = name,
                        value = "|"..song.dl.."| Requested By: "..song.user
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
        ["muc"] = {
            description = "Shows song in position #1 of the queue",
            exec = function(message)
                if not queued[message.guild.id] then
                    message:reply({
                        embed = {
                            title = "Music - Current",
                            description = "No Music Queued!"
                        }
                    })
                    return
                end

                message:reply({
                    embed = {
                        title = queued[message.guild.id][1].title,
                        description = "Requested By: "..queued[message.guild.id][1].user,
                        url = queued[message.guild.id][1].url
                    }
                })
            end
        },
        ["mup"] = {
            description = "Plays queued music",
            exec = function(message)
                -- set default loading music if not set yet
                if not waitmu[message.guild.id] then
                    waitmu[message.guild.id] = 1
                end

                if message.member.voiceChannel then
                    if not status[message.guild.id] then
                        local connection = message.member.voiceChannel:join()
                        coroutine.wrap(function ()
                            status[message.guild.id] = coroutine.running()
                            while status[message.guild.id] do
                                if queued[message.guild.id] and queued[message.guild.id][1].dl == 1 then
                                    -- play song
                                    connection:playFFmpeg("./wrun/"..message.guild.id.."/music_curr.opus")

                                    -- switch to next song
                                    if status[message.guild.id] then
                                        if nexted[message.guild.id] then
                                            next_song(message.guild.id, true)
                                        else
                                            next_song(message.guild.id, false)
                                        end
                                    else
                                        break
                                    end
                                else
                                    -- waiting for song to download
                                    if status[message.guild.id] then
                                        connection:playFFmpeg(uv.os_getenv("WOZEY_ROOT").."/assets/music_waiting_"..waitmu[message.guild.id]..".opus")
                                    else
                                        break
                                    end
                                end
                                nexted[message.guild.id] = false
                            end
                            connection:close()
                            status[message.guild.id] = nil
                        end)()
                    end
                else
                    message:reply({
                        embed = {
                            title = "Music - Play",
                            description = "Join a VC First!"
                        }
                    })
                end
            end
        },
        ["mus"] = {
            description = "Stops playing queued music",
            exec = function(message)
                if status[message.guild.id] then
                    status[message.guild.id] = nil
                    message.guild.connection:stopStream()
                else
                    message:reply({
                        embed = {
                            title = "Music - Stop",
                            description = "No Music Queued / No Music Playing!"
                        }
                    })
                end
            end
        },
        ["mun"] = {
            description = "Skips to next queued song",
            owner_only = true,
            exec = function(message)
                if status[message.guild.id] and queued[message.guild.id] then
                    nexted[message.guild.id] = true
                    message.guild.connection:stopStream()
                else
                    message:reply({
                        embed = {
                            title = "Music - Next",
                            description = "No Music Queued / No Music Playing!"
                        }
                    })
                end
            end
        },
        ["muw"] = {
            description = "Changes waiting music",
            owner_only = true,
            exec = function(message)
                local args = message.content:split(" ")

                if args[2] then
                    waitmu[message.guild.id] = args[2]

                    message:reply({
                        embed = {
                            title = "Music - Waiting",
                            description = "Changed Waiting Music To: "..args[2],
                        }
                    })
                else
                    message:reply({
                        embed = {
                            title = "Music - Waiting",
                            description = "Invalid Waiting Music!"
                        }
                    })
                end
            end
        }
    },
    callbacks = {
        ["voiceChannelLeave"] = function(user, channel)
	        if #channel.connectedMembers == 0 and channel.connection then
                channel.connection:close()
	        end
        end
    }
}end
