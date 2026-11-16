-- Shop offers (docs/MVP.md "Shop"; *tune*). Server-only: clients see the Catalog projection (ProductId included, it is no secret).
--   Id        1..16 ASCII bytes, never reused (keys Purchases)
--   Tab       "Featured" | "Gems" (the Shop tab that lists it)
--   Currency  "Gold" | "Gems" (Remote Buy pays it) | "Robux" (only Marketplace receipts grant it; Price is display only)
--   Grant     Rules/Rewards bundle given on purchase
--   Limit     optional: purchases per account (Profile.Purchases)
--   ProductId developer product id of a Robux offer. EMPTY until the owner provides the real ids: an offer without
--             one is not available (the client shows "Not available yet"). Never invent one.
local Rewards = require(script.Parent.Parent.Rules.Rewards)
local Validate = require(script.Parent.Parent.Rules.Validate)

local Shop = {}

Shop.MaxReceipts = 100 -- newest Marketplace PurchaseIds kept per profile (Profile.Receipts)

local function offer(fields)
	table.freeze(fields.Grant)
	return table.freeze(fields)
end

local list = {
	offer({
		Id = "XpTome1",
		Tab = "Featured",
		Name = "XP Tome",
		Currency = "Gold",
		Price = 300, -- *tune*; Sell x count stays below it (spec)
		Grant = { Items = table.freeze({ XpTome = 1 }) },
	}),
	offer({
		Id = "Frag20",
		Tab = "Featured",
		Name = "20 Fragments",
		Currency = "Gold",
		Price = 100, -- *tune*
		Grant = { Materials = table.freeze({ Fragment = 20 }) },
	}),
	offer({
		Id = "XpTome3",
		Tab = "Featured",
		Name = "3 XP Tomes",
		Currency = "Gems",
		Price = 40, -- *tune*
		Grant = { Items = table.freeze({ XpTome = 3 }) },
	}),
	offer({
		Id = "Starter",
		Tab = "Featured",
		Name = "Starter Pack",
		Currency = "Robux",
		Price = 399,
		Limit = 1,
		ProductId = nil, -- owner: real developer product id
		Grant = { Gems = 1200, Gold = 2000, Dice = table.freeze({ R01 = 1 }) },
	}),
	offer({
		Id = "Gems400",
		Tab = "Gems",
		Name = "400 Gems",
		Currency = "Robux",
		Price = 99,
		ProductId = nil, -- owner
		Grant = { Gems = 400 },
	}),
	offer({
		Id = "Gems1200",
		Tab = "Gems",
		Name = "1,200 Gems",
		Currency = "Robux",
		Price = 249,
		ProductId = nil, -- owner
		Grant = { Gems = 1200 },
	}),
	offer({
		Id = "Gems3500",
		Tab = "Gems",
		Name = "3,500 Gems",
		Currency = "Robux",
		Price = 699,
		ProductId = nil, -- owner
		Grant = { Gems = 3500 },
	}),
}

local byId, byProduct = {}, {}
for _, o in list do
	assert(string.match(o.Id, "^%w+$") and #o.Id <= 16 and not byId[o.Id], "Shop: bad or taken id " .. o.Id)
	assert(o.Tab == "Featured" or o.Tab == "Gems", "Shop: bad Tab on " .. o.Id)
	assert(o.Currency == "Gold" or o.Currency == "Gems" or o.Currency == "Robux", "Shop: bad Currency on " .. o.Id)
	assert(Validate.IsInt(o.Price, 1, Validate.MAX_INT), "Shop: bad Price on " .. o.Id)
	assert(o.Limit == nil or Validate.IsInt(o.Limit, 1, Validate.MAX_INT), "Shop: bad Limit on " .. o.Id)
	assert(Rewards.Valid(o.Grant), "Shop: bad Grant on " .. o.Id)
	assert(o.Currency == "Robux" or o.ProductId == nil, "Shop: ProductId on a currency offer " .. o.Id)
	-- Rules/Shop pays by setting Grant[Currency] = -Price, which would silently replace such a grant
	assert(o.Currency == "Robux" or o.Grant[o.Currency] == nil, "Shop: offer grants its own price currency " .. o.Id)
	if o.ProductId ~= nil then
		assert(Validate.IsInt(o.ProductId, 1, 2 ^ 52) and not byProduct[o.ProductId], "Shop: bad ProductId " .. o.Id)
		byProduct[o.ProductId] = o
	end
	byId[o.Id] = o
end

Shop.Offers = table.freeze(list)
Shop.ById = table.freeze(byId)
Shop.ByProduct = table.freeze(byProduct) -- {[productId] = offer}; empty while no ids are set

return table.freeze(Shop)
