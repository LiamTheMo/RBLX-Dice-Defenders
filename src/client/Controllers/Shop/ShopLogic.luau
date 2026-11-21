--!strict
-- Shop menu logic: pure, no Instances. Turns the server's Catalog.Shop offers plus the Meta / State balances into the View's
-- sections and decides what a price press does. The server checks every purchase again; nothing here sells or grants anything.

local ShopLogic = {}

ShopLogic.VIP_ID = "VipPass" -- View item id of the VIP game pass card (not a Catalog.Shop offer)

export type Section = { Kind: string, Heading: string, Items: { any }? }

-- Product art per offer (View ART keys); an offer not listed shows the gem bag.
local ART = {
	Starter = "HeroArt",
	Gems400 = "Gems3",
	Gems1200 = "GemBag",
	Gems3500 = "ChestOpenGems",
	XpTome1 = "Potion",
	XpTome3 = "Potion",
	Frag20 = "Clover",
}
-- Hero bullet icon per Rewards.Lines Kind (View BULLET keys).
local BULLET_ICON = { Gems = "Gem", Gold = "Coin", Die = "Dice3", Xp = "Potion", Item = "Potion" }
local LABEL = { Owned = "Owned", Unavailable = "Not available yet" }

-- Whole number with thousands commas: 1200 -> "1,200". Floors; never negative.
function ShopLogic.priceText(n: number): string
	local s = tostring(math.max(0, math.floor(n)))
	while true do
		local r, count = string.gsub(s, "^(%d+)(%d%d%d)", "%1,%2")
		s = r
		if count == 0 then
			return s
		end
	end
end

-- The live inputs of one render, or nil until the Catalog (with its Shop) has arrived. `meta` and `snap` may be nil.
function ShopLogic.data(catalog: any, meta: any, snap: any): any?
	if type(catalog) ~= "table" or type(catalog.Shop) ~= "table" then
		return nil
	end
	local bought = {}
	if type(meta) == "table" and type(meta.Purchases) == "table" then
		for _, row in meta.Purchases do
			bought[row.Id] = row.Count
		end
	end
	local owned = type(meta) == "table" and type(meta.RollDiscountPct) == "number" and meta.RollDiscountPct > 0
	return {
		Vip = { Owned = owned, Offer = if type(meta) == "table" then meta.VipOffer else nil }, -- the VIP game pass (Meta)
		Catalog = catalog,
		Offers = catalog.Shop.Offers,
		Bought = bought,
		Gold = if type(snap) == "table" then snap.Gold else nil,
		Gems = if type(meta) == "table" then meta.Gems else nil,
	}
end

-- "Owned" (limit reached), "Unavailable" (Robux offer without a product), "Poor" (balance below the price) or "Ready".
function ShopLogic.status(offer: any, data: any): string
	if offer.Limit ~= nil and (data.Bought[offer.Id] or 0) >= offer.Limit then
		return "Owned"
	elseif offer.Currency == "Robux" then
		return if offer.Available then "Ready" else "Unavailable"
	end
	local balance = data[offer.Currency]
	return if type(balance) == "number" and balance >= offer.Price then "Ready" else "Poor"
end

function ShopLogic.offer(data: any, id: any): any?
	if data ~= nil then
		for _, offer in data.Offers do
			if offer.Id == id then
				return offer
			end
		end
	end
	return nil
end

-- What a price press does: ("Toast", text), ("Buy") for a Gold / Gems offer, ("Prompt", productId) for a Robux one.
function ShopLogic.press(offer: any?, data: any): (string, any?)
	if offer == nil then
		return "Toast", "Shop is loading"
	end
	local status = ShopLogic.status(offer, data)
	if status == "Owned" then
		return "Toast", "Already owned"
	elseif status == "Unavailable" then
		return "Toast", LABEL.Unavailable
	elseif status == "Poor" then
		return "Toast", "Not enough " .. offer.Currency
	end
	return if offer.Currency == "Robux" then "Prompt" else "Buy", offer.ProductId
end

-- Display name of the thing a rewards line gives (Catalog lookup by Id), "" if unknown.
local function nameOf(catalog: any, line: any): string
	local list = ({
		Die = catalog.Dice,
		Item = catalog.Items,
		Material = catalog.Materials,
		Cosmetic = catalog.Cosmetics,
	})[line.Kind]
	for _, entry in list or {} do
		if entry.Id == line.Id then
			return entry.Name
		end
	end
	return ""
