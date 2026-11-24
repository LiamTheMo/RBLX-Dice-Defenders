-- DICE tab: owned dice from the Meta payload, then unowned playable dice ("Not owned"), then the
-- unreleased catalogue (Display.Locked). Pure data -> models; no UI, no authority.

local Sprites = require(script.Parent.Parent.Parent.Sprites)
local BagLogic = require(script.Parent.Parent.BagLogic)
local Display = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Display"))

local Dice = {}

Dice.Id = "DICE"
Dice.Label = "DICE"
Dice.Icon = "IconDice"
Dice.Fallback = Sprites.Icon.Roll -- tinted glyph for dice without art
Dice.Grid = "Dice"
Dice.Placeholder = "Search"
Dice.SortOptions = {
	{ Id = "Rarity", Label = "Rarity" },
	{ Id = "Level", Label = "Level" },
	{ Id = "Name", Label = "Name" },
	{ Id = "Equipped", Label = "Equipped" },
}
Dice.DefaultSort = "Rarity"
Dice.EmptyText = "No dice found"
Dice.DetailW = 368 -- mockup detail panel width
Dice.HasTopBar = true -- UNEQUIP ALL row above the detail panel (Bag builds it)

-- Die art asset id, or nil (the grid then tints its fallback glyph).
local function art(id: string): string?
	local name = Sprites.DieArt[id]
	return name and Sprites.Dice[name] or nil
end

local function inDeck(meta, id: string): boolean
	return meta ~= nil and meta.Deck ~= nil and table.find(meta.Deck, id) ~= nil
end

-- Unowned card: the locked look, no EQUIP. `footer` doubles as the button hint; `note` is the detail text;
-- `s` is the die's Catalog entry (nil for the unreleased catalogue).
local function lockedItem(id: string, name: string, rarity: string, footer: string, note: string, s)
	return {
		Id = id,
		Name = name,
		Rarity = rarity,
		Damage = s and s.Damage,
		AttackSpeed = s and s.AttackSpeed,
		ExtraStats = s and s.Stats,
		Ability = s and s.Description,
		Level = 0,
		Locked = true,
		Equipped = false,
		Icon = art(id),
		CornerBadge = "Lock",
		SubTag = string.upper(rarity),
		Footer = footer,
		Note = note,
	}
end

-- The account's total crit damage, shown beside the inventory's sort box: the starter 100% (a crit hits for 2x) plus the
-- crit every die level-up has earned (the server sums the same curve). Nil until the catalogue's curve has loaded.
local BASE_CRIT = 100
local BASE_CRIT_CHANCE = 5
function Dice.Count(meta, catalog): string?
	local DL = catalog and catalog.DieLevel
	if type(DL) ~= "table" or type(DL.Crit) ~= "table" or meta == nil then
		return nil
	end
	local offsets = if type(DL.Offset) == "table" then DL.Offset else {}
	local total = BASE_CRIT
	for _, die in meta.Dice or {} do
		local info = Display.Dice[die.Id]
		local off = if info and type(offsets[info.Rarity]) == "number" then offsets[info.Rarity] else 0
		for l = 1, if info and type(die.Level) == "number" then math.min(die.Level, 500) - 1 else 0 do
			local v = DL.Crit[l + off]
			total += if type(v) == "number" then v else 0
		end
	end
	-- two rows of "label<TAB>number" (the toolbar left-aligns the labels, right-aligns the numbers): the total in deep
	-- tangerine, the starter 5% crit chance (display only: no crit-chance upgrade exists yet) under it
	return ('Crit Damage\t<font color="#FF7A00">%g%%</font>\nCrit Chance\t<font color="#FFC21A">%g%%</font>'):format(
		total,
		BASE_CRIT_CHANCE
	)
end
Dice.CountGain = true -- the toolbar keeps room beside the total for the green "+N%" an UPGRADE hover previews

