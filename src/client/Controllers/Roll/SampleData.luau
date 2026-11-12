--!strict
-- CLIENT-ONLY SAMPLE DATA: display only. The server has no roll feature; nothing here grants, spends or decides anything.
-- Studio gets the full reference sample; live players get `live` (no balance, no pity progress, no rotation timer).
local QuestLogic = require(script.Parent.Parent.QuestLog.QuestLogic)

-- PLACEHOLDER until the server owns them: the user-set per-step chances (percent) of the roll chain, in chain order
-- Secret -> Mythic -> Legendary -> Epic -> Rare -> Common (Common is the remainder: no key). One table for Studio and live:
-- odds are disclosed before purchase.
local Odds = {
	Secret = 0.01,
	Mythic = 0.1,
	Legendary = 1,
	Epic = 10,
	Rare = 25,
}

-- Docs: Legendary pity after 80 Premium chests; Mythic is never pity-guaranteed.
local function pity(count: number)
	return { Count = count, Max = 80, Rarity = "Legendary" }
end

-- PLACEHOLDER prices in gems (undocumented), keyed by roll count.
local Prices = { [1] = 100, [10] = 900 }

-- Real catalogue ids (Display.Locked: not playable yet).
local Featured = {
	{ Id = "L02", Rarity = "Legendary" },
	{ Id = "M01", Rarity = "Mythic" },
	{ Id = "L03", Rarity = "Legendary" },
}

-- PLACEHOLDER rotation end: next Monday 00:00 UTC (the weekly quest reset). There is no event rotation yet.
local full = {
	Odds = Odds,
	Pity = pity(32),
	Prices = Prices,
	Featured = Featured,
	Gems = 120 :: number?,
	RotationEnd = QuestLogic.weeklyResetAt :: ((number) -> number)?,
}

-- No Gems balance exists anywhere yet, and no rolls exist, so live has no balance and zero pity.
local live = {
	Odds = Odds,
	Pity = pity(0),
	Prices = Prices,
	Featured = Featured,
	Gems = nil :: number?,
	RotationEnd = nil :: ((number) -> number)?,
}

return {
	full = full,
	live = live,
	get = function(isStudio: boolean)
		return if isStudio then full else live
	end,
}
