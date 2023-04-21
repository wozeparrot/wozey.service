local uv = require("uv")

local Time = require("discordia").Time
local Stopwatch = require("discordia").Stopwatch

local log = require("discordia").Logger(3, "%F %T")

-- stores the state of the music player for each guild
local mp_state = {}

local function ensure_state_exists(guild)
	if not mp_state[guild.id] then
		mp_state[guild.id] = {
			voice_channel = nil,
			songs = {},
			thread_handle = nil,
			tweaks = {
				bassboost = 0,
				reverb = false,
				loudnorm = false,
				tempo = 1.0,
				bitcrush = 0,
			},
		}
	end
end

local function extract_song_info(url)
	local info = {}

	local function parse_data(data)
		local sdata = data:split(" |||||||||||||||| ")

		info.title = sdata[1]
		local raw_time = tonumber(sdata[2])
		if raw_time then
			info.duration = Time.fromSeconds(raw_time)
		elseif sdata[2] == "NA" then
			info.duration = Time.fromSeconds(0)
		else
			info.duration = nil
		end

		info.url = sdata[3]
	end

	-- spawn the process
	local data = ""
	local function read_data_from_ytdlp()
		-- store a reference to the coroutine that called this function
		local co = coroutine.running()

		local stdout_pipe = uv.new_pipe(false)
		local handle, _ = assert(
			uv.spawn("yt-dlp", {
				args = {
					"-xO",
					"%(title)s |||||||||||||||| %(duration)s |||||||||||||||| %(urls)s",
					"--no-playlist",
					url,
				},
				stdio = {
					nil,
					stdout_pipe,
					2,
				},
			}, function(code, signal)
				if code ~= 0 or signal ~= 0 then
					log:log(1, "yt-dlp exited with code %d", code)
				end
			end),
			"Failed to spawn yt-dlp"
		)

		-- read from the stdout pipe
		stdout_pipe:read_start(function(err, chunk)
			if err then
				log:log(1, "Error reading from yt-dlp: %s", err)

				uv.close(handle)
				uv.shutdown(stdout_pipe)

				return
			end

			if chunk then
				data = data .. chunk
			end

			if not chunk then
				coroutine.resume(co)
			end
		end)

		-- wait for the process to exit
		coroutine.yield()

		uv.close(handle)
		uv.shutdown(stdout_pipe)
	end

	read_data_from_ytdlp()

	if data == "" then
		-- retry once
		log:log(2, "Failed to extract song info, retrying")
		read_data_from_ytdlp()

		if data == "" then
			return nil
		end
	end

	parse_data(data)

	return info
end

local function extract_playlist_urls(url)
	local urls = {}

	local function parse_urls(data)
		urls = data:split("\n")
	end

	-- spawn the process
	local data = ""
	local function read_data_from_ytdlp()
		-- store a reference to the coroutine that called this function
		local co = coroutine.running()

		local stdout_pipe = uv.new_pipe(false)
		local handle, _ = assert(
			uv.spawn("yt-dlp", {
				args = {
					"-xO",
					"%(webpage_url)s",
					"--compat-options",
					"no-youtube-unavailable-videos",
					"--flat-playlist",
					"--playlist-random",
					url,
				},
				stdio = {
					nil,
					stdout_pipe,
					2,
				},
			}, function(code, signal)
				if code ~= 0 or signal ~= 0 then
					log:log(1, "yt-dlp exited with code %d", code)
				end
			end),
			"Failed to spawn yt-dlp"
		)

		-- read from the stdout pipe
		stdout_pipe:read_start(function(err, chunk)
			if err then
				log:log(1, "Error reading from yt-dlp: %s", err)

				uv.close(handle)
				uv.shutdown(stdout_pipe)

				return
			end

			if chunk then
				data = data .. chunk
			end

			if not chunk then
				coroutine.resume(co)
			end
		end)

		-- wait for the process to exit
		coroutine.yield()

		uv.close(handle)
		uv.shutdown(stdout_pipe)
	end

	read_data_from_ytdlp()

	if data == "" then
		-- retry once
		log:log(2, "Failed to extract song info, retrying")
		read_data_from_ytdlp()

		if data == "" then
			return nil
		end
	end

	parse_urls(data)

	-- only return 4 urls
	return { urls[1], urls[2], urls[3], urls[4] }
