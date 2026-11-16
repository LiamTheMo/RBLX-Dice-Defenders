-- Robux purchases: the ONLY code path that may yield in the Shop. MarketplaceService.ProcessReceipt runs
-- Rules/Shop.ProcessProduct (the grant is one no-yield block), then saves the profile at once and answers
-- PurchaseGranted only if the save landed. Never trusts anything but the receipt Roblox signs.

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ShopConfig = require(script.Parent.Parent.Config.Shop)
local Shop = require(script.Parent.Parent.Rules.Shop)
local ProfileService = require(script.Parent.ProfileService)

local ShopService = {}

local function io(player: Player)
	return {
		changed = function()
			ProfileService.MarkChanged(player)
		end,
		save = function(): boolean
			return (ProfileService.SaveNow(player)) == true
		end,
		warn = function(message: string)
			warn(message)
		end,
	}
end

local function decision(result: string): Enum.ProductPurchaseDecision
	return if result == "PurchaseGranted"
		then Enum.ProductPurchaseDecision.PurchaseGranted
		else Enum.ProductPurchaseDecision.NotProcessedYet
end

local function processReceipt(receipt): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local profile = player and ProfileService.Get(player)
	if player == nil or profile == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox retries when they are back
	end
	return decision(Shop.ProcessProduct(profile, receipt.ProductId, receipt.PurchaseId, io(player)))
end

-- Studio only: the same grant code for a Robux offer, with a fake PurchaseId. Not a remote; from the command bar call
-- game.ServerStorage.StudioGrant:Invoke(player, offerId).
-- Yields (the save). Returns the same decision string as a receipt.
function ShopService.StudioGrant(player: Player, offerId: string): string
	if not RunService:IsStudio() then
		error("ShopService.StudioGrant is Studio-only")
	end
	local offer = ShopConfig.ById[offerId]
	local profile = ProfileService.Get(player)
	if offer == nil or offer.Currency ~= "Robux" or profile == nil then
		error("StudioGrant: unknown Robux offer or profile not loaded")
	end
	return Shop.Process(profile, offer, "studio-" .. HttpService:GenerateGUID(false), io(player))
end

function ShopService.Start()
	MarketplaceService.ProcessReceipt = processReceipt
	if RunService:IsStudio() then
		-- The command bar gets its own module copies (no loaded profiles), so it reaches the game's StudioGrant
		-- through this ServerStorage BindableFunction; ServerStorage never replicates to clients.
		local bindable = Instance.new("BindableFunction")
		bindable.Name = "StudioGrant"
		bindable.OnInvoke = ShopService.StudioGrant
		bindable.Parent = game:GetService("ServerStorage")
	end
end

return ShopService
