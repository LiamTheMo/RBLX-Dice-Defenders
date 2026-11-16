--!strict
-- Shop menu logic: pure, no Instances. Turns the server's Catalog.Shop offers plus the Meta / State balances into the View's
-- sections and decides what a price press does. The server checks every purchase again; nothing here sells or grants anything.

local ShopLogic = {}

export type Section = { Kind: string, Heading: string, Tab: string?, Items: { any }? }

-- Tab order and labels; icons are the View's job.
ShopLogic.TABS = {
	{ Id = "FEATURED", Label = "FEATURED" },
	{ Id = "GAMEPASSES", Label = "GAMEPASSES" },
	{ Id = "GEMS", Label = "GEMS" },
	{ Id = "SHARDS", Label = "SHARDS" },
}

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

local function soonHeading(tabId: string): string
	for _, tab in ShopLogic.TABS do
		if tab.Id == tabId then
			return tab.Label
		end
	end
	return "COMING SOON"
end

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
	return {
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
		table.insert(out, { Icon = BULLET_ICON[line.Kind] or "Chest", Text = text })
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

local function soon(tabId: string): { Section }
	return { { Kind = "Soon", Heading = soonHeading(tabId), Tab = tabId } }
end

function ShopLogic.sectionsFor(tabId: string, data: any): { Section }
	if data == nil then
		return soon(tabId)
	elseif tabId == "FEATURED" then
		local hero, cards = nil, {}
		for _, offer in data.Offers do
			if offer.Tab == "Featured" and offer.Currency == "Robux" then
				hero = hero or offer
			elseif offer.Tab == "Featured" then
				table.insert(cards, item(offer, data))
			end
		end
		local sections: { Section } = {}
		if hero then
			table.insert(sections, { Kind = "Hero", Heading = "STARTER PACK", Items = { item(hero, data, true) } })
		end
		if #cards > 0 then
			table.insert(sections, { Kind = "Cards", Heading = "OFFERS", Items = cards })
		end
		return if #sections > 0 then sections else soon(tabId)
	elseif tabId == "GEMS" then
		local cards = {}
		for _, offer in data.Offers do
			if offer.Tab == "Gems" then
				table.insert(cards, item(offer, data))
			end
		end
		return if #cards > 0 then { { Kind = "Cards", Heading = "GEMS", Items = cards } } else soon(tabId)
	end
	return soon(tabId) -- GAMEPASSES (none defined), SHARDS (crafting deferred), unknown
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