end

local function player_thread(message)
	while true do
		if not mp_state[message.guild.id].voice_channel then
			log:log(3, "No voice channel to play in, stopping player thread")
			mp_state[message.guild.id].thread_handle = nil
			return
		end

		-- wait for a song to be queued
		while #mp_state[message.guild.id].songs == 0 do
			coroutine.yield()
		end

		-- get refreshed song info
		local song = nil
		local play_info = nil
		while not play_info do
			song = mp_state[message.guild.id].songs[1]
			if uv.now() - song.queue_time > 12000 then
				log:log(3, "Attempting to extract refreshed info for song: %s in %s", song.url, message.guild.name)
				play_info = extract_song_info(song.url)
			else
				play_info = song.info
			end

			if not play_info then
				log:log(3, "Failed to extract refreshed info for song: %s in %s", song.url, message.guild.name)
				table.remove(mp_state[message.guild.id].songs, 1)

				-- wait for a song to be queued
				while #mp_state[message.guild.id].songs == 0 do
					coroutine.yield()
				end
			end
		end

		-- connect to the voice channel
		if not message.guild.connection then
			assert(mp_state[message.guild.id].voice_channel:join(), "Failed to join voice channel")
		end

		log:log(3, "Playing song: %s in %s", play_info.title, message.guild.name)

		-- send the now playing message
		song.now_playing_message = message.channel:send({
			embed = {
				title = "Music Player - Now Playing",
				description = play_info.title,
				fields = {
					{
						name = "Requested by",
						value = song.user,
						inline = true,
					},
					{
						name = "Duration",
						value = play_info.duration:toString(),
						inline = true,
					},
				},
			},
		})

		-- play the song
		local function build_filter_chain()
			local filter_chain = {}

			-- tempo
			if mp_state[message.guild.id].tweaks.tempo > 2 then
				table.insert(
					filter_chain,
					"[0] atempo=sqrt(" .. mp_state[message.guild.id].tweaks.tempo .. ") [tempo0];"
				)
				table.insert(
					filter_chain,
					"[tempo0] atempo=sqrt(" .. mp_state[message.guild.id].tweaks.tempo .. ") [tempo];"
				)
			else
				table.insert(filter_chain, "[0] atempo=" .. mp_state[message.guild.id].tweaks.tempo .. " [tempo];")
			end

			-- loudness normalization
			if mp_state[message.guild.id].tweaks.loudnorm then
				table.insert(filter_chain, "[tempo] loudnorm=I=-16:LRA=11:TP=-1.5 [norm];")
			else
				table.insert(filter_chain, "[tempo] amix=inputs=1 [norm];")
			end

			-- bass boost
			table.insert(
				filter_chain,
				"[norm] bass=g=" .. mp_state[message.guild.id].tweaks.bassboost .. ":frequency=140 [bass];"
			)

			-- bitcrusher
			if mp_state[message.guild.id].tweaks.bitcrush ~= 0 then
				table.insert(
					filter_chain,
					"[bass] acrusher=bits=" .. mp_state[message.guild.id].tweaks.bitcrush .. ":mode=log [crush];"
				)
			else
				table.insert(filter_chain, "[bass] amix=inputs=1 [crush];")
			end

			-- reverb
			if mp_state[message.guild.id].tweaks.reverb then
				table.insert(filter_chain, "[crush] [1] afir=dry=4:wet=4")
			else
				table.insert(filter_chain, "[crush] amix")
			end

			return table.concat(filter_chain)
		end
		message.guild.connection:playFFmpeg(play_info.url, {
			"-reconnect",
			"1",
			"-reconnect_streamed",
			"1",
			"-reconnect_delay_max",
			"5",
			"-reconnect_on_network_error",
			"1",
			"-reconnect_on_http_error",
			"1",
			"-xerror",
		}, {
			"-i",
			uv.os_getenv("WOZEY_ROOT") .. "/assets/reverb.wav",
			"-filter_complex",
			build_filter_chain(),
		})

		-- delete the now playing message
		if song.now_playing_message then
			song.now_playing_message:delete()
		end

		-- remove the song from the queue
		table.remove(mp_state[message.guild.id].songs, 1)
	end
