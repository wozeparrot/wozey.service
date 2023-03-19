local https = require("https")
local log = require("discordia").Logger(3, "%F %T")

return function(client, state)
	return {
		name = "XKCD",
		description = "Returns XKCD comics",
		commands = {
			["xkcd"] = {
				description = "Returns a XKCD comic. Use `;xkcd <number>` to get a specific comic. Use `;xkcd` to get the latest comic.",
				exec = function(message)
					local args = message.content:split(" ")

					if not args[2] then
						-- stored response string
						local response = ""
						-- generate request
						local req = https.get({
							hostname = "xkcd.com",
							path = "/info.0.json",
							method = "GET",
							headers = {
								["Accept"] = "application/json",
							},
						}, function(res)
							-- append to response string
							res:on("data", function(chunk)
								response = response .. chunk
							end)
							-- run stuff
							res:on(
								"end",
								coroutine.wrap(function()
									-- parse returned json
									local comic = json.parse(response)

									message:reply({
										embed = {
											title = comic.title,
											description = comic.alt,
											image = {
												url = comic.img,
											},
											footer = {
												text = "XKCD #" .. comic.num,
											},
										},
									})
								end)
							)
						end)
						-- finish request
						req:done()
					else
						local num = tonumber(args[2])

						if num == nil then
							message:reply({
								embed = {
									title = "Error",
									description = "Invalid comic number",
								},
							})
							return
						end

						-- stored response string
						local response = ""
						-- generate request
						local req = https.get({
							hostname = "xkcd.com",
							path = "/" .. num .. "/info.0.json",
							method = "GET",
							headers = {
								["Accept"] = "application/json",
							},
						}, function(res)
							-- append to response string
							res:on("data", function(chunk)
								response = response .. chunk
							end)
							-- run stuff
							res:on(
								"end",
								coroutine.wrap(function()
									-- parse returned json
									local comic = json.parse(response)

									if comic == nil then
										message:reply({
											embed = {
												title = "Error",
												description = "Invalid comic number",
											},
										})
										return
									end

									message:reply({
										embed = {
											title = comic.title,
											description = comic.alt,
											image = {
												url = comic.img,
											},
											footer = {
												text = "XKCD #" .. comic.num,
											},
										},
									})
								end)
							)
						end)
						-- finish request
						req:done()
					end
				end,
			},
		},
		callbacks = {},
	}
end
