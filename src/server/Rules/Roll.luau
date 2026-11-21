-- The Roll rule (docs/MVP.md "Remotes"): paid random dice from a Config/Roll pool. Pure, no yields. The client sends
-- only (pool, count); odds, prices, pity and the Random stay on the server. Buy validates fully, pays ONE Rewards.Apply
-- bundle (the Gems cost and the dice), and writes the pity counter and Stats.Rolls only after it landed.
local RollConfig = require(script.Parent.Parent.Config.Roll)
local Economy = require(script.Parent.Economy)
local Rewards = require(script.Parent.Rewards)
local Validate = require(script.Parent.Validate)

local Roll = {}

Roll.TOTAL_BP = 10_000 -- one roll draws 1..TOTAL_BP against the pool's Odds
Roll.MAX_COUNT = RollConfig.MaxCount

-- Gems for `count` rolls: the pool's single-roll price x count, less `discountPct` (VIP), rounded up. nil = no such pool price.
function Roll.Price(pool, count: number, discountPct: number?): number?
	if not Validate.IsInt(count, 1, Roll.MAX_COUNT) then
		return nil
	end
	local unit = nil
	for _, p in pool.Prices do
		if p.Count == 1 then
			unit = p.Gems
		end
	end
	if unit == nil then
		return nil
	end
	return math.ceil(unit * count * (100 - (discountPct or 0)) / 100)
end

-- RemoteGuard validator for (pool, count): pool a string of 1..16 bytes, count an integer in 1..MAX_COUNT.
function Roll.Shape(pool: any, count: any): boolean
	return type(pool) == "string" and #pool >= 1 and #pool <= 16 and Validate.IsInt(count, 1, Roll.MAX_COUNT)
end

-- One roll: the guarantee when `pity` (rolls since the last Pity.Rarity die) reached Max - 1, else a weighted rarity;
-- then a uniform die of it. Returns ({Id, Rarity}, new pity).
local function drawOne(pity: number, pool, rng)
	local rarity = nil -- odds summing below TOTAL_BP leave it nil and throw before anything is written
	if pity >= pool.Pity.Max - 1 then
		rarity = pool.Pity.Rarity
	else
		local roll = rng:NextInteger(1, Roll.TOTAL_BP)
		for _, odds in pool.Odds do
			if odds.Bp > 0 then
				roll -= odds.Bp
				if roll <= 0 then
					rarity = odds.Rarity
					break
				end
			end
		end
	end
	local list = pool.ByRarity[rarity]
	local id = list[rng:NextInteger(1, #list)]
	return { Id = id, Rarity = rarity }, if rarity == pool.Pity.Rarity then 0 else pity + 1
end

-- `count` single rolls in a row, the pity counter carried through each. Returns ({{Id, Rarity}}, new pity).
function Roll.Draw(pity: number, pool, count: number, rng): ({ any }, number)
	local results = {}
	for i = 1, count do
		results[i], pity = drawOne(pity, pool, rng)
	end
	return results, pity
end

-- Buys `count` rolls of `poolId` for a Shape-valid request. `allowed` must be exactly true (the player's cached
-- paid-random-item policy). Codes, in order: UnknownPool, UnknownPrice, Restricted, Insufficient, then a Rewards.Apply
-- code (Overflow). Returns (true, nil, {Pool, Results = {{Id, Rarity, New}}, Pity}); New = that die was not owned before
-- this roll (so only its first copy in a ROLL 10).
function Roll.Buy(
	profile: any,
	poolId: string,
	count: number,
	allowed: any,
	rng,
	discountPct: number?
): (boolean, string?, any)
	local pool = RollConfig.ById[poolId]
	if pool == nil then
		return false, "UnknownPool", nil
	end
	local price = Roll.Price(pool, count, discountPct)
	if price == nil then
		return false, "UnknownPrice", nil
	elseif allowed ~= true then
		return false, "Restricted", nil
	elseif type(profile.Gems) ~= "number" or profile.Gems < price then
		return false, "Insufficient", nil
	end
	local results, pity = Roll.Draw(profile.RollPity[poolId] or 0, pool, count, rng)
	local dice, rows = {}, {}
	for i, r in results do
		rows[i] = { Id = r.Id, Rarity = r.Rarity, New = profile.Dice[r.Id] == nil and dice[r.Id] == nil }
		dice[r.Id] = (dice[r.Id] or 0) + 1
	end
	local ok, code = Rewards.Apply(profile, { Gems = -price, Dice = dice })
	if not ok then
		return false, code, nil
	end
	profile.RollPity[poolId] = pity
	profile.Stats.Rolls = math.min(Economy.MAX, profile.Stats.Rolls + count)
	return true, nil, { Pool = poolId, Results = rows, Pity = pity }
end

return Roll
