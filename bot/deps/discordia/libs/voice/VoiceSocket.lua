local uv = require("uv")
local class = require("class")
local timer = require("timer")
local enums = require("enums")

local WebSocket = require("client/WebSocket")

local logLevel = assert(enums.logLevel)
local format = string.format
local setInterval, clearInterval = timer.setInterval, timer.clearInterval
local wrap = coroutine.wrap
local time = os.time
local unpack, pack = string.unpack, string.pack -- luacheck: ignore

local ENCRYPTION_MODE = "xsalsa20_poly1305"

local IDENTIFY = 0
local SELECT_PROTOCOL = 1
local READY = 2
local HEARTBEAT = 3
local DESCRIPTION = 4
local SPEAKING = 5
local HEARTBEAT_ACK = 6
local RESUME = 7
local HELLO = 8
local RESUMED = 9
local USER_DISCONNECT = 13

local function checkMode(modes)
    for _, mode in ipairs(modes) do
        if mode == ENCRYPTION_MODE then
            return mode
        end
    end
end

local VoiceSocket = class("VoiceSocket", WebSocket)

for name in pairs(logLevel) do
    VoiceSocket[name] = function(self, fmt, ...)
        local client = self._client
        return client[name](client, format("Voice : %s", fmt), ...)
    end
end

function VoiceSocket:__init(state, connection, manager)
    WebSocket.__init(self, manager)
    self._state = state
    self._manager = manager
    self._client = manager._client
    self._connection = connection
    self._session_id = state.session_id
    self._handshaked = false
end

function VoiceSocket:handleDisconnect()
    -- TODO: reconnecting and resuming
    self._connection:_cleanup()
end

function VoiceSocket:handlePayload(payload)
    local manager = self._manager

    local d = payload.d
    local op = payload.op

    self:debug("WebSocket OP %s", op)

    if op == HELLO then
        self:info("Received HELLO")
        self:startHeartbeat(d.heartbeat_interval * 0.75) -- NOTE: hotfix for API bug
        self:identify()
    elseif op == READY then
        self:info("Received READY")
        local mode = checkMode(d.modes)
        if mode then
            self._mode = mode
            self._ssrc = d.ssrc
            self:handshake(d.ip, d.port)
        else
            self:error("No supported encryption mode available")
            self:disconnect()
        end
    elseif op == RESUMED then
        self:info("Received RESUMED")
    elseif op == DESCRIPTION then
        if d.mode == self._mode then
            self._connection:_prepare(d.secret_key, self)
        else
            self:error("%q encryption mode not available", self._mode)
            self:disconnect()
        end
    elseif op == HEARTBEAT_ACK then
        manager:emit("heartbeat", nil, self._sw.milliseconds) -- TODO: id
    elseif op == SPEAKING then
        self._connection:updateUserSsrc(d.user_id, d.ssrc)
    elseif op == USER_DISCONNECT then
        self._connection:removeUserSsrc(d.user_id)
    elseif op == 12 then
        return -- ignore
    elseif op then
        self:warning("Unhandled WebSocket payload OP %i", op)
    end
end

local function loop(self)
    return wrap(self.heartbeat)(self)
end

function VoiceSocket:startHeartbeat(interval)
    if self._heartbeat then
        clearInterval(self._heartbeat)
    end
    self._heartbeat = setInterval(interval, loop, self)
end

function VoiceSocket:stopHeartbeat()
    if self._heartbeat then
        clearInterval(self._heartbeat)
    end
    self._heartbeat = nil
end

function VoiceSocket:heartbeat()
    self._sw:reset()
    return self:_send(HEARTBEAT, time())
end

function VoiceSocket:identify()
    local state = self._state
    return self:_send(IDENTIFY, {
        server_id = state.guild_id,
        user_id = state.user_id,
        session_id = state.session_id,
        token = state.token,
    }, true)
end

function VoiceSocket:resume()
    local state = self._state
    return self:_send(RESUME, {
        server_id = state.guild_id,
        session_id = state.session_id,
        token = state.token,
    })
end

function VoiceSocket:handshake(server_ip, server_port)
    local udp = uv.new_udp()
    self._udp = udp
    self._ip = server_ip
    self._port = server_port
    udp:recv_start(function(err, data)
        if not self._handshaked then
            -- handshake
            assert(not err, err)
            self._handshaked = true
            local client_ip = unpack("xxxxxxxxz", data)
            local client_port = unpack("<I2", data, -2)
            return wrap(self.selectProtocol)(self, client_ip, client_port)
        else
            -- voice data
            assert(not err, err)

            if not data then
                return
            end

            return wrap(self._connection.receivePacket)(self._connection, data)
        end
    end)
    local packet = pack(">I2I2I4c64H", 0x1, 70, self._ssrc, self._ip, self._port)
    return udp:send(packet, server_ip, server_port)
end

function VoiceSocket:selectProtocol(address, port)
    return self:_send(SELECT_PROTOCOL, {
        protocol = "udp",
        data = {
            address = address,
            port = port,
            mode = self._mode,
        },
    })
end

function VoiceSocket:setSpeaking(speaking)
    return self:_send(SPEAKING, {
        speaking = speaking,
        delay = 0,
        ssrc = self._ssrc,
    })
end

return VoiceSocket
