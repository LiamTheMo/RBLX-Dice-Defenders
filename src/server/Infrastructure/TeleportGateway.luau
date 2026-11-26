-- The only module that calls TeleportService for Duels. pcall + retry; every call returns
-- (ok, valueOrReason). Studio cannot teleport; specs use InMemoryTeleport (same method names).

local TeleportGateway = {}
TeleportGateway.__index = TeleportGateway

TeleportGateway.MAX_ATTEMPTS = 3
TeleportGateway.BASE_DELAY_SECONDS = 1

export type Options = {
	service: any?, -- TeleportService or a stand-in
	lobbyPlaceId: number?,
	sleep: ((number) -> ())?,
	maxAttempts: number?,
	baseDelay: number?,
}

function TeleportGateway.new(options: Options)
	return setmetatable({
		_service = options.service or game:GetService("TeleportService"),
		_lobbyPlaceId = options.lobbyPlaceId or game.PlaceId,
		_sleep = options.sleep or task.wait,
		_maxAttempts = options.maxAttempts or TeleportGateway.MAX_ATTEMPTS,
		_baseDelay = options.baseDelay or TeleportGateway.BASE_DELAY_SECONDS,
	}, TeleportGateway)
end

function TeleportGateway:_call(fn: () -> any)
	local lastError
	for attempt = 1, self._maxAttempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < self._maxAttempts then
			self._sleep(self._baseDelay * 2 ^ (attempt - 1))
		end
	end
	return false, tostring(lastError)
end

-- (true, accessCode) or (false, reason).
function TeleportGateway:ReserveServer(placeId: number)
	return self:_call(function()
		return self._service:ReserveServer(placeId)
	end)
end

-- (true) or (false, reason).
function TeleportGateway:TeleportPlayerToReserved(
	player: Player,
	accessCode: string,
	teleportData: any,
	placeId: number
)
	local ok, result = self:_call(function()
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = accessCode
		options:SetTeleportData(teleportData)
		self._service:TeleportAsync(placeId, { player }, options)
	end)
	return ok, if ok then nil else result
end

function TeleportGateway:TeleportToLobby(player: Player, teleportData: any?)
	local ok, result = self:_call(function()
		local options
		if teleportData ~= nil then
			options = Instance.new("TeleportOptions")
			options:SetTeleportData(teleportData)
		end
		self._service:TeleportAsync(self._lobbyPlaceId, { player }, options)
	end)
	return ok, if ok then nil else result
end

return TeleportGateway
