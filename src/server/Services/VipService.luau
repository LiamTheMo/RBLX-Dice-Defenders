-- VIP game pass ownership per player: looked up once per join in its own thread (pcall, up to 3 tries) and cached,
-- then kept current by PromptGamePassPurchaseFinished. Readers only read the cache and never yield. A failed lookup
-- reads as "not VIP" (the player pays full price until they rejoin). Changed(player) fires when the answer changes.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Passes = require(script.Parent.Parent.Config.Passes)
local Signal = require(ReplicatedStorage.Shared.Core.Signal)

local VipService = {}

VipService.ATTEMPTS = 3
VipService.Changed = Signal.new()

local owned: { [Player]: boolean } = {} -- absent = not VIP

local function set(player: Player, value: boolean)
	if (owned[player] == true) ~= value then
		owned[player] = if value then true else nil
		VipService.Changed:Fire(player)
	end
end

-- Yields: run it in its own thread.
function VipService.Fetch(player: Player)
	if Passes.Vip.Id == 0 then
		return
	end
	local delay = 1
	for attempt = 1, VipService.ATTEMPTS do
		local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, Passes.Vip.Id)
		if player.Parent == nil then
			return
		end
		if ok and type(has) == "boolean" then
			set(player, has)
			return
		end
		warn(("[VipService] %s: pass lookup %d failed: %s"):format(tostring(player), attempt, tostring(has)))
		if attempt < VipService.ATTEMPTS then
			task.wait(delay)
			delay *= 2
		end
	end
end

function VipService.IsVip(player: Player): boolean
	return owned[player] == true
end

function VipService.Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(VipService.Fetch, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(VipService.Fetch, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passId == Passes.Vip.Id and Passes.Vip.Id ~= 0 then
			set(player, true)
		end
	end)
end

return VipService
