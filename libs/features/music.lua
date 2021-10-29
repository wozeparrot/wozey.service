local uv = require("uv")
local yield, resume, running = coroutine.yield, coroutine.resume, coroutine.running
local fs = require("fs")
local path = require("path")
local json = require("json")
local time = require("discordia").Time
local stopwatch = require("discordia").Stopwatch

local log = require("discordia").Logger(3, "%F %T")

local queued = {}
local status = {}
local played = {}
local nexted = {}
local waitmu = {}
local loopmu = {}
local repemu = {}
local volume = {}
local normmu = {}

local function update_queue(guild)
    fs.mkdirSync("./wrun/"..guild)

    -- set default normmu is not set yet
    if normmu[guild] == nul then
        normmu[guild] = true
    end

    if not queued[guild] then return end

    -- fetch current song
    if queued[guild][1] and queued[guild][1].dl == 0 then
        queued[guild][1].dl = 2
        log:log(3, "[music] Downloading: %s", queued[guild][1].url)
        queued[guild][1].dl_handle = assert(uv.spawn("yt-dlp", {
            args = { "-x", "--audio-format", "wav", "--audio-quality", "0", "--no-playlist", "--force-overwrites", "-o", "./wrun/"..guild.."/music_curr_pre.%(ext)s", queued[guild][1].url },
        }, function(code, signal)
            if code == 0 and signal == 0 then
                -- check if we are normalizing
                if normmu[guild] then
                    log:log(3, "[music] Normalizing: %s", queued[guild][1].url)
                    queued[guild][1].dl_handle = assert(uv.spawn("ffmpeg-normalize", {
                        args = { "-ar", "48000", "-f", "-t", volume[guild], "./wrun/"..guild.."/music_curr_pre.wav", "-o", "./wrun/"..guild.."/music_curr.wav" },
                    }, function(code, signal)
                        if code == 0 and signal == 0 then
                            os.execute("rm ./wrun/"..guild.."/music_curr_pre.wav")
                            queued[guild][1].dl = 1
                            log:log(3, "[music] Ready: %s", queued[guild][1].url)
                        end
                        if code == 1 then
                            if not queued[guild][1].dl_retry then
                                queued[guild][1].dl = 0
                                queued[guild][1].dl_retry = true
                                log:log(3, "[music] Retrying: %s", queued[guild][1].url)
                            else
                                queued[guild][1].dl = 1
                                log:log(3, "[music] Ready: %s", queued[guild][1].url)
                            end
                        end
                    end), "is ffmpeg-normalize installed and on $PATH?")
                else
                    os.execute("mv ./wrun/"..guild.."/music_curr_pre.wav ./wrun/"..guild.."/music_curr.wav")
                    queued[guild][1].dl = 1
                    log:log(3, "[music] Ready: %s", queued[guild][1].url)
                end
            end
            if code == 1 then
                if not queued[guild][1].dl_retry then
                    queued[guild][1].dl = 0
                    queued[guild][1].dl_retry = true
                    log:log(3, "[music] Retrying: %s", queued[guild][1].url)
                else
                    queued[guild][1].dl = 1
                    log:log(3, "[music] Ready: %s", queued[guild][1].url)
                end
            end
        end), "is yt-dlp installed and on $PATH?")
    end
    -- prefetch next song
    if queued[guild][2] and queued[guild][2].dl == 0 then
        queued[guild][2].dl = 2
        log:log(3, "[music] Downloading: %s", queued[guild][2].url)
        queued[guild][2].dl_handle = assert(uv.spawn("yt-dlp", {
            args = { "-x", "--audio-format", "wav", "--audio-quality", "0", "--no-playlist", "--force-overwrites", "-o", "./wrun/"..guild.."/music_next_pre.%(ext)s", queued[guild][2].url },
        }, function(code, signal)
            if code == 0 and signal == 0 then
                -- check if we are normalizing
                if normmu[guild] then
                    log:log(3, "[music] Normalizing: %s", queued[guild][2].url)
                    queued[guild][2].dl_handle = assert(uv.spawn("ffmpeg-normalize", {
                        args = { "-ar", "48000", "-f", "-t", volume[guild], "./wrun/"..guild.."/music_next_pre.wav", "-o", "./wrun/"..guild.."/music_next.wav" },
                    }, function(code, signal)
                        if code == 0 and signal == 0 then
                            os.execute("rm ./wrun/"..guild.."/music_next_pre.wav")
                            queued[guild][2].dl = 1
                            log:log(3, "[music] Ready: %s", queued[guild][2].url)
                        end
                        if code == 1 then
                            if not queued[guild][2].dl_retry then
                                queued[guild][2].dl = 0
                                queued[guild][2].dl_retry = true
                                log:log(3, "[music] Retrying: %s", queued[guild][2].url)
                            else
                                queued[guild][2].dl = 1
                                log:log(3, "[music] Failed: %s", queued[guild][2].url)
                            end
                        end
                    end), "is ffmpeg-normalize installed and on $PATH?")
                else
                    os.execute("mv ./wrun/"..guild.."/music_next_pre.wav ./wrun/"..guild.."/music_next.wav")
                    queued[guild][2].dl = 1
                    log:log(3, "[music] Ready: %s", queued[guild][2].url)
                end
            end
            if code == 1 then
                if not queued[guild][2].dl_retry then
                    queued[guild][2].dl = 0
                    queued[guild][2].dl_retry = true
                    log:log(3, "[music] Retrying: %s", queued[guild][2].url)
                else
                    queued[guild][2].dl = 1
                    log:log(3, "[music] Ready: %s", queued[guild][2].url)
                end
            end
        end), "is yt-dlp installed and on $PATH?")
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

    -- if we are repeating requeue the song
    if repemu[guild] then
        table.insert(queued[guild], queued[guild][1])
        queued[guild][#queued[guild]].dl = 0
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
            fs.renameSync("./wrun/"..guild.."/music_next.wav", "./wrun/"..guild.."/music_curr.wav")
        else
            queued[guild][1].dl = 0
            os.execute("rm -r ./wrun/"..guild)
        end

        -- fetch new next
        update_queue(guild)

        return
    end

    -- move next to curr
    fs.renameSync("./wrun/"..guild.."/music_next.wav", "./wrun/"..guild.."/music_curr.wav")
    table.remove(queued[guild], 1)

    -- fetch new next
    update_queue(guild)
end

return function(client) return {
    name = "Music",
    description = "Plays music in voice channels",
    commands = {
        ["queue"] = {
            description = "Queues a song for playback",
            exec = function(message)
                local args = message.content:split(" ")

                -- set default volume if not set yet
                if volume[message.guild.id] == nil then
                    volume[message.guild.id] = "-23"
                end

                if args[2] then
                    local sw = stopwatch()
                    sw:start()

                    local url = message.content:gsub(";queue ", "", 1):gsub("<", ""):gsub(">", "")

                    -- spawn youtube-dl process
                    local stop = false
                    local thread = running()
                    local stdout = uv.new_pipe(false)
                    local handle, pid = assert(uv.spawn("yt-dlp", {
                        args = { "-O", "%(title)s|||||%(duration)s", "--no-playlist", url },
                        stdio = { 0, stdout, 2 }
                    }, function(code, signal)
                        if code ~= 0 or signal ~= 0 then
                            stop = true
                        end
                        resume(thread)
                    end), "is yt-dlp installed and on $PATH?")

                    -- read data from stdout of youtube-dl
                    local ret = ""
                    stdout:read_start(function(err, data)
                        assert(not err, err)
                        if data then
                            ret = ret..data
                        end
                    end)
                    yield()

                    -- close handle
                    uv.close(handle)
                    uv.shutdown(stdout)

                    -- invalid url encountered
                    if stop then
                        message:reply({
                            embed = {
                                title = "Music - Queue",
                                description = "Invalid URL!"
                            },
                            reference = { message = message, mention = true }
                        })
                        return
                    end

                    -- parse returned data
                    local title = ret:split("|||||")[1]
                    local raw_duration = tonumber(ret:split("|||||")[2])

                    -- check before queue
                    if title and title ~= "NA" and raw_duration and (raw_duration <= 900 or message.author == client.owner) then
                        local duration = time.fromSeconds(raw_duration):toString()
                        
                        -- create array if not already created
                        if not queued[message.guild.id] then
                            queued[message.guild.id] = {}
                        end

                        -- check if the song is already queued
                        local before_duration = 0
                        for i, song in ipairs(queued[message.guild.id]) do
                            if song.title == title then
                                message:reply({
                                    embed = {
                                        title = "Music - Queue",
                                        description = "Already Queued!"
                                    },
                                    reference = { message = message, mention = true }
                                })
                                return
                            end
                            before_duration = before_duration + song.raw_duration
                        end

                        -- queue song
                        table.insert(queued[message.guild.id], {
                            title = title,
                            raw_duration = raw_duration,
                            duration = duration,
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
                                        value = message.author.tag,
                                        inline = true
                                    },
                                    {
                                        name = "Duration",
                                        value = duration,
                                        inline = true
                                    },
                                    {
                                        name = "Will Play In",
                                        value = time.fromSeconds(before_duration):toString(),
                                        inline = true
                                    },
                                    {
                                        name = "Queued In",
                                        value = sw:getTime():toString(),
                                        inline = true
                                    },
                                    {
                                        name = "Queue ID",
                                        value = #queued[message.guild.id],
                                        inline = true
                                    }
                                }
                            },
                            reference = { message = message, mention = true }
                        })

                        -- update queue
                        update_queue(message.guild.id)
                    else
                        message:reply({
                            embed = {
                                title = "Music - Queue",
                                description = "Invalid URL / Duration Too Long!"
                            },
                            reference = { message = message, mention = true }
                        })
                    end
                else
                    message:reply({
                        embed = {
                            title = "Music - Queue",
                            description = "Invalid URL!"
                        },
                        reference = { message = message, mention = true }
                    })
                end
            end
        },
        ["qlist"] = {
            description = "Queues a playlist for playback",
            exec = function(message)
                local args = message.content:split(" ")

                -- set default volume if not set yet
                if volume[message.guild.id] == nil then
                    volume[message.guild.id] = "-23"
                end

                if args[2] then
                    local sw = stopwatch()
                    sw:start()

                    local url = message.content:gsub(";qlist ", "", 1):gsub("<", ""):gsub(">", "")

                    -- spawn youtube-dl process
                    local stop = false
                    local thread = running()
                    local stdout = uv.new_pipe(false)
                    local handle, pid = assert(uv.spawn("yt-dlp", {
                        args = { "-O", "%(title)s|||||%(duration)s|||||%(url)s|||||%(playlist_index)s", "--flat-playlist", url },
                        stdio = { 0, stdout, 2 }
                    }, function(code, signal)
                        if code ~= 0 or signal ~= 0 then
                            stop = true
                        end
                        resume(thread)
                    end), "is yt-dlp installed and on $PATH?")

                    -- read data from stdout of youtube-dl
                    local ret = ""
                    stdout:read_start(function(err, data)
                        assert(not err, err)
                        if data then
                            ret = ret..data
                        end
                    end)
                    yield()

                    -- close handle
                    uv.close(handle)
                    uv.shutdown(stdout)

                    -- invalid url encountered
                    if stop then
                        message:reply({
                            embed = {
                                title = "Music - Queue List",
                                description = "Invalid URL!"
                            },
                            reference = { message = message, mention = true }
                        })
                        return
                    end

                    -- loop over playlist songs
                    local songs = ret:split("\n")
                    local succeeded = {}
                    local failed = {}
                    local skipped = {}
                    for i, song in ipairs(songs) do
                        if i == #songs then break end
                        if #succeeded >= 9 and message.author ~= client.owner then break end

                        -- parse song data
                        local title = song:split("|||||")[1]
                        local raw_duration = tonumber(song:split("|||||")[2])
                        local url = song:split("|||||")[3]
                        local index = song:split("|||||")[4]

                        -- check before queue
                        if title and title ~= "NA" and raw_duration and url and (raw_duration <= 900 or message.author == client.owner) then
                            local duration = time.fromSeconds(raw_duration):toString()

                            -- create array if not already created
                            if not queued[message.guild.id] then
                                queued[message.guild.id] = {}
                            end

                            -- check if the song is already queued
                            local skip = false
                            local before_duration = 0
                            for i, song in ipairs(queued[message.guild.id]) do
                                if song.title == title then
                                    skip = true
                                    table.insert(skipped, song)
                                end
                                before_duration = before_duration + song.raw_duration
                            end
                            if not skip then
                                -- queue song
                                table.insert(queued[message.guild.id], {
                                    title = title,
                                    raw_duration = raw_duration,
                                    duration = duration,
                                    url = url,
                                    user = message.author.tag,
                                    message = message,
                                    dl = 0,
                                    dl_handle = nil
                                })
                                table.insert(succeeded, song)

                                message:reply({
                                    embed = {
                                        title = "Music - Queued",
                                        description = title,
                                        fields = {
                                            {
                                                name = "Requested By",
                                                value = message.author.tag,
                                                inline = true
                                            },
                                            {
                                                name = "Duration",
                                                value = duration,
                                                inline = true
                                            },
                                            {
                                                name = "Will Play In",
                                                value = time.fromSeconds(before_duration):toString(),
                                                inline = true
                                            },
                                            {
                                                name = "Queued In",
                                                value = sw:getTime():toString(),
                                                inline = true
                                            },
                                            {
                                                name = "Queue ID",
                                                value = #queued[message.guild.id],
                                                inline = true
                                            },
                                            {
                                                name = "Playlist ID",
                                                value = index,
                                                inline = true
                                            }
                                        }
                                    },
                                    reference = { message = message, mention = true }
                                })

                                -- update queue
                                update_queue(message.guild.id)
                            end
                        else
                            table.insert(failed, song)
                        end
                    end

                    -- report how many failed
                    message:reply({
                        embed = {
                            title = "Music - Queue List",
                            description = "Succeeded: "..#succeeded.." | Failed: "..#failed.." | Skipped: "..#skipped
                        },
                        reference = { message = message, mention = true }
                    })
                else
                    message:reply({
                        embed = {
                            title = "Music - Queue List",
                            description = "Invalid URL!"
                        },
                        reference = { message = message, mention = true }
                    })
                end
            end
        },
        ["qlistr"] = {
            description = "Queues a playlist for playback (randomized)",
            exec = function(message)
                local args = message.content:split(" ")

                -- set default volume if not set yet
                if volume[message.guild.id] == nil then
                    volume[message.guild.id] = "-23"
                end

                if args[2] then
                    local sw = stopwatch()
                    sw:start()

                    local url = message.content:gsub(";qlistr ", "", 1):gsub("<", ""):gsub(">", "")

                    -- spawn youtube-dl process
                    local stop = false
                    local thread = running()
                    local stdout = uv.new_pipe(false)
                    local handle, pid = assert(uv.spawn("yt-dlp", {
                        args = { "-O", "%(title)s|||||%(duration)s|||||%(url)s|||||%(playlist_index)s", "--flat-playlist", "--playlist-random", url },
                        stdio = { 0, stdout, 2 }
                    }, function(code, signal)
                        if code ~= 0 or signal ~= 0 then
                            stop = true
                        end
                        resume(thread)
                    end), "is yt-dlp installed and on $PATH?")

                    -- read data from stdout of youtube-dl
                    local ret = ""
                    stdout:read_start(function(err, data)
                        assert(not err, err)
                        if data then
                            ret = ret..data
                        end
                    end)
                    yield()

                    -- close handle
                    uv.close(handle)
                    uv.shutdown(stdout)

                    -- invalid url encountered
                    if stop then
                        message:reply({
                            embed = {
                                title = "Music - Queue List",
                                description = "Invalid URL!"
                            },
                            reference = { message = message, mention = true }
                        })
                        return
                    end

                    -- loop over playlist songs
                    local songs = ret:split("\n")
                    local succeeded = {}
                    local failed = {}
                    local skipped = {}
                    for i, song in ipairs(songs) do
                        if i == #songs then break end
                        if #succeeded >= 9 and message.author ~= client.owner then break end

                        -- parse song data
                        local title = song:split("|||||")[1]
                        local raw_duration = tonumber(song:split("|||||")[2])
                        local url = song:split("|||||")[3]
                        local index = song:split("|||||")[4]

                        -- check before queue
                        if title and title ~= "NA" and raw_duration and url and (raw_duration <= 900 or message.author == client.owner) then
                            local duration = time.fromSeconds(raw_duration):toString()

                            -- create array if not already created
                            if not queued[message.guild.id] then
                                queued[message.guild.id] = {}
                            end

                            -- check if the song is already queued
                            local skip = false
                            local before_duration = 0
                            for i, song in ipairs(queued[message.guild.id]) do
                                if song.title == title then
                                    skip = true
                                    table.insert(skipped, song)
                                end
                                before_duration = before_duration + song.raw_duration
                            end
                            if not skip then
                                -- queue song
                                table.insert(queued[message.guild.id], {
                                    title = title,
                                    raw_duration = raw_duration,
                                    duration = duration,
                                    url = url,
                                    user = message.author.tag,
                                    message = message,
                                    dl = 0,
                                    dl_handle = nil
                                })
                                table.insert(succeeded, song)

                                message:reply({
                                    embed = {
                                        title = "Music - Queued",
                                        description = title,
                                        fields = {
                                            {
                                                name = "Requested By",
                                                value = message.author.tag,
                                                inline = true
                                            },
                                            {
                                                name = "Duration",
                                                value = duration,
                                                inline = true
                                            },
                                            {
                                                name = "Will Play In",
                                                value = time.fromSeconds(before_duration):toString(),
                                                inline = true
                                            },
                                            {
                                                name = "Queued In",
                                                value = sw:getTime():toString(),
                                                inline = true
                                            },
                                            {
                                                name = "Queue ID",
                                                value = #queued[message.guild.id],
                                                inline = true
                                            },
                                            {
                                                name = "Playlist ID",
                                                value = index,
                                                inline = true
                                            }
                                        }
                                    },
                                    reference = { message = message, mention = true }
                                })

                                -- update queue
                                update_queue(message.guild.id)
                            end
                        else
                            table.insert(failed, song)
                        end
                    end

                    -- report how many failed
                    message:reply({
                        embed = {
                            title = "Music - Queue List",
                            description = "Succeeded: "..#succeeded.." | Failed: "..#failed.." | Skipped: "..#skipped
                        },
                        reference = { message = message, mention = true }
                    })
                else
                    message:reply({
                        embed = {
                            title = "Music - Queue List",
                            description = "Invalid URL!"
                        },
                        reference = { message = message, mention = true }
                    })
                end
            end
        },
        ["qlists"] = {
            description = "Queues a selection of random songs from a playlist",
            exec = function(message)
                local args = message.content:split(" ")

                -- set default volume if not set yet
                if volume[message.guild.id] == nil then
                    volume[message.guild.id] = "-23"
                end

                if args[2] and tonumber(args[3]) and (tonumber(args[3]) <= 9 or message.author == client.owner) then
                    local sw = stopwatch()
                    sw:start()

                    local url = args[2]
                    local count = tonumber(args[3])

                    -- spawn youtube-dl process
                    local stop = false
                    local thread = running()
                    local stdout = uv.new_pipe(false)
                    local handle, pid = assert(uv.spawn("yt-dlp", {
                        args = { "-O", "%(title)s|||||%(duration)s|||||%(url)s|||||%(playlist_index)s", "--flat-playlist", "--playlist-random", url },
                        stdio = { 0, stdout, 2 }
                    }, function(code, signal)
                        if code ~= 0 or signal ~= 0 then
                            stop = true
                        end
                        resume(thread)
                    end), "is yt-dlp installed and on $PATH?")

                    -- read data from stdout of youtube-dl
                    local ret = ""
                    stdout:read_start(function(err, data)
                        assert(not err, err)
                        if data then
                            ret = ret..data
                        end
                    end)
                    yield()

                    -- close handle
                    uv.close(handle)
                    uv.shutdown(stdout)

                    -- invalid url encountered
                    if stop then
                        message:reply({
                            embed = {
                                title = "Music - Queue List",
                                description = "Invalid URL!"
                            },
                            reference = { message = message, mention = true }
                        })
                        return
                    end

                    -- loop over playlist songs
                    local songs = ret:split("\n")
                    for i, song in ipairs(songs) do
                        if i == #songs then break end

                        -- parse song data
                        local title = song:split("|||||")[1]
                        local raw_duration = tonumber(song:split("|||||")[2])
                        local url = song:split("|||||")[3]
                        local index = song:split("|||||")[4]

                        -- check before queue
                        if title and title ~= "NA" and raw_duration and url and (raw_duration <= 900 or message.author == client.owner) then
                            local duration = time.fromSeconds(raw_duration):toString()

                            -- create array if not already created
                            if not queued[message.guild.id] then
                                queued[message.guild.id] = {}
                            end

                            -- check if the song is already queued
                            local skip = false
                            local before_duration = 0
                            for i, song in ipairs(queued[message.guild.id]) do
                                if song.title == title then
                                    skip = true
                                end
                                before_duration = before_duration + song.raw_duration
                            end
                            if not skip then
                                -- queue song
                                table.insert(queued[message.guild.id], {
                                    title = title,
                                    raw_duration = raw_duration,
                                    duration = duration,
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
                                                value = message.author.tag,
                                                inline = true
                                            },
                                            {
                                                name = "Duration",
                                                value = duration,
                                                inline = true
                                            },
                                            {
                                                name = "Will Play In",
                                                value = time.fromSeconds(before_duration):toString(),
                                                inline = true
                                            },
                                            {
                                                name = "Queued In",
                                                value = sw:getTime():toString(),
                                                inline = true
                                            },
                                            {
                                                name = "Queue ID",
                                                value = #queued[message.guild.id],
                                                inline = true
                                            },
                                            {
                                                name = "Playlist ID",
                                                value = index,
                                                inline = true
                                            }
                                        }
                                    },
                                    reference = { message = message, mention = true }
                                })

                                -- update queue
                                update_queue(message.guild.id)

                                if count <= 1 then
                                    break
                                else
                                    count = count - 1
                                end
                            end
                        end
                    end
                else
                    message:reply({
                        embed = {
                            title = "Music - Queue List",
                            description = "Invalid URL/Invalid Count!"
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

                -- get page number
                local page = 0
                local args = message.content:split(" ")
                if args[2] then
                    page = tonumber(args[2])
                    if not page or page < 1 then
                        page = 0
                    else
                        page = math.floor(page - 1)
                    end
                end

                -- generate fields for queued songs
                local fields = {}
                for i = (page * 12) + 1, math.min(((page + 1) * 12), #queued[message.guild.id]) do
                    local song = queued[message.guild.id][i]

                    local name = ""
                    if i == 1 then
                        name = "*"..i..") "..song.title
                    else
                        name = i..")  "..song.title
                    end
                    local value = "Requested By: "..song.user
                    if song.dl == 0 then
                        value = value.." | Status: (Waiting)"
                    end
                    if song.dl == 1 then
                        value = value.." | Status: (Ready)"
                    end
                    if song.dl == 2 then
                        value = value.." | Status: (Downloading)"
                    end
                    table.insert(fields, {
                        name = name,
                        value = value,
                        inline = true
                    })
                end

                -- get total duration
                local total_duration = 0
                for i, song in ipairs(queued[message.guild.id]) do
                    total_duration = total_duration + song.raw_duration
                end

                message:reply({
                    embed = {
                        title = "Music - List | Songs: "..#queued[message.guild.id].." | Page: "..page + 1,
                        description = "Queue Duration: "..time.fromSeconds(total_duration):toString(),
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
                    if played[message.guild.id] == nil then
                        played[message.guild.id] = stopwatch()
                    end

                    message:reply({
                        embed = {
                            title = "Music - Current",
                            description = queued[message.guild.id][1].title,
                            fields = {
                                {
                                    name = "Requested By",
                                    value = queued[message.guild.id][1].user,
                                    inline = true
                                },
                                {
                                    name = "Played",
                                    value = played[message.guild.id]:getTime():toString(),
                                    inline = true
                                },
                                {
                                    name = "Duration",
                                    value = queued[message.guild.id][1].duration,
                                    inline = true
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
                if waitmu[message.guild.id] == nil then
                    waitmu[message.guild.id] = 1
                end

                -- set default loop state if not set yet
                if loopmu[message.guild.id] == nil then
                    loopmu[message.guild.id] = false
                end

                -- set default repeat state if not set yet
                if repemu[message.guild.id] == nil then
                    repemu[message.guild.id] = false
                end

                -- set default played if not set yet
                if played[message.guild.id] == nil then
                    played[message.guild.id] = stopwatch()
                end

                if message.member.voiceChannel then
                    if not status[message.guild.id] then
                        message:addReaction("✅")
                        message.member.voiceChannel:join()
                        coroutine.wrap(function ()
                            status[message.guild.id] = coroutine.running()
                            while status[message.guild.id] do
                                if queued[message.guild.id] and queued[message.guild.id][1] and queued[message.guild.id][1].dl == 1 then
                                    -- send now playing message
                                    message:reply({
                                        embed = {
                                            title = "Music - Now Playing",
                                            description = queued[message.guild.id][1].title,
                                            fields = {
                                                {
                                                    name = "Requested By",
                                                    value = queued[message.guild.id][1].user,
                                                    inline = true
                                                },
                                                {
                                                    name = "Duration",
                                                    value = queued[message.guild.id][1].duration,
                                                    inline = true
                                                }
                                            }
                                        },
                                        reference = { message = queued[message.guild.id][1].message, mention = false },
                                    })

                                    -- play song
                                    local f = io.open("./wrun/"..message.guild.id.."/music_curr.wav", "rb")
                                    local difference = nil
                                    if f then
                                        f:seek("set", 44)
                                        played[message.guild.id]:start()
                                        played[message.guild.id]:reset()
                                        if message.guild.connection then
                                            difference = time.fromMilliseconds(message.guild.connection:playPCM(f:read("*a"))):toSeconds() - queued[message.guild.id][1].raw_duration
                                        else
                                            break
                                        end
                                    end

                                    -- switch to next song
                                    if not nexted[message.guild.id] and not (difference < 5 and difference > -5) then
                                        break
                                    end
                                    if status[message.guild.id] and message.guild.connection then
                                        if not loopmu[message.guild.id] then
                                            if nexted[message.guild.id] then
                                                next_song(message.guild.id, true)
                                            else
                                                next_song(message.guild.id, false)
                                            end
                                        end
                                    else
                                        break
                                    end
                                else
                                    -- waiting for song to download
                                    if status[message.guild.id] and message.guild.connection then
                                        local f = io.open(uv.os_getenv("WOZEY_ROOT").."/assets/music_waiting_"..waitmu[message.guild.id]..".wav", "rb")
                                        if f then
                                            f:seek("set", 44)
                                            if message.guild.connection then
                                                message.guild.connection:playPCM(f:read("*a"))
                                            else
                                                break
                                            end
                                        end
                                    else
                                        break
                                    end

                                    if status[message.guild.id] and nexted[message.guild.id] and message.guild.connection then
                                        next_song(message.guild.id, true)
                                    end
                                end
                                nexted[message.guild.id] = false
                            end
                            if message.guild.connection then
                                message.guild.connection:close()
                            end
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
                    if message.guild.connection then
                        message.guild.connection:stopStream()
                    end
                    played[message.guild.id]:stop()
                    played[message.guild.id]:reset()
                    message:addReaction("✅")
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
                    played[message.guild.id]:start()
                    message.guild.connection:resumeStream()
                    message:addReaction("✅")
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
                    played[message.guild.id]:stop()
                    message.guild.connection:pauseStream()
                    message:addReaction("✅")
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
                if status[message.guild.id] and queued[message.guild.id] and message.guild.connection then
                    -- only allow person who queued to skip their song
                    if queued[message.guild.id][1].user == message.author.tag or message.author == client.owner or not message.guild.connection.channel.connectedMembers:find(function (a) return queued[message.guild.id][1].user == a.user.tag end) then
                        nexted[message.guild.id] = true
                        message.guild.connection:stopStream()
                        message:addReaction("✅")
                    else
                        message:reply({
                            embed = {
                                title = "Music - Next",
                                description = "You Didn't Queue This Song!"
                            },
                            reference = { message = message, mention = true }
                        })
                    end
                else
                    message:reply({
                        embed = {
                            title = "Music - Next",
                            description = "No Music Queued / No Music Playing!"
                        },
                        reference = { message = message, mention = true }
                    })
                end
            end
        },
        ["delete"] = {
            description = "Deletes a song from the queue",
            exec = function(message)
                if queued[message.guild.id] then
                    local args = message.content:split(" ")
                    
                    if args[2] and tonumber(args[2]) and args[2] ~= "1" and queued[message.guild.id][tonumber(args[2])] ~= nil then
                        local i = tonumber(args[2])

                        -- only allow person who queued to delete their song
                        if queued[message.guild.id][i].user == message.author.tag or message.author == client.owner then
                            if queued[message.guild.id][i].dl == 2 then
                                uv.process_kill(queued[message.guild.id][i].dl_handle, "sigkill")
                                queued[message.guild.id][i].dl = 0
                            end
                            if i == 2 then
                                os.execute("rm ./wrun/"..message.guild.id.."/music_next.wav")
                            end

                            table.remove(queued[message.guild.id], i)

                            -- fetch new next
                            update_queue(message.guild.id)

                            message:addReaction("✅")
                        else
                            message:reply({
                                embed = {
                                    title = "Music - Delete",
                                    description = "You Didn't Queue This Song!"
                                },
                                reference = { message = message, mention = true }
                            })
                        end
                    else
                        -- handle first song differently
                        if args[2] == "1" then
                            if not status[message.guild.id] and not message.guild.connection then
                                -- only allow person who queued to delete their song
                                if queued[message.guild.id][1].user == message.author.tag or message.author == client.owner then
                                    next_song(message.guild.id, true)

                                    message:addReaction("✅")
                                else
                                    message:reply({
                                        embed = {
                                            title = "Music - Delete",
                                            description = "You Didn't Queue This Song!"
                                        },
                                        reference = { message = message, mention = true }
                                    })
                                end
                            else
                                message:reply({
                                    embed = {
                                        title = "Music - Delete",
                                        description = "Song is currently playing! (use ;next)"
                                    },
                                    reference = { message = message, mention = true }
                                })
                            end
                        else
                            message:reply({
                                embed = {
                                    title = "Music - Delete",
                                    description = "Invalid Queue ID!"
                                },
                                reference = { message = message, mention = true }
                            })
                        end
                    end
                else
                    message:reply({
                        embed = {
                            title = "Music - Delete",
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
        },
        ["mul"] = {
            description = "Sets loop mode",
            owner_only = true,
            exec = function(message)
                local args = message.content:split(" ")

                if args[2] and (args[2] == "true" or args[2] == "false") then
                    if args[2] == "true" then
                        loopmu[message.guild.id] = true
                    end
                    if args[2] == "false" then
                        loopmu[message.guild.id] = false
                    end

                    message:reply({
                        embed = {
                            title = "Music - Loop",
                            description = "Set Loop To: "..args[2],
                        },
                        reference = { message = message, mention = true }
                    })
                else
                    message:reply({
                        embed = {
                            title = "Music - Loop",
                            description = "Invalid Loop State!"
                        },
                        reference = { message = message, mention = true }
                    })
                end
            end
        },
        ["mur"] = {
            description = "Sets repeat mode",
            owner_only = true,
            exec = function(message)
                local args = message.content:split(" ")

                if args[2] and (args[2] == "true" or args[2] == "false") then
                    if args[2] == "true" then
                        repemu[message.guild.id] = true
                    end
                    if args[2] == "false" then
                        repemu[message.guild.id] = false
                    end

                    message:reply({
                        embed = {
                            title = "Music - Repeat",
                            description = "Set Repeat To: "..args[2],
                        },
                        reference = { message = message, mention = true }
                    })
                else
                    message:reply({
                        embed = {
                            title = "Music - Repeat",
                            description = "Invalid Repeat State!"
                        },
                        reference = { message = message, mention = true }
                    })
                end
            end
        },
        ["muv"] = {
            description = "Changes music volume for not downloaded tracks",
            owner_only = true,
            exec = function(message)
                local args = message.content:split(" ")

                if args[2] then
                    volume[message.guild.id] = args[2]

                    message:reply({
                        embed = {
                            title = "Music - Volume",
                            description = "Changed Music Volume To: "..args[2],
                        },
                        reference = { message = message, mention = true }
                    })
                else
                    message:reply({
                        embed = {
                            title = "Music - Volume",
                            description = "Invalid Music Volume!"
                        },
                        reference = { message = message, mention = true }
                    })
                end
            end
        },
        ["mun"] = {
            description = "Sets normalization mode",
            owner_only = true,
            exec = function(message)
                local args = message.content:split(" ")

                if args[2] and (args[2] == "true" or args[2] == "false") then
                    if args[2] == "true" then
                        normmu[message.guild.id] = true
                    end
                    if args[2] == "false" then
                        normmu[message.guild.id] = false
                    end

                    message:reply({
                        embed = {
                            title = "Music - Normalization",
                            description = "Set Normalization To: "..args[2],
                        },
                        reference = { message = message, mention = true }
                    })
                else
                    message:reply({
                        embed = {
                            title = "Music - Normalization",
                            description = "Invalid Normalization State!"
                        },
                        reference = { message = message, mention = true }
                    })
                end
            end
        },
        ["mus"] = {
            description = "Shuffles not downloaded tracks",
            owner_only = true,
            exec = function(message)
                if queued[message.guild.id] then
                    for i = #queued[message.guild.id], 2, -1 do
                        local j = math.random(i)
                        if i > 2 and j > 2 then
                            queued[message.guild.id][i], queued[message.guild.id][j] = queued[message.guild.id][j], queued[message.guild.id][i]
                        end
                    end

                    message:addReaction("✅")
                else
                    message:reply({
                        embed = {
                            title = "Music - Shuffle",
                            description = "No Music Queued!"
                        },
                        reference = { message = message, mention = true }
                    })
                end
            end
        },
        ["muc"] = {
            description = "Clears the queue",
            owner_only = true,
            exec = function(message)
                status[message.guild.id] = nil
                if message.guild.connection then
                    message.guild.connection:stopStream()
                end
                if queued[message.guild.id] then
                    if queued[message.guild.id][1] and queued[message.guild.id][1].dl == 2 then
                        uv.process_kill(queued[message.guild.id][1].dl_handle, "sigkill")
                    end
                    if queued[message.guild.id][2] and queued[message.guild.id][2].dl == 2 then
                        uv.process_kill(queued[message.guild.id][2].dl_handle, "sigkill")
                    end

                    queued[message.guild.id] = nil
                end
                message:addReaction("✅")
            end
        },
        ["mum"] = {
            description = "Swaps the places of two songs in the queue",
            owner_only = true,
            exec = function(message)
                local args = message.content:split(" ")
                if not args[2] or not args[3] or args[2] == "1" or args[3] == "1" or args[2] == "2" or args[3] == "2" or not tonumber(args[2]) or not tonumber(args[2]) then
                    message:reply({
                        embed = {
                            title = "Music - Move",
                            description = "Invalid Queued IDs!"
                        },
                        reference = { message = message, mention = true }
                    })
                    return
                end

                if queued[message.guild.id] then
                    queued[message.guild.id][tonumber(args[2])], queued[message.guild.id][tonumber(args[3])] = queued[message.guild.id][tonumber(args[3])], queued[message.guild.id][tonumber(args[2])]

                    message:addReaction("✅")
                else
                    message:reply({
                        embed = {
                            title = "Music - Move",
                            description = "No Music Queued!"
                        },
                        reference = { message = message, mention = true }
                    })
                end
            end
        }
    },
    callbacks = {}
}end