function Dice.GetItems(meta, catalog)
	local stats = {} -- Catalog entries (Damage, Rate) by die id
	for _, s in catalog and catalog.Dice or {} do
		stats[s.Id] = s
	end
	-- Level cap and per-level copy costs come from the Catalog (untrusted: numbers only). nil = not loaded.
	local DL = catalog and catalog.DieLevel
	local function whole(n) -- finite whole number >= 1 (NaN/inf/fractions/negatives fail)
		return type(n) == "number" and n >= 1 and n < math.huge and n % 1 == 0
	end
	-- one cost per level-up: also bounds the loop below (a huge finite Max is refused before it runs)
	local ok = type(DL) == "table" and type(DL.Copies) == "table" and whole(DL.Max) and #DL.Copies == DL.Max - 1
	for i = 1, ok and DL.Max - 1 or 0 do
		ok = ok and whole(DL.Copies[i])
	end
	local cap = if ok then DL.Max else nil
	local costs = if ok then DL.Copies else {}
	-- Gold and crit curves are indexed by class = level + the rarity's offset (Random Dice: rarer dice start further up)
	local goldCurve = if ok and type(DL.Gold) == "table" then DL.Gold else {}
	local critCurve = if ok and type(DL.Crit) == "table" then DL.Crit else {}
	local offsets = if ok and type(DL.Offset) == "table" then DL.Offset else {}
	local balance = if meta and type(meta.Gold) == "number" then meta.Gold else 0
	local function curve(list, rarity: string, level: number): number?
		local off = if type(offsets[rarity]) == "number" then offsets[rarity] else 0
		local v = list[level + off]
		return if type(v) == "number" then v else nil
	end
	local items = {}
	local shards = 0
	for _, stack in meta and meta.Materials or {} do
		if stack.Id == "DieShard" then
			shards = stack.Quantity
			break
		end
	end
	for _, die in meta and meta.Dice or {} do
		local info = Display.Dice[die.Id]
		if info then
			local equipped = inDeck(meta, die.Id)
			local s = stats[die.Id]
			local cost = costs[die.Level]
			local spare = if type(die.Copies) == "number" then die.Copies else 0
			table.insert(items, {
				Id = die.Id,
				Name = info.Name,
				Rarity = info.Rarity,
				Damage = s and s.Damage,
				AttackSpeed = s and s.AttackSpeed,
				ExtraStats = s and s.Stats,
				Targeting = s and s.Targeting,
				Ability = s and s.Description,
				Level = die.Level,
				Equipped = equipped,
				Icon = art(die.Id),
				Tint = if art(die.Id) == nil then info.Color else nil, -- elemental art keeps its own colours
				TopTag = if equipped then "EQUIPPED" else nil,
				TopTagStyle = "Equipped",
				SubTag = string.upper(info.Rarity),
				Footer = "Lv. " .. tostring(die.Level),
				Count = "x" .. BagLogic.formatCount(spare), -- spare copies (the first copy unlocks the die)
				Copies = spare,
				LevelMax = cap,
				LevelCost = if type(cost) == "number" then cost else nil,
				LevelGold = curve(goldCurve, info.Rarity, die.Level),
				CritGain = curve(critCurve, info.Rarity, die.Level),
				Gold = balance,
				Shards = shards,
			})
		end
	end
	return items -- unowned and unreleased dice are not listed at all
end

-- Combat stats: Damage and Attack Speed (seconds per attack at 1 pip) always, then any number of ability stats the Catalog
-- lists for the die (Config/Dice `stats`: { { Label, Value, Suffix?, Icon?, Color? } }, in order: crit chance, poison damage,
-- chain damage, phase duration, MP bonus ...). A dash when the Catalog lacks a number. The panel scrolls past ~4 rows.
local UPGRADE_YELLOW = Color3.fromRGB(255, 190, 20) -- the UPGRADE button's amber (Shared.PillYellow)
local DASH = "\u{2013}"
local DEFAULT_DESC = "placeholder desc" -- shown for dice with no ability text yet
local DEFAULT_TARGETING = "Front" -- every die targets the front enemy until its Config entry says otherwise
local function num(v, suffix: string?): string
	return if type(v) == "number" then string.format("%g", v) .. (suffix or "") else DASH
