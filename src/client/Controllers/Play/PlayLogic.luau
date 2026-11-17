--!strict
-- Play tab logic: pure, no Instances. The view draws what these return.
-- Milestone states and the repeat payout come from the server's Catalog and Meta; the client only shows them (the server
-- re-checks every claim).

local PlayLogic = {}

-- The one real, playable world is the server's trial.
PlayLogic.WORLD = { Id = "DiceKingdom", Name = "DICE KINGDOM", Art = "WorldDice" }

-- The other worlds: display only, always locked.
PlayLogic.LOCKED_WORLDS = table.freeze({
	table.freeze({ Id = "FrostPeaks", Name = "FROST PEAKS", Art = "WorldFrost" }),
	table.freeze({ Id = "MagmaCitadel", Name = "MAGMA CITADEL", Art = "WorldMagma" }),
	table.freeze({ Id = "ShadowRealm", Name = "SHADOW REALM", Art = "WorldShadow" }),
})

-- Repeat-reward tiles. Only materials drop from a run (Verdant Fragments); the rest are placeholders marked Soon.
PlayLogic.TILES = table.freeze({
	table.freeze({ Label = "MATERIALS", Icon = "IconCrystals" }),
	table.freeze({ Label = "ITEMS", Icon = "Potion", Soon = true }),
	table.freeze({ Label = "COSMETICS", Icon = "Crown", Soon = true }),
	table.freeze({ Label = "RARE DICE", Icon = "IconGalaxyDie", Soon = true }),
})

-- Card denominator only (every world card reads "/ 100"); not the server's playable wave count.
PlayLogic.DISPLAY_WAVES = 100

