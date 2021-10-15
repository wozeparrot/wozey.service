local https = require("https")
local json = require("json")

return function(client) return {
    name = "Polls",
    description = "Create polls that people can vote on",
    commands = {
        ["poll-create"] = {
            description = "Create a poll",
            exec = function(message)
            end
        },
        ["poll-oadd"] = {
            description = "Add an option to a poll",
            exec = function(message)
            end
        },
        ["poll-orem"] = {
            description = "Remove an option from a poll",
            exec = function(message)
            end
        },
        ["poll-send"] = {
            description = "Send a poll into a chennel for voting",
            exec = function(message)
            end
        },
        ["poll-end"] = {
            description = "End voting on a poll",
            exec = function(message)
            end
        }
    },
    callbacks = {}
}end
