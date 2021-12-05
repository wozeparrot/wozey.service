  return {
    name = "wozeparrot/wozey.service",
    version = "0.1.0",
    description = "A Opinionated Discord Bot",
    tags = { "discord", "discord-bot" },
    license = "Apache2",
    author = { name = "Woze Parrot", email = "wozeparrot@gmail.com" },
    homepage = "https://github.com/wozeparrot/wozey.service",
    dependencies = {
        "SinisterRectus/discordia@2.9.1"
    },
    files = {
      "**.lua",
      "!test*"
    }
  }
  