end
local function stats(item)
	local list = {
		{ Icon = "IconSword", Label = "Damage", Value = num(item.Damage) },
		{ Icon = "IconHourglass", Label = "SPA", Value = num(item.AttackSpeed, "s") },
		{
			Icon = "IconDice",
			Label = "Target",
			Value = if type(item.Targeting) == "string" then item.Targeting else DEFAULT_TARGETING,
		},
	}
	for _, st in if type(item.ExtraStats) == "table" then item.ExtraStats else {} do
		if type(st) == "table" and type(st.Label) == "string" and st.Value ~= nil then
			table.insert(list, {
				Icon = if type(st.Icon) == "string" then st.Icon else "IconDice",
				Label = st.Label,
				Value = if type(st.Value) == "number" then num(st.Value, st.Suffix) else tostring(st.Value),
				Color = if typeof(st.Color) == "Color3" then st.Color else nil,
			})
		end
	end
	return list
end

function Dice.Detail(item)
	local locked = item.Locked == true
	local equipped = item.Equipped == true
	local hint = if locked then item.Footer else nil
	local max, cost, goldCost = item.LevelMax, item.LevelCost, item.LevelGold
	local loaded = max ~= nil and ((cost ~= nil and goldCost ~= nil) or item.Level >= max)
	local atMax = loaded and item.Level >= max
	local haveGold = (item.Gold or 0) >= (goldCost or 0)
	local upOk = not locked and loaded and not atMax and item.Copies >= cost and haveGold
	local upHint = if locked
		then item.Footer
		elseif not loaded then "Still loading"
		elseif atMax then "Max level"
		elseif upOk then "Upgrade"
		elseif item.Copies < cost then ("Need %d copies"):format(cost)
		else ("Need %s gold"):format(BagLogic.formatCount(goldCost))
	local copies = if loaded and not locked
		then (if atMax then ("Copies %d"):format(item.Copies) else ("Copies %d / %d"):format(item.Copies, cost))
		else nil
	return {
		Name = item.Name,
		Rarity = item.Rarity,
		StatusTag = if equipped then "EQUIPPED" else nil,
		Icon = item.Icon,
		Tint = item.Tint,
		BtnW = { 125, 125 },
		TopY = 14,
		ArtY = 20,
		ArtH = 94,
		NameY = 108,
		Ys = { Sub = 150, Desc = 180, Extra = 240 }, -- the panel is shorter now (it sits under the action row)
		Subline = if copies
			then {
				Kind = "Level",
				Value = item.Level,
				Max = max,
				Copies = copies,
				FillColor = UPGRADE_YELLOW, -- the same amber as the UPGRADE button
				Progress = if atMax then 1 else math.min(1, item.Copies / cost), -- the bar: spare copies toward the next level
			}
			else nil,
		Description = if type(item.Ability) == "string" and item.Ability ~= ""
			then item.Ability
			elseif locked then item.Note
			else DEFAULT_DESC,
		Stats = stats(item),
		-- the crit damage the next level adds: the toolbar's Crit Damage total shows it in green while UPGRADE is hovered or held
		Preview = if loaded
				and not locked
				and not atMax
				and type(item.CritGain) == "number"
				and item.CritGain > 0
			then "+" .. string.format("%g", item.CritGain) .. "%"
			else nil,
		ActionDrop = -3, -- the buttons sit a little lower than on the other tabs
		-- the gold price of the next level, shown on a tag above UPGRADE
		UpgradeCost = if loaded and not locked and not atMax then { Amount = goldCost, Afford = haveGold } else nil,
		Buttons = {
			{
				Id = "Upgrade",
				Label = "UPGRADE",
				Style = "Yellow",
				Enabled = upOk,
				Hint = upHint,
			},
			{
				Id = if equipped then "Unequip" else "Equip",
				Label = if equipped then "UNEQUIP" else "EQUIP",
				Style = if equipped then "Red" else "Green",
				Enabled = not locked,
				Hint = hint,
			},
		},
	}
end

-- The action row above the detail panel: UNEQUIP ALL (red), enabled while the loadout holds a die.
function Dice.TopBar(meta)
	local deck = meta and meta.Deck or {}
	return {
		UnequipAll = {
			Label = "UNEQUIP ALL",
			Enabled = #deck > 0,
			Hint = if meta then "No dice equipped" else "Still loading",
		},
	}
end

return Dice
