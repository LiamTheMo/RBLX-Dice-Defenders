-- Recording stand-in for TeleportGateway (same method names). Never teleports; `calls` lists what was asked.
-- `failNext` makes the next N calls return (false, reason).

local InMemoryTeleport = {}
InMemoryTeleport.__index = InMemoryTeleport

function InMemoryTeleport.new()
	return setmetatable({ calls = {}, failNext = 0, _reserved = 0 }, InMemoryTeleport)
end

function InMemoryTeleport:_record(call): boolean
	table.insert(self.calls, call)
	if self.failNext > 0 then
		self.failNext -= 1
		return false
	end
	return true
end

function InMemoryTeleport:ReserveServer(placeId: number)
	if not self:_record({ Kind = "Reserve", PlaceId = placeId }) then
		return false, "simulated failure"
	end
	self._reserved += 1
	return true, "code-" .. self._reserved
end

function InMemoryTeleport:TeleportPlayerToReserved(player, accessCode: string, teleportData: any, placeId: number)
	local call =
		{ Kind = "Reserved", Player = player, AccessCode = accessCode, TeleportData = teleportData, PlaceId = placeId }
	if not self:_record(call) then
		return false, "simulated failure"
	end
	return true
end

function InMemoryTeleport:TeleportToLobby(player, teleportData: any?)
	if not self:_record({ Kind = "Lobby", Player = player, TeleportData = teleportData }) then
		return false, "simulated failure"
	end
	return true
end

return InMemoryTeleport
