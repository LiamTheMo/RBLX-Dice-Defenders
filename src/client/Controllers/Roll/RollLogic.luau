--!strict
-- Roll menu logic: pure, no Instances. Display only: odds, prices, pity and every draw are the server's (Catalog.Roll,
-- Meta.Pity / RollAllowed / Gems, RollResult); nothing here decides anything.

local Display = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Display"))

local RollLogic = {}

-- Display order of the odds rows, top to bottom (the existing row art); also the rarity rank, best first.
RollLogic.ORDER = { "Secret", "Mythic", "Legendary", "Epic", "Rare", "Common" }
RollLogic.COUNTS = { 1, 10 } -- ROLL 1 and ROLL 10

-- Trailing zeros trimmed, at most `places` decimals (default 4): 0.01 -> "0.01%".
function RollLogic.pctText(n: number, places: number?): string
	local s = string.format(`%.{places or 4}f`, n)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s .. "%"
end

-- The pool with this id in Catalog.Roll.Pools, or nil (no Catalog yet). A malformed pool (e.g. from a server
-- mid-update) also reads as nil, so every caller can index Odds, Prices, Dice, Featured and Pity freely.
function RollLogic.pool(catalog: any, id: string): any
	local roll = type(catalog) == "table" and catalog.Roll
	for _, pool in if type(roll) == "table" and type(roll.Pools) == "table" then roll.Pools else {} do
		if type(pool) == "table" and pool.Id == id then
			local whole = type(pool.Odds) == "table"
				and type(pool.Prices) == "table"
				and type(pool.Dice) == "table"
				and type(pool.Featured) == "table"
				and type(pool.Pity) == "table"
			return if whole then pool else nil
		end
	end
	return nil
end

-- One row per ORDER rarity: the pool's basis points as a true percentage (Bp / 100); a rarity the pool leaves out is 0%.
-- No pool (no Catalog yet): no rows.
function RollLogic.oddsRows(pool: any): { { Rarity: string, Pct: number, Text: string } }
	local rows = {}
	if pool == nil then
		return rows
	end
	local bp = {}
	for _, odds in pool.Odds do
		bp[odds.Rarity] = odds.Bp
	end
	for i, rarity in RollLogic.ORDER do
		local pct = (bp[rarity] or 0) / 100
		rows[i] = { Rarity = rarity, Pct = pct, Text = RollLogic.pctText(pct) }
	end
	return rows
end

-- Gems for `count` rolls of the pool, or nil.
function RollLogic.price(pool: any, count: number): number?
	for _, p in if pool then pool.Prices else {} do
		if p.Count == count then
			return p.Gems
		end
	end
	return nil
end

function RollLogic.canAfford(gems: number?, price: number?): boolean
	return gems ~= nil and price ~= nil and gems >= price
end

-- The two ROLL buttons: { Count, Price (Gems, or "-" before the Catalog), Enabled = allowed and affordable }.
function RollLogic.buttons(
	pool: any,
	gems: number?,
	allowed: boolean
): { { Count: number, Price: any, Enabled: boolean } }
	local list = {}
	for i, count in RollLogic.COUNTS do
		local price = RollLogic.price(pool, count)
		list[i] = { Count = count, Price = price or "-", Enabled = allowed and RollLogic.canAfford(gems, price) }
	end
	return list
end

-- Rolls toward the pool's guarantee from Meta.Pity ({{Pool, Count}}); 0 when absent.
function RollLogic.pityCount(meta: any, poolId: string): number
	for _, row in if meta and meta.Pity then meta.Pity else {} do
		if row.Pool == poolId and type(row.Count) == "number" then
			return row.Count
		end
	end
	return 0
end

function RollLogic.pityText(count: number, max: number): string
	return `{count} / {max}`
end

function RollLogic.pityFraction(count: number, max: number): number
	if max <= 0 then
		return 0
	end
	return math.clamp(count / max, 0, 1)
end

local function tile(id: string, rarity: string)
	local info = Display.Dice[id]
	return { Id = id, Rarity = rarity, Name = if info then info.Name else id }
end

-- The pool's Featured ids as tiles { Id, Rarity, Name } (rarity from the pool's dice).
function RollLogic.featured(pool: any): { any }
	local list = {}
	if pool == nil then
		return list
	end
	local rarity = {}
	for _, d in pool.Dice do
		rarity[d.Id] = d.Rarity
	end
	for _, id in pool.Featured do
		table.insert(list, tile(id, rarity[id] or "Legendary"))
	end
	return list
end

local function rank(rarity: string): number
	return table.find(RollLogic.ORDER, rarity) or #RollLogic.ORDER + 1
end

-- RollResult rows -> the three featured slots: one result in the middle; more show the three rarest (new first, then
-- roll order), the best in the middle. Slots may be empty (nil).
function RollLogic.resultTiles(results: { any }): { [number]: any }
	local order = {}
	for i, r in results do
		order[i] = { r = r, i = i }
	end
	table.sort(order, function(a, b)
		if rank(a.r.Rarity) ~= rank(b.r.Rarity) then
			return rank(a.r.Rarity) < rank(b.r.Rarity)
		elseif a.r.New ~= b.r.New then
			return a.r.New == true
		end
		return a.i < b.i
	end)
	local slots = {}
	for k, slot in { 2, 1, 3 } do
		local entry = order[k]
		if entry then
			slots[slot] = tile(entry.r.Id, entry.r.Rarity)
		end
	end
	return slots
end

-- Short toast for a RollResult: "+1 Frost (new)", "+1 Pebble", "+10 dice (2 new)".
function RollLogic.resultToast(results: { any }): string
	if #results == 1 then
		local r = results[1]
		return `+1 {tile(r.Id, r.Rarity).Name}` .. (if r.New then " (new)" else "")
	end
	local new = 0
	for _, r in results do
		if r.New then
			new += 1
		end
	end
	return `+{#results} dice` .. (if new > 0 then ` ({new} new)` else "")
end

return RollLogic
