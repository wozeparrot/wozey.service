local Nibs = require("nibs")

local state = {}

function state.new()
    local self = setmetatable({}, { __index = state })

    self._state = {}

    return self
end

function state:encode()
    return Nibs.encode(self._state)
end

function state:decode(data)
    self._state = Nibs.decode(data)
end

function state:get(key)
    return self._state[key]
end

function state:set(key, value)
    self._state[key] = value
end

return state
