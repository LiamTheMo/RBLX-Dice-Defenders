-- The single bundle writer: a reward or cost lands on the profile whole or not at
-- all. Pure, no yields.
--   Bundle = { Gold?, Gems?, Xp?, Materials? = { [id] = n }, Items? = { [id] = n },
--              Dice? = { [id] = n }, Cosmetics? = { [id] = true } }
-- Gold, Gems, Materials and Items may be negative (costs); Xp and Dice only gain.
local Dice = require(script.Parent.Parent.Config.Dice)
local Inventory = require(script.Parent.Parent.Config.Inventory)
local Economy = require(script.Parent.Economy)
local Validate = require(script.Parent.Validate)

local Rewards = {}

-- Lowest amount per counter key.
local COUNTERS = { Gold = -Economy.MAX, Gems = -Economy.MAX, Xp = 1 }
-- Catalogue and lowest amount per map key (Cosmetics values are exactly true).
local MAPS = {
	Materials = { Inventory.Materials, -Economy.MAX },
	Items = { Inventory.Items, -Economy.MAX },
	Dice = { Dice.Types, 1 },
	Cosmetics = { Inventory.Cosmetics },
}

-- A plain table: no metatable (an __iter could show Valid and Apply different
-- contents) and, for write targets, not frozen (pass 2 would throw half-way).
local function plain(t: any): boolean
	return type(t) == "table" and getmetatable(t) == nil and not table.isfrozen(t)
end

local function noMeta(t: any): boolean
	return type(t) == "table" and getmetatable(t) == nil
end

function Rewards.Valid(bundle: any): boolean
	if not noMeta(bundle) then
		return false
	end
	for key, value in bundle do
		local map = MAPS[key]
		if COUNTERS[key] ~= nil then
			if not Validate.IsInt(value, COUNTERS[key], Economy.MAX) then
				return false
			end
		elseif map == nil or not noMeta(value) then
			return false
		else
			for id, n in value do
				local amountOk = if map[2] then Validate.IsInt(n, map[2], Economy.MAX) else n == true
				if map[1][id] == nil or not amountOk then
					return false
				end
			end
		end
	end
	return true
end

-- Applies `bundle` to `profile`. Codes: BadBundle (not Valid), BadAmount (a corrupt
-- or missing stored value), Insufficient, Overflow. Pass 1 computes every write and
-- pass 2 makes them, so a rejection leaves the profile untouched.
function Rewards.Apply(profile: any, bundle: any): (boolean, string?)
	if type(profile) ~= "table" or not Rewards.Valid(bundle) then
		return false, "BadBundle"
	end
	if not plain(profile) then
		return false, "BadAmount"
	end
	local writes = {} -- { table, key, value }; a nil value removes the key
	for key, value in bundle do
		if COUNTERS[key] ~= nil then
			local ok, result = Economy.Sum(profile[key], value)
			if not ok then
				return false, result
			end
			table.insert(writes, { profile, key, result })
			continue
		end
		local owned = profile[key]
		if key == "Cosmetics" then
			owned = if type(owned) == "table" then owned.Owned else nil
		end
		if not plain(owned) then
			return false, "BadAmount"
		end
		for id, n in value do
			local current = owned[id]
			if key == "Cosmetics" then
				table.insert(writes, { owned, id, true })
			elseif key == "Dice" and current == nil then
				table.insert(writes, { owned, id, { Level = 1, Copies = n - 1 } }) -- the first copy unlocks it
			elseif key == "Dice" then
				local ok, result = Economy.Sum(if plain(current) then current.Copies else nil, n)
				if not ok then
					return false, result
				end
				table.insert(writes, { current, "Copies", result })
			else
				local ok, result = Economy.Sum(if current == nil then 0 else current, n)
				if not ok then
					return false, result
				end
				table.insert(writes, { owned, id, if result == 0 then nil else result })
			end
		end
	end
	for _, write in writes do
		write[1][write[2]] = write[3]
	end
	return true, nil
end

-- Display form of a bundle for the Catalog: {{Kind, Id?, Amount}} with counters
-- first (Gold, Gems, Xp), then each map's ids sorted; a cosmetic's Amount is 1.
local COUNTER_ORDER = { "Gold", "Gems", "Xp" }
local MAP_ORDER = { { "Materials", "Material" }, { "Items", "Item" }, { "Dice", "Die" }, { "Cosmetics", "Cosmetic" } }

function Rewards.Lines(bundle): { any }
	local lines = {}
	for _, key in COUNTER_ORDER do
		if bundle[key] ~= nil then
			table.insert(lines, { Kind = key, Amount = bundle[key] })
		end
	end
	for _, pair in MAP_ORDER do
		local map = bundle[pair[1]]
		if map ~= nil then
			local ids = {}
			for id in map do
				table.insert(ids, id)
			end
			table.sort(ids)
			for _, id in ids do
				table.insert(lines, { Kind = pair[2], Id = id, Amount = if map[id] == true then 1 else map[id] })
			end
		end
	end
	return lines
end

return Rewards
