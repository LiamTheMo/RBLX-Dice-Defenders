-- The Shop rules (docs/_archive/MVP.md "Shop"). Pure, no yields. Buy: a Gold or Gems offer for the Buy remote, ONE Rewards.Apply
-- bundle (the price as a negative counter plus the grant), then Purchases. Receipt/Process: a Robux offer granted by a
-- Marketplace receipt, exactly once per PurchaseId (Profile.Receipts, newest Config/Shop.MaxReceipts). Prices and grants
-- come from Config/Shop: the client sends only an offer id.
local ShopConfig = require(script.Parent.Parent.Config.Shop)
local Rewards = require(script.Parent.Rewards)

local Shop = {}

Shop.MAX_RECEIPT_ID = 64 -- bytes of a stored PurchaseId

-- RemoteGuard validator for (offerId): a string of 1..16 bytes.
function Shop.Shape(offerId: any): boolean
	return type(offerId) == "string" and #offerId >= 1 and #offerId <= 16
end

local function bought(profile, offer): number
	local purchases = profile.Purchases
	return if type(purchases) == "table" and type(purchases[offer.Id]) == "number" then purchases[offer.Id] else 0
end

-- Pays and grants `offer` in one Rewards.Apply; a limited offer counts after it landed. Returns (ok, code?).
local function pay(profile, offer, price: number?): (boolean, string?)
	local bundle = table.clone(offer.Grant)
	if price then
		bundle[offer.Currency] = -price
	end
	local ok, code = Rewards.Apply(profile, bundle)
	if ok and offer.Limit then
		-- capped: a paid receipt past the limit still grants (below), and the save must stay within 0..Limit
		profile.Purchases[offer.Id] = math.min(offer.Limit, bought(profile, offer) + 1)
	end
	return ok, code
end

-- Buys a Gold or Gems offer. Codes: UnknownOffer, NotAvailable (Robux offers), SoldOut, then a Rewards.Apply code
-- (Insufficient, Overflow). A refusal leaves the profile untouched.
function Shop.Buy(profile: any, offerId: string): (boolean, string?)
	local offer = ShopConfig.ById[offerId]
	if offer == nil then
		return false, "UnknownOffer"
	elseif offer.Currency == "Robux" then
		return false, "NotAvailable"
	elseif offer.Limit and bought(profile, offer) >= offer.Limit then
		return false, "SoldOut"
	end
	return pay(profile, offer, offer.Price)
end

export type Io = { changed: () -> (), save: () -> boolean, warn: (string) -> () }

-- Grants a Robux `offer` for Marketplace `purchaseId` exactly once, then saves. Everything up to `save` is one no-yield
-- block; only io.save yields. Returns "PurchaseGranted" ONLY when the id is on the profile AND the save landed, else
-- "NotProcessedYet" (Roblox retries; the retry finds the id and only saves again). A receipt is always paid for: a
-- limited offer bought again past its Limit (two prompts, a second device, a stale Meta) still grants, because the
-- player was charged; the Limit only gates the client's prompt.
function Shop.Process(profile: any, offer: any, purchaseId: any, io: Io): string
	if type(purchaseId) ~= "string" or #purchaseId < 1 or #purchaseId > Shop.MAX_RECEIPT_ID then
		io.warn("[Shop] receipt with a bad PurchaseId")
		return "NotProcessedYet"
	end
	local receipts = profile.Receipts
	if table.find(receipts, purchaseId) == nil then
		local ok, code = pay(profile, offer, nil)
		if not ok then
			-- Overflow at the 1e9 cap: Roblox keeps retrying, so the grant lands once the player has room again.
			io.warn(`[Shop] cannot grant {offer.Id} for {purchaseId}: {tostring(code)}`)
			return "NotProcessedYet"
		end
		table.insert(receipts, purchaseId)
		while #receipts > ShopConfig.MaxReceipts do
			table.remove(receipts, 1)
		end
		io.changed()
	end
	return if io.save() == true then "PurchaseGranted" else "NotProcessedYet"
end

-- Process for a Marketplace ProductId; an unknown one is NotProcessedYet.
function Shop.ProcessProduct(profile: any, productId: any, purchaseId: any, io: Io): string
	local offer = ShopConfig.ByProduct[productId]
	if offer == nil then
		io.warn("[Shop] receipt for an unknown ProductId " .. tostring(productId))
		return "NotProcessedYet"
	end
	return Shop.Process(profile, offer, purchaseId, io)
end

return Shop
