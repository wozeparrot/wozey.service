local Nibs = require("nibs")
local base64 = require("base64")

local state = {}

function state.new()
    local self = setmetatable({}, { __index = state })

    self.s = {}

    return self
end

function state:encode()
    return Nibs.encode(self.s)
end

function state:encodeString()
    return base64.encode(self:encode())
end

function state:decode(data)
    self.s = Nibs.decode(data)
end

function state:decodeString(data)
    self:decode(base64.decode(data))
end

function state:get(key)
    return self.s[key]
end

function state:set(key, value)
    self.s[key] = value
end

return state
