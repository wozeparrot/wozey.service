return {
	name = "wozeparrot/wozey.service",
	version = "0.1.0",
	description = "An Opinionated Discord Bot",
	tags = { "discord", "discord-bot" },
	license = "Apache2",
	author = { name = "Woze Parrot", email = "wozeparrot@gmail.com" },
	homepage = "https://github.com/wozeparrot/wozey.service",
	dependencies = {
		"creationix/coro-spawn@3.0.2",
	},
	files = {
		"**.lua",
		"!test*",
	},
}
