
local discordia = require("discordia")
local classes = discordia.class.classes
local VoiceSocket = classes.VoiceSocket

local ENCRYPTION_MODE = 'xsalsa20_poly1305'
local READY           = 2
local DESCRIPTION     = 4
local SPEAKING        = 5
local HEARTBEAT_ACK   = 6
local HELLO           = 8
local RESUMED         = 9

local function checkMode(modes)
	for _, mode in ipairs(modes) do
		if mode == ENCRYPTION_MODE then
			return mode
		end
	end
end

local reconnectCodes = {
	[4006] = true;
	[4009] = true;
	[4014] = true;
}

function VoiceSocket:handleDisconnect(url, path, code)
	-- TODO: reconnecting and resuming
	local connection = self._connection
	local channel = connection and connection._channel
	local guild = channel and channel._parent
	if (not code) or reconnectCodes[code] then -- for reconnecting
		if not channel then return end
		channel._connection = nil
		if not guild then return end
		guild._reconnect = true
		guild._connection = nil
		guild._oldConnection = connection
		return
	elseif guild then
		guild._disconnected = true
	end
	connection:_cleanup()
end

function VoiceSocket:handlePayload(payload)

	local manager = self._manager

	local d = payload.d
	local op = payload.op

	self:debug('WebSocket OP %s', op)

	if op == HELLO then

		self:info('Received HELLO')
		self:startHeartbeat(d.heartbeat_interval * 0.75) -- NOTE: hotfix for API bug
		self:identify()

	elseif op == READY then

		self:info('Received READY')
		local mode = checkMode(d.modes)
		if mode then
			self._mode = mode
			self._ssrc = d.ssrc
			self:handshake(d.ip, d.port)
		else
			self:error('No supported encryption mode available')
			self:disconnect()
		end

	elseif op == RESUMED then

		self:info('Received RESUMED')

	elseif op == DESCRIPTION then

		if d.mode == self._mode then
			local connection = self._connection
			local prepare = connection._prepare or VoiceSocket._prepare
			if connection and prepare then
				prepare(connection,d.secret_key, self)
			end
		else
			self:error('%q encryption mode not available', self._mode)
			self:disconnect()
		end

	elseif op == HEARTBEAT_ACK then

		manager:emit('heartbeat', nil, self._sw.milliseconds) -- TODO: id

	elseif op == SPEAKING then

		return -- TODO

	elseif op == 12 or op == 13 or op == 14 then

		return -- ignore

	elseif op then

		self:warning('Unhandled WebSocket payload OP %i', op)

	end

end
