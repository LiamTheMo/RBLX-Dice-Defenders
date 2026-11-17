-- Roll pools (docs/MVP.md "Roll"; *tune*). Server-only: clients see the Catalog projection, never this module.
-- Odds are basis points per rarity for one roll (they sum to 10000); the dice of a rarity are every Config/Dice entry
-- of that rarity, drawn uniformly. Pity: a roll after Pity.Max - 1 in a row without a Pity.Rarity die is one of them
-- (the counter resets on any). Featured lists grantable ids only. Mythic and Secret stay at 0: nothing is drawable there.
local Dice = require(script.Parent.Dice)

local Roll = {}

local function freeze(t)
	for _, v in t do
		if type(v) == "table" and not table.isfrozen(v) then
			freeze(v)
		end
	end
	return table.freeze(t)
end

-- Adds Dice = {{Id, Rarity}} (sorted by Id) and ByRarity = {[rarity] = {ids}} for every rarity with weight.
local function pool(def)
	local byRarity, dice, ids = {}, {}, {}
	for _, odds in def.Odds do
		if odds.Bp > 0 then
			byRarity[odds.Rarity] = {}
		end
	end
	for id in Dice.Types do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local rarity = Dice.Types[id].rarity
		if byRarity[rarity] and not Dice.Types[id].retired then
			table.insert(byRarity[rarity], id)
			table.insert(dice, { Id = id, Rarity = rarity })
		end
	end
	def.ByRarity, def.Dice = byRarity, dice
	return freeze(def)
end

Roll.Pools = freeze({
	pool({
		Id = "Standard",
		Name = "Standard",
		Prices = { { Count = 1, Gems = 100 }, { Count = 10, Gems = 900 } },
		Odds = { -- draw order; Rules/Roll walks it against one roll of 1..10000
			{ Rarity = "Common", Bp = 4000 },
			{ Rarity = "Rare", Bp = 4500 },
			{ Rarity = "Epic", Bp = 1400 },
			{ Rarity = "Legendary", Bp = 100 },
			{ Rarity = "Mythic", Bp = 0 },
			{ Rarity = "Secret", Bp = 0 },
		},
		Pity = { Rarity = "Legendary", Max = 80 },
		Featured = { "L01", "L02" },
	}),
})

local byId = {}
for _, p in Roll.Pools do
	byId[p.Id] = p
end
Roll.ById = table.freeze(byId)

return table.freeze(Roll)