-- Reward kinds (Rewards.Lines): counters read as a word, the rest by their Catalog name.
local COUNTER = { Gold = "GOLD", Gems = "GEMS", Xp = "XP" }
local CATALOG_LIST = { Material = "Materials", Item = "Items", Die = "Dice", Cosmetic = "Cosmetics" }
-- Row icon: the most special reward picks it (view sprite keys; Coin / Gem are the HUD's currency sprites).
local ICON = {
	Die = "IconGalaxyDie",
	Cosmetic = "Crown",
	Item = "Potion",
	Material = "IconCrystals",
	Gems = "Gem",
	Gold = "Coin",
	Xp = "BadgeXp",
}
local ICON_RANK = { "Die", "Cosmetic", "Item", "Material", "Gems", "Gold", "Xp" }

-- BEST pill text. `shown` lets the view pass a rich-text-wrapped number in place of `best`.
function PlayLogic.bestWaveText(best: string, form: "full" | "short" | "min", shown: string?): string
	local n = shown or best
	if form == "full" then
		return `BEST WAVE {n} / {PlayLogic.DISPLAY_WAVES}`
	elseif form == "short" then
		return `BEST {n}/{PlayLogic.DISPLAY_WAVES}`
	end
	return `{n}/{PlayLogic.DISPLAY_WAVES}`
end

function PlayLogic.bestText(best: number?): string
	if type(best) ~= "number" or best ~= best or best < 1 then
		return "--"
	end
	return tostring(math.floor(best))
end

function PlayLogic.startState(snap: any, busy: boolean): "Ready" | "Busy" | "Disabled"
	if busy then
		return "Busy"
	end
	if snap and (snap.Phase == "Lobby" or snap.Phase == "Ended") then
		return "Ready"
	end
	return "Disabled"
end

function PlayLogic.worlds(snap: any)
	local W = PlayLogic.WORLD
	local out = {
		{
			Id = W.Id,
			Name = W.Name,
			Art = W.Art,
			Best = PlayLogic.bestText(snap and snap.BestWave),
			Locked = false,
		},
	}
	for _, w in PlayLogic.LOCKED_WORLDS do
		table.insert(out, { Id = w.Id, Name = w.Name, Art = w.Art, Best = "--", Locked = true })
	end
	return out
end

-- "+50 GEMS", "+1 XP TOME", "+2 XP TOMES", "+1 FROST DIE". form "Icon" drops " DIE" (the row's die icon says it, and the
-- desktop text column is narrow); form "Short" keeps only the name's last word ("+5 FRAGMENTS" for Verdant Fragments).
function PlayLogic.rewardText(line: any, catalog: any, form: ("Icon" | "Short")?): string
	local label = COUNTER[line.Kind]
	if label and line.Amount == 1 then
		label = (string.gsub(label, "S$", "")) -- +1 GEM
	elseif not label then
		local name = line.Id
		local list = catalog and catalog[CATALOG_LIST[line.Kind]]
		for _, e in (if type(list) == "table" then list else {}) :: { any } do
			if e.Id == line.Id then
				name = e.Name
			end
		end
		label = string.upper(tostring(name))
		if form == "Short" then
			label = string.match(label, "(%S+)$") or label
			if line.Amount == 1 then
				label = string.gsub(label, "([^S])S$", "%1") -- FRAGMENTS -> FRAGMENT, GLASS stays
			end
		elseif line.Kind == "Die" then
			label ..= if form == "Icon" then "" else " DIE"
		elseif line.Amount ~= 1 and not string.match(label, "S$") then
			label ..= "S"
		end
	end
	return `+{tostring(line.Amount)} {label}`
end

-- One row per Catalog milestone, in its order. State (the server decides via Meta): "Claimed", "Claimable", "Locked"
-- (a wave the Trial has, not reached yet) or "Soon" (a wave the game does not have yet). Busy = a claim is in flight.
-- Lines sit beside the row's reward icon (desktop; a claimable row's CLAIM takes the icon's place, so it gets Full); Full is
-- the same rewards for phone rows, which draw no icon. Malformed Catalog rows and rewards are skipped.
function PlayLogic.milestones(catalog: any, meta: any, pending: { [string]: boolean }?)
	local status = {}
	for _, m in (if meta and type(meta.Milestones) == "table" then meta.Milestones else {}) :: { any } do
		if type(m) == "table" and m.Id ~= nil then
			status[m.Id] = m
		end
	end
	local out = {}
	for _, m in (if catalog and type(catalog.Milestones) == "table" then catalog.Milestones else {}) :: { any } do
		if type(m) ~= "table" or m.Id == nil or type(m.Wave) ~= "number" then
			continue
		end
		local s = status[m.Id]
		local state = if s and s.Claimed == true
			then "Claimed"
			elseif s and s.Claimable == true then "Claimable"
			elseif m.Reachable then "Locked"
			else "Soon"
		local lines, full, icon, rank = {}, {}, nil, math.huge
		for _, r in (if type(m.Rewards) == "table" then m.Rewards else {}) :: { any } do
			if type(r) ~= "table" then
				continue
			end
			table.insert(lines, PlayLogic.rewardText(r, catalog, "Icon"))
			table.insert(full, PlayLogic.rewardText(r, catalog))
			local at = table.find(ICON_RANK, r.Kind)
			if at and at < rank then
				icon, rank = ICON[r.Kind], at
			end
		end
		table.insert(out, {
			Id = m.Id,
			Wave = m.Wave,
			Icon = icon or "IconCrystals",
			Lines = if state == "Claimable" then full else lines,
			Full = full,
			State = state,
			Busy = pending ~= nil and pending[m.Id] == true,
		})
	end
	return out
end

-- The milestone id a CLAIM press should send, or nil (not claimable, or a claim for it is already in flight).
function PlayLogic.claimTarget(row: any, pending: { [string]: boolean }): string?
	if row and row.State == "Claimable" and not pending[row.Id] then
		return row.Id
	end
	return nil
end

-- The real per-run payout (Catalog.Repeat) as payout-box lines of tokens; a token ending in ":" is a heading.
--   { {"PER WAVE:"}, {"+5 GOLD", "+1 GEM", "+10 XP"}, {"+1 FRAGMENT"}, {"BOSS WAVE:", "+3 GEMS"} }
function PlayLogic.repeatLines(catalog: any): { { string } }
	local rep = catalog and catalog.Repeat
	if type(rep) ~= "table" then
		return {}
	end
	local lines: { { string } } = { { "PER WAVE:" } }
	local function add(rewards: any, head: string?)
		local counters: { string } = if head then { head } else {}
		local named: { { string } } = {}
		for _, r in (if type(rewards) == "table" then rewards else {}) :: { any } do
			if type(r) ~= "table" then
				continue
			end
			local text = PlayLogic.rewardText(r, catalog, "Short")
			if COUNTER[r.Kind] then
				table.insert(counters, text)
			else
				table.insert(named, { text })
			end
		end
		if #counters > (if head then 1 else 0) then -- a heading alone is no line
			table.insert(lines, counters)
		end
		table.move(named, 1, #named, #lines + 1, lines)
	end
	add(rep.PerWave)
	add(rep.BossWave, "BOSS WAVE:")
	return lines
end

function PlayLogic.worldClear(snap: any): boolean
	return snap ~= nil and snap.TrialCleared == true
end

return PlayLogic