end

local function bullets(catalog: any, offer: any): { any }
	local out = {}
	for _, line in offer.Rewards do
		local amount = ShopLogic.priceText(line.Amount)
		local text
		if line.Kind == "Gold" or line.Kind == "Gems" then
			text = `{amount} {line.Kind}`
		elseif line.Kind == "Xp" then
			text = `{amount} XP`
		elseif line.Kind == "Die" then
			text = `{amount} {nameOf(catalog, line)} Die`
		else
			text = `{amount} {nameOf(catalog, line)}`
		end
		table.insert(out, {
			Icon = BULLET_ICON[line.Kind] or "Chest",
			Text = text,
			DieId = if line.Kind == "Die" then line.Id else nil,
		})
	end
	return out
end

-- One View item for an offer: price + currency, art, and the button state (Label replaces the price when set).
local function item(offer: any, data: any, withBullets: boolean?): any
	local status = ShopLogic.status(offer, data)
	return {
		Id = offer.Id,
		Name = offer.Name,
		Price = offer.Price,
		Currency = offer.Currency,
		Art = ART[offer.Id] or "GemBag",
		Label = LABEL[status],
		Enabled = status == "Ready",
		Bullets = if withBullets then bullets(data.Catalog, offer) else nil,
	}
end

-- The VIP game pass card (Id "VipPass"): Robux price, or "Owned" once the pass is held.
function ShopLogic.vipItem(data: any): any
	local vip = data.Vip
	local offer = vip.Offer
	return {
		Id = ShopLogic.VIP_ID,
		Name = "VIP",
		Price = if offer then offer.Robux else 0,
		Currency = "Robux",
		Art = "VipPass",
		Desc = `{if offer then offer.Pct else 10}% off every\nroll, forever`,
		Label = if vip.Owned then LABEL.Owned else nil,
		Enabled = not vip.Owned,
	}
end

function ShopLogic.sections(data: any): { Section }
	if data == nil then
		return { { Kind = "Loading", Heading = "Loading shop…" } }
	end
	local hero, offers, gems = nil, {}, {}
	for _, offer in data.Offers do
		if offer.Id == "Starter" then
			hero = offer
		elseif offer.Tab == "Featured" then
			table.insert(offers, item(offer, data))
		elseif offer.Tab == "Gems" then
			table.insert(gems, item(offer, data))
		end
	end
	local sections: { Section } = {}
	if hero then
		table.insert(sections, { Kind = "Hero", Heading = "STARTER PACK", Items = { item(hero, data, true) } })
	end
	if #offers > 0 then
		table.insert(sections, { Kind = "Cards", Heading = "OFFERS", Items = offers })
	end
	if #gems > 0 then
		table.insert(sections, { Kind = "Cards", Heading = "GEMS", Items = gems })
	end
	local vip = data.Vip
	if vip.Owned or vip.Offer then
		table.insert(sections, { Kind = "Cards", Heading = "GAMEPASSES", Items = { ShopLogic.vipItem(data) } })
	else
		table.insert(sections, { Kind = "Soon", Heading = "GAMEPASSES" })
	end
	table.insert(sections, { Kind = "Soon", Heading = "SHARDS" })
	return sections
end

local function data_vip(data: any): string
	return `{data.Vip.Owned}:{data.Vip.Offer ~= nil}`
end

-- Changes whenever a render would look different (offers' states and their prices): the controller redraws only then.
function ShopLogic.key(data: any?): string
	if data == nil then
		return "-"
	end
	local parts = {}
	for _, offer in data.Offers do
		table.insert(parts, `{offer.Id}:{ShopLogic.status(offer, data)}`)
	end
	table.insert(parts, `vip:{data_vip(data)}`)
	return table.concat(parts, "|")
end

-- One flight at a time: begin() is true once until finish().
function ShopLogic.guard(): { begin: () -> boolean, finish: () -> () }
	local busy = false
	return {
		begin = function()
			if busy then
				return false
			end
			busy = true
			return true
		end,
		finish = function()
			busy = false
		end,
	}
end

return ShopLogic
