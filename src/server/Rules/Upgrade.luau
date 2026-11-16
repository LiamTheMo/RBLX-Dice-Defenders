-- Die level-up (docs/MVP.md "Remotes", UpgradeDie): spend spare copies of a die for +1 level.
-- Pure, no yields. Costs are Progression.DieLevel.Copies and never leave the server.
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
	entry.Copies, entry.Level = copies, entry.Level + 1
	return true, nil
end

return Upgrade
