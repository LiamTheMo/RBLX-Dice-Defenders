-- Die level-up (docs/_archive/MVP.md "Remotes", UpgradeDie): spend spare copies AND gold of a die for +1 level.
-- Pure, no yields. Costs are Progression.DieLevel (server config; clients only get a read-only Catalog copy for display).
-- Codes also include NoGold (Gold below the step's cost).
local Dice = require(script.Parent.Parent.Config.Dice)
local Progression = require(script.Parent.Parent.Config.Progression)
local Economy = require(script.Parent.Economy)
local Validate = require(script.Parent.Validate)

local Upgrade = {}

-- True for a string of 1..8 bytes (the same rule as Deck.Shape's ids). Untrusted input.
function Upgrade.Shape(id: any): boolean
	return type(id) == "string" and #id >= 1 and #id <= 8
end

-- Levels `id` up once. Returns (true) or (false, code): UnknownDie, NotOwned, BadAmount (a corrupt
-- entry), MaxLevel, Insufficient. A rejection changes nothing; success is one write.
function Upgrade.Die(profile: any, id: any): (boolean, string?)
	if type(id) ~= "string" or Dice.Types[id] == nil then
		return false, "UnknownDie"
	end
	local owned = profile.Dice
	local entry = if type(owned) == "table" then owned[id] else nil
	if entry == nil then
		return false, "NotOwned"
	end
	local max = Progression.DieLevel.Max
	if
		type(entry) ~= "table"
		or getmetatable(entry) ~= nil
		or table.isfrozen(entry)
		or not Validate.IsInt(entry.Level, 1, max)
		or not Validate.IsInt(entry.Copies, 0, Economy.MAX)
	then
		return false, "BadAmount"
	end
	if entry.Level >= max then
		return false, "MaxLevel"
	end
	local ok, copies = Economy.Sum(entry.Copies, -Progression.DieLevel.Copies[entry.Level])
	if not ok then
		return false, copies
	end
	local goldCost = Progression.GoldCost(Dice.Types[id].rarity, entry.Level)
	local okGold, gold = Economy.Sum(profile.Gold, -(goldCost or 0))
	if not okGold then
		return false, if gold == "Insufficient" then "NoGold" else gold
	end
	entry.Copies, entry.Level, profile.Gold = copies, entry.Level + 1, gold
	return true, nil
end

-- Crit damage percent the whole account has earned from die levels (summed over every owned die).
function Upgrade.CritBonus(profile: any): number
	local total = 0
	local owned = profile.Dice
	if type(owned) ~= "table" then
		return 0
	end
	for id, entry in owned do
		local cfg = Dice.Types[id]
		if cfg and type(entry) == "table" and Validate.IsInt(entry.Level, 1, Progression.DieLevel.Max) then
			total += Progression.CritOf(cfg.rarity, entry.Level)
		end
	end
	return total
end

return Upgrade
