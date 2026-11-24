-- Match HUD pure logic: hearts, text, slot / summon states, visibility. No Roblox APIs (unit-tested headless).
-- Display hints only: the server decides every Summon / PowerUp; affordability here just styles the buttons.

local HudLogic = {}

HudLogic.MAX_HEARTS = 10 -- drawing cap; the server's MaxLives is far below it
HudLogic.MAX_SHOWN = 999_999_999 -- text cap so a huge or infinite MP never overflows the number formatting
HudLogic.SUMMON_TEXT = "SUMMON"

local function whole(n: any): number -- finite integer >= 0, else 0
	if type(n) ~= "number" or n ~= n then
		return 0
	end
	return math.floor(math.clamp(n, 0, HudLogic.MAX_SHOWN))
end

local function thousands(n: number): string
	local s = tostring(n)
	while true do
		local out, count = string.gsub(s, "^(%d+)(%d%d%d)", "%1,%2")
		s = out
		if count == 0 then
			return s
		end
	end
end

-- Hearts to draw: full + empty = max (MaxLives, or Lives when the snapshot has none), capped at MAX_HEARTS.
function HudLogic.hearts(lives: number?, maxLives: number?): (number, number)
	local l = whole(lives)
	local m = math.min(HudLogic.MAX_HEARTS, if maxLives == nil then l else math.max(whole(maxLives), l))
	local full = math.min(l, m)
	return full, m - full
end

function HudLogic.waveText(wave: number?): string
	return "WAVE " .. whole(wave)
end

function HudLogic.mpText(mp: number?): string
	return thousands(whole(mp)) .. " MP"
end

function HudLogic.levelText(tier: number?): string
	return "Lv " .. whole(tier)
end

function HudLogic.costText(cost: number?): string
	return if cost == nil then "MAX" else thousands(whole(cost)) .. " MP"
end

-- "maxed" (Cost nil), "insufficient" (MP below Cost or MP unknown), else "idle".
function HudLogic.slotState(cost: number?, mp: number?): string
	if cost == nil then
		return "maxed"
	end
	if type(cost) ~= "number" or cost ~= cost or (mp or 0) < cost or mp ~= mp then
		return "insufficient"
	end
	return "idle"
end

-- Convenience over a snapshot Tiers row.
function HudLogic.slotInfo(row, mp: number?)
	return {
		State = HudLogic.slotState(row.Cost, mp),
		LevelText = HudLogic.levelText(row.Tier),
		CostText = HudLogic.costText(row.Cost),
	}
end

-- "idle" when MP covers SummonCost, else "insufficient" (also when SummonCost is unknown).
function HudLogic.summonState(summonCost: number?, mp: number?): string
	if type(summonCost) ~= "number" or summonCost ~= summonCost or (mp or 0) < summonCost or mp ~= mp then
		return "insufficient"
	end
	return "idle"
end

function HudLogic.summonCostText(summonCost: number?): string
	return thousands(whole(summonCost)) .. " MP"
end

-- Which parts show per snapshot phase (mirrors the old Hud.render): everything is Playing-only; the hint also
-- needs wave <= 2, the slot row needs at least one Tiers row.
function HudLogic.visibility(phase: string?, wave: number?, tierRows: number?)
	local playing = phase == "Playing"
	return {
		Bar = playing,
		Summon = playing,
		Slots = playing and whole(tierRows) > 0,
		Hint = playing and whole(wave) <= 2,
	}
end

return HudLogic