end

return function(client, state)
	return {
		name = "Music Player",
		config_name = "music",
		description = "Plays music in a single voice channel",
		configs = {
			["max_duration"] = 600,
		},
		commands = {
			["play"] = {
				description = "Plays a song or queues a song depending on if a song is already playing or not",
				exec = function(message)
					local sw = Stopwatch()
					sw:start()

					-- Check if the user is in a voice channel
					if not message.member.voiceChannel then
						message:reply({
							embed = {
								title = "Music Player - `play`",
								description = "You must be in a voice channel!",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					local args = message.content:split(" ")
					if #args < 2 then
						message:reply({
							embed = {
								title = "Music Player - `play`",
								description = "You must provide a URL or a search query!",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					local url = nil

					-- Check if the item is a URL
					if args[2]:match("https?://") then
						-- use url without the < and > characters that hides the embed on discord
						url = args[2]:gsub("<", ""):gsub(">", "")
					else
						-- assuming that the item is a search query
						url = "ytsearch:" .. message.content:sub(#args[1] + 2)
					end

					log:log(3, "Attempting to extract initial info for song: %s in %s", url, message.guild.name)
					local info = extract_song_info(url)

					-- check if the song is valid
					if info == nil or not info.title or info.title == "NA" or info.duration == nil then
						message:reply({
							embed = {
								title = "Music Player - `play`",
								description = "Invalid URL!",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					-- check that the song is not too long
					-- TODO: make this configurable
					if
						info.duration:toSeconds() > state[message.guild.id].s.config.music.max_duration
						and message.author ~= client.owner
					then
						message:reply({
							embed = {
								title = "Music Player - `play`",
								description = "Song is too long!",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					ensure_state_exists(message.guild)
					mp_state[message.guild.id].voice_channel = message.member.voiceChannel

					-- calculate the time before this song will play
					local prior_duration = 0
					for _, song in ipairs(mp_state[message.guild.id].songs) do
						prior_duration = prior_duration + song.info.duration:toSeconds()
					end

					-- reply that the song was queued
					message:reply({
						embed = {
							title = "Music Player - Queued",
							description = info.title,
							fields = {
								{
									name = "Requested by",
									value = message.author.tag,
									inline = true,
								},
								{
									name = "Duration",
									value = info.duration:toString(),
									inline = true,
								},
								{
									name = "Will play in",
									value = Time.fromSeconds(prior_duration):toString(),
									inline = true,
								},
								{
									name = "Queue position",
									value = #mp_state[message.guild.id].songs + 1,
									inline = true,
								},
								{
									name = "Operation took",
									value = sw:getTime():toMilliseconds() .. "ms",
									inline = true,
								},
							},
						},
					})

					-- queue the song
					table.insert(mp_state[message.guild.id].songs, {
						url = url,
						info = info,
						user = message.author.tag,
						queue_time = uv.now(),
					})
					log:log(3, "Queued song: %s in %s", info.title, message.guild.name)

					-- check if the bot is already connected to a voice channel
					if mp_state[message.guild.id].thread_handle then
						-- resume the player thread
						if coroutine.status(mp_state[message.guild.id].thread_handle) == "suspended" then
							coroutine.resume(mp_state[message.guild.id].thread_handle)
						end
						return
					end

					-- spawn player thread
					mp_state[message.guild.id].thread_handle = coroutine.create(function()
						player_thread(message)
					end)

					-- resume the player thread
					if coroutine.status(mp_state[message.guild.id].thread_handle) == "suspended" then
						coroutine.resume(mp_state[message.guild.id].thread_handle)
					end
				end,
			},
			["playlist"] = {
				description = "Plays a playlist or queues a playlist depending on if a song is already playing or not",
				exec = function(message)
					local sw = Stopwatch()
					sw:start()

					-- Check if the user is in a voice channel
					if not message.member.voiceChannel then
						message:reply({
							embed = {
								title = "Music Player - `playlist`",
								description = "You must be in a voice channel!",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					local args = message.content:split(" ")
					if #args < 2 then
						message:reply({
							embed = {
								title = "Music Player - `playlist`",
								description = "You must provide a URL!",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					local playlist_url = nil

					-- Check if the item is a URL
					if args[2]:match("https?://") then
						-- use url without the < and > characters that hides the embed on discord
						playlist_url = args[2]:gsub("<", ""):gsub(">", "")
					else
						message:reply({
							embed = {
								title = "Music Player - `playlist`",
								description = "You must provide a URL!",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					ensure_state_exists(message.guild)
					mp_state[message.guild.id].voice_channel = message.member.voiceChannel

					local urls = extract_playlist_urls(playlist_url)

					for _, url in ipairs(urls) do
						if not url or url == "" then
							goto continue
						end

						log:log(3, "Attempting to extract initial info for song: %s in %s", url, message.guild.name)
						local info = extract_song_info(url)

						-- check if the song is valid
						if info == nil or not info.title or info.title == "NA" or info.duration == nil then
							-- skip this song
							goto continue
						end

						-- check that the song is not too long
						-- TODO: make this configurable
						if
							info.duration:toSeconds() > state[message.guild.id].s.config.music.max_duration
							and message.author ~= client.owner
						then
							-- skip this song
							goto continue
						end

						-- queue the song
						table.insert(mp_state[message.guild.id].songs, {
							url = url,
							info = info,
							user = message.author.tag,
							queue_time = uv.now(),
						})
						log:log(3, "Queued song: %s in %s", info.title, message.guild.name)

						-- check if the bot is already connected to a voice channel
						if mp_state[message.guild.id].thread_handle then
							-- resume the player thread
							if coroutine.status(mp_state[message.guild.id].thread_handle) == "suspended" then
								coroutine.resume(mp_state[message.guild.id].thread_handle)
							end
							goto continue
						end

						-- spawn player thread
						mp_state[message.guild.id].thread_handle = coroutine.create(function()
							player_thread(message)
						end)

						-- resume the player thread
						if coroutine.status(mp_state[message.guild.id].thread_handle) == "suspended" then
							coroutine.resume(mp_state[message.guild.id].thread_handle)
						end

						::continue::
					end

					message:reply({
						embed = {
							title = "Music Player - Queued",
							description = "Playlist queued",
							fields = {
								{
									name = "Requested by",
									value = message.author.tag,
									inline = true,
								},
								{
									name = "Operation took",
									value = sw:getTime():toMilliseconds() .. "ms",
									inline = true,
								},
							},
						},
					})
				end,
			},
			["stop"] = {
				description = "Stops the music player",
				exec = function(message)
					ensure_state_exists(message.guild)

					local args = message.content:split(" ")

					-- check if the bot is connected to a voice channel
					if mp_state[message.guild.id].thread_handle then
						-- clear the queue
						mp_state[message.guild.id].songs = {}

						-- stop the stream
						message.guild.connection:stopStream()

						if not args[2] then
							-- kill the player thread
							mp_state[message.guild.id].voice_channel = nil
							mp_state[message.guild.id].thread_handle = nil
							message.guild.connection:close()
						end

						-- react
						message:addReaction("✅")
					else
						-- reply that the player was not running
						message:reply({
							embed = {
								title = "Music Player - `stop`",
								description = "No music is playing.",
							},
							reference = { message = message, mention = true },
						})
					end
				end,
			},
			["skip"] = {
				description = "Skips the currently playing song",
				exec = function(message)
					ensure_state_exists(message.guild)

					-- check if the bot is connected to a voice channel
					if mp_state[message.guild.id].thread_handle then
						-- kill the player thread
						message.guild.connection:stopStream()

						-- react
						message:addReaction("✅")
					else
						-- reply that the player was not running
						message:reply({
							embed = {
								title = "Music Player - `skip`",
								description = "No music is playing.",
							},
							reference = { message = message, mention = true },
						})
					end
				end,
			},
			["unplay"] = {
				description = "Deletes the selected song from the queue",
				exec = function(message)
					ensure_state_exists(message.guild)

					-- check if the bot is connected to a voice channel
					if mp_state[message.guild.id].thread_handle then
						-- get the song index
						local args = message.content:split(" ")
						local index = tonumber(args[2])
						if not index then
							message:reply({
								embed = {
									title = "Music Player - `unplay`",
									description = "Invalid song index.",
								},
								reference = { message = message, mention = true },
							})
							return
						end

						-- check if the song index is valid
						if index < 1 or index > #mp_state[message.guild.id].songs then
							message:reply({
								embed = {
									title = "Music Player - `unplay`",
									description = "Invalid song index.",
								},
								reference = { message = message, mention = true },
							})
							return
						end

						-- remove the song from the queue
						table.remove(mp_state[message.guild.id].songs, index)

						-- react
						message:addReaction("✅")
					else
						-- reply that the player was not running
						message:reply({
							embed = {
								title = "Music Player - `unplay`",
								description = "No music is playing.",
							},
							reference = { message = message, mention = true },
						})
					end
				end,
			},
			["queue"] = {
				description = "Shows the songs that are queued",
				exec = function(message)
					ensure_state_exists(message.guild)

					-- check if the bot is connected to a voice channel
					if mp_state[message.guild.id].thread_handle then
						-- get page number
						local page = 0
						local args = message.content:split(" ")
						if args[2] then
							local _page = tonumber(args[2])
							if _page and _page > 1 then
								page = math.floor(_page - 1)
							end
						end

						if page > math.ceil(#mp_state[message.guild.id].songs / 12) then
							page = math.ceil(#mp_state[message.guild.id].songs / 12)
						end

						-- generate fields for queued songs
						local fields = {}
						for i = (page * 12) + 1, math.min(((page + 1) * 12), #mp_state[message.guild.id].songs) do
							local song = mp_state[message.guild.id].songs[i]

							local name = ""
							if i == 1 then
								name = "*" .. i .. ") " .. song.info.title
							else
								name = i .. ")  " .. song.info.title
							end

							local value = "Requested By: " .. song.user

							table.insert(fields, {
								name = name,
								value = value,
								inline = false,
							})
						end

						-- get total duration
						local total_duration = 0
						for _, song in ipairs(mp_state[message.guild.id].songs) do
							total_duration = total_duration + song.info.duration:toSeconds()
						end

						message:reply({
							embed = {
								title = "Music Player - Queue",
								description = "Page " .. (page + 1) .. "/" .. math.ceil(
									#mp_state[message.guild.id].songs / 12
								),
								fields = fields,
								footer = {
									text = "Total Duration: " .. Time.fromSeconds(total_duration):toString(),
								},
							},
							reference = { message = message, mention = true },
						})
					else
						-- reply that the player was not running
						message:reply({
							embed = {
								title = "Music Player - `queue`",
								description = "No music is playing.",
							},
							reference = { message = message, mention = true },
						})
					end
				end,
			},
			["np"] = {
				description = "Shows the currently playing song",
				exec = function(message)
					ensure_state_exists(message.guild)

					-- check if the bot is connected to a voice channel
					if mp_state[message.guild.id].thread_handle and mp_state[message.guild.id].songs[1] then
						-- get the currently playing song
						local song = mp_state[message.guild.id].songs[1]

						-- reply with the currently playing song
						message:reply({
							embed = {
								title = "Music Player - Now Playing",
								description = song.info.title,
								fields = {
									{
										name = "Requested by",
										value = song.user,
										inline = true,
									},
									{
										name = "Played",
										value = Time.fromMilliseconds(message.guild.connection._playElapsed):toString(),
										inline = true,
									},
									{
										name = "Duration",
										value = song.info.duration:toString(),
										inline = true,
									},
								},
							},
							reference = { message = message, mention = true },
						})
					else
						-- reply that the player was not running
						message:reply({
							embed = {
								title = "Music Player - `np`",
								description = "No music is playing.",
							},
							reference = { message = message, mention = true },
						})
					end
				end,
			},
			["bassboost"] = {
				description = "Sets the bassboost level",
				exec = function(message)
					ensure_state_exists(message.guild)

					local args = message.content:split(" ")
					if #args < 2 then
						message:reply({
							embed = {
								title = "Music Player - `bassboost`",
								description = "Expected a number as an argument.",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					local level = tonumber(args[2])
					if not level then
						message:reply({
							embed = {
								title = "Music Player - `bassboost`",
								description = "Expected a number as an argument.",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					if math.abs(level) > 20 then
						message:reply({
							embed = {
								title = "Music Player - `bassboost`",
								description = "Expected a number between -20 and 20.",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					mp_state[message.guild.id].tweaks.bassboost = level

					message:addReaction("✅")
				end,
			},
			["reverb"] = {
				description = "Enables or disables reverb",
				exec = function(message)
					ensure_state_exists(message.guild)

					local args = message.content:split(" ")
					if #args < 2 then
						message:reply({
							embed = {
								title = "Music Player - `reverb`",
								description = "Expected a boolean as an argument.",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					local enabled = args[2] == "true"
					if not enabled and args[2] ~= "false" then
						message:reply({
							embed = {
								title = "Music Player - `reverb`",
								description = "Expected a boolean as an argument.",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					mp_state[message.guild.id].tweaks.reverb = enabled

					message:addReaction("✅")
				end,
			},
			["loudnorm"] = {
				description = "Enables or disables loudness normalization",
				exec = function(message)
					ensure_state_exists(message.guild)

					local args = message.content:split(" ")
					if #args < 2 then
						message:reply({
							embed = {
								title = "Music Player - `loudnorm`",
								description = "Expected a boolean as an argument.",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					local enabled = args[2] == "true"
					if not enabled and args[2] ~= "false" then
						message:reply({
							embed = {
								title = "Music Player - `loudnorm`",
								description = "Expected a boolean as an argument.",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					mp_state[message.guild.id].tweaks.loudnorm = enabled

					message:addReaction("✅")
				end,
			},
			["tempo"] = {
				description = "Sets the tempo",
				exec = function(message)
					ensure_state_exists(message.guild)

					local args = message.content:split(" ")
					if #args < 2 then
						message:reply({
							embed = {
								title = "Music Player - `tempo`",
								description = "Expected a number as an argument.",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					local tempo = tonumber(args[2])
					if not tempo then
						message:reply({
							embed = {
								title = "Music Player - `tempo`",
								description = "Expected a number as an argument.",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					if tempo < 0.2 or tempo > 4 then
						message:reply({
							embed = {
								title = "Music Player - `tempo`",
								description = "Expected a number between 0.2 and 4.0",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					mp_state[message.guild.id].tweaks.tempo = tempo

					message:addReaction("✅")
				end,
			},
			["bitcrush"] = {
				description = "Sets the bitcrush level",
				exec = function(message)
					ensure_state_exists(message.guild)

					local args = message.content:split(" ")
					if #args < 2 then
						message:reply({
							embed = {
								title = "Music Player - `bitcrush`",
								description = "Expected a number as an argument.",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					local level = tonumber(args[2])
					if not level then
						message:reply({
							embed = {
								title = "Music Player - `bitcrush`",
								description = "Expected a number as an argument.",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					if level < 0 or level > 64 then
						message:reply({
							embed = {
								title = "Music Player - `bitcrush`",
								description = "Expected a number between 0 (off) and 64",
							},
							reference = { message = message, mention = true },
						})
						return
					end

					mp_state[message.guild.id].tweaks.bitcrush = math.floor(level)

					message:addReaction("✅")
				end,
			},
		},
		callbacks = {},
	}
end
