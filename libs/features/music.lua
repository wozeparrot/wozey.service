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
                        args = { "-c:a", "libopus", "-b:a", "128k", "./wrun/"..guild.."/music_curr_pre.opus", "-o", "./wrun/"..guild.."/music_curr.opus" },
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
                        args = { "-c:a", "libopus", "-b:a", "128k", "./wrun/"..guild.."/music_next_pre.opus", "-o", "./wrun/"..guild.."/music_next.opus" },
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
            uv.process_kill(queued[guild][1].dl_handle, "sigkill")
            queued[guild][1].dl = 0
        end
        if queued[guild][2].dl == 2 then
            uv.process_kill(queued[guild][2].dl_handle, "sigkill")
            queued[guild][2].dl = 0
        end

        -- remove curr and switch to next
        table.remove(queued[guild], 1)
        if queued[guild][1].dl == 1 then
            fs.renameSync("./wrun/"..guild.."/music_next.opus", "./wrun/"..guild.."/music_curr.opus")
        else
            queued[guild][1].dl = 0
            os.execute("rm -r ./wrun/"..guild)
        end

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
        ["queue"] = {
            description = "queues a song for playback",
            exec = function(message)
                local args = message.content:split(" ")

                if args[2] then
                    local url = message.content:gsub(";queue ", "", 1):gsub("<", ""):gsub(">", "")

                    -- spawn youtube-dl process
                    local stdout = uv.new_pipe(false)
                    local handle, pid = assert(uv.spawn("youtube-dl", {
                        args = { "-e", "--no-playlist", url },
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
                            url = url,
                            user = message.author.tag,
                            message = message,
                            dl = 0,
                            dl_handle = nil
                        })

                        message:reply({
                            embed = {
                                title = "Music - Queued",
                                description = title,
                                fields = {
                                    {
                                        name = "Requested By",
                                        value = message.author.tag
                                    }
                                }
                            },
                            reference = { message = message, mention = true }
                        })

                        update_queue(message.guild.id)
                    else
                        message:reply({
                            embed = {
                                title = "Music",
                                description = "Invalid URL!"
                            },
                            reference = { message = message, mention = true }
                        })
                    end
                else
                    message:reply({
                        embed = {
                            title = "Music",
                            description = "Invalid URL!"
                        },
                        reference = { message = message, mention = true }
                    })
                end
            end
        },
        ["list"] = {
            description = "Lists currently queued music",
            exec = function(message)
                if not queued[message.guild.id] then
                    message:reply({
                        embed = {
                            title = "Music - List",
                            description = "No Music Queued!"
                        },
                        reference = { message = message, mention = true }
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
                    },
                    reference = { message = message, mention = true }
                })
            end
        },
        ["np"] = {
            description = "Shows curently playing song",
            exec = function(message)
                if not queued[message.guild.id] or queued[message.guild.id][1].dl ~= 1 then
                    message:reply({
                        embed = {
                            title = "Music - Current",
                            description = "Waiting Music While Next Song Loads",
                            fields = {
                                {
                                    name = "Requested By",
                                    value = client.user.tag
                                }
                            }
                        },
                        reference = { message = message, mention = true }
                    })
                else
                    message:reply({
                        embed = {
                            title = "Music - Current",
                            description = queued[message.guild.id][1].title,
                            fields = {
                                {
                                    name = "Requested By",
                                    value = queued[message.guild.id][1].user
                                }
                            }
                        },
                        reference = { message = message, mention = true }
                    })
                end
            end
        },
        ["play"] = {
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
                                    -- send now playing message
                                    message:reply({
                                        embed = {
                                            title = "Music - Now Playing",
                                            description = queued[message.guild.id][1].title,
                                            fields = {
                                                {
                                                    name = "Requested By",
                                                    value = queued[message.guild.id][1].user
                                                }
                                            }
                                        },
                                        reference = { message = queued[message.guild.id][1].message, mention = false },
                                    })

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
                                        local f = io.open(uv.os_getenv("WOZEY_ROOT").."/assets/music_waiting_"..waitmu[message.guild.id]..".wav", "rb")
                                        f:seek("set", 44)
                                        connection:playPCM(f:read("*a"))
                                        --connection:playFFmpeg(uv.os_getenv("WOZEY_ROOT").."/assets/music_waiting_"..waitmu[message.guild.id]..".opus")
                                    else
                                        break
                                    end

                                    if status[message.guild.id] and nexted[message.guild.id] then
                                        next_song(message.guild.id, true)
                                    end
                                end
                                nexted[message.guild.id] = false
                            end
                            connection:close()
                            status[message.guild.id] = nil
                        end)()
                    else
                        message:reply({
                            embed = {
                                title = "Music - Play",
                                description = "Already Playing Music!"
                            },
                            reference = { message = message, mention = true }
                        })
                    end
                else
                    message:reply({
                        embed = {
                            title = "Music - Play",
                            description = "Join a VC First!"
                        },
                        reference = { message = message, mention = true }
                    })
                end
            end
        },
        ["stop"] = {
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
                        },
                        reference = { message = message, mention = true }
                    })
                end
            end
        },
        ["resume"] = {
            description = "Resume previously playing music",
            exec = function(message)
                if status[message.guild.id] then
                    message.guild.connection:resumeStream()
                else
                    message:reply({
                        embed = {
                            title = "Music - Resume",
                            description = "No Music Playing!"
                        },
                        reference = { message = message, mention = true }
                    })
                end
            end
        },
        ["pause"] = {
            description = "Pauses currently playing music",
            exec = function(message)
                if status[message.guild.id] then
                    message.guild.connection:pauseStream()
                else
                    message:reply({
                        embed = {
                            title = "Music - Pause",
                            description = "No Music Playing!"
                        },
                        reference = { message = message, mention = true }
                    })
                end
            end
        },
        ["next"] = {
            description = "Skips to next queued song",
            exec = function(message)
                if queued[message.guild.id] then
                    nexted[message.guild.id] = true
                    message.guild.connection:stopStream()
                else
                    message:reply({
                        embed = {
                            title = "Music - Next",
                            description = "No Music Queued!"
                        },
                        reference = { message = message, mention = true }
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
                        },
                        reference = { message = message, mention = true }
                    })
                else
                    message:reply({
                        embed = {
                            title = "Music - Waiting",
                            description = "Invalid Waiting Music!"
                        },
                        reference = { message = message, mention = true }
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
