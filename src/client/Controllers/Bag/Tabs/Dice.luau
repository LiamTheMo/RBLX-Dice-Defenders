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
Dice.Placeholder = "Search dice..."
Dice.SortOptions = {
	{ Id = "Rarity", Label = "Rarity" },
	{ Id = "Level", Label = "Level" },
	{ Id = "Name", Label = "Name" },
	{ Id = "Equipped", Label = "Equipped" },
}
Dice.DefaultSort = "Rarity"
Dice.EmptyText = "No dice found"

local ABILITY = "Ability: coming soon" -- non-Common dice are stat-only until their abilities are built

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
		Rate = s and s.Rate,
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
	local items = {}
	local owned = {}
	for _, die in meta and meta.Dice or {} do
		owned[die.Id] = true
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
				Rate = s and s.Rate,
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
			})
		end
	end
	local unowned = {}
	for id in Display.Dice do
		if not owned[id] and (not stats[id] or not stats[id].Retired) then
			table.insert(unowned, id)
		end
	end
	table.sort(unowned)
	for _, id in unowned do
		local info = Display.Dice[id]
		local unavailable = info.Rarity == "Mythic"
		local note = if unavailable then "Not available yet" elseif info.Rarity == "Common" then "Not owned" else "Not owned. " .. ABILITY
		table.insert(items, lockedItem(id, info.Name, info.Rarity, if unavailable then "Locked" else "Not owned", note, stats[id]))
	end
	for _, die in Display.Locked do
		table.insert(items, lockedItem(die.Id, die.Name, die.Rarity, "Locked", "Not available yet"))
	end
	return items
end

-- Damage and Attack Speed (attacks/s) come from the Catalog; the other rows render a dash until the client gets them.
local DASH = "\u{2013}"
local function num(v): string
	return if type(v) == "number" then string.format("%g", v) else DASH
end
local function stats(item)
	return {
		{ Icon = "IconSword", Label = "Damage", Value = num(item.Damage) },
		{ Icon = "IconHourglass", Label = "Attack Speed", Value = num(item.Rate) },
		{ Icon = "IconFlame", Label = "Burn Damage", Value = DASH },
	}
end

-- Buttons: one size; EQUIP for an owned die not in the deck, UPGRADE when the spare copies cover the next level.
function Dice.Detail(item)
	local locked = item.Locked == true
	local equipped = item.Equipped == true
	local hint = if locked then item.Footer else nil
	local equipOk = not locked and not equipped
	local max, cost = item.LevelMax, item.LevelCost
	local loaded = max ~= nil and (cost ~= nil or item.Level >= max)
	local atMax = loaded and item.Level >= max
	local upOk = not locked and loaded and not atMax and item.Copies >= cost
	local upHint = if locked
		then item.Footer
		elseif not loaded then "Still loading"
		elseif atMax then "Max level"
		elseif upOk then "Upgrade"
		else ("Need %d copies"):format(cost)
	local copies = if loaded and not locked
		then (if atMax then ("Copies %d"):format(item.Copies) else ("Copies %d / %d"):format(item.Copies, cost))
		else nil
	return {
		Name = item.Name,
		Rarity = item.Rarity,
		StatusTag = if equipped then "EQUIPPED" else nil,
		Icon = item.Icon,
		Tint = item.Tint,
		Subline = if copies then { Kind = "Level", Value = item.Level, Max = max, Copies = copies } else nil,
		Description = if item.Ability then item.Ability elseif locked then item.Note elseif item.Rarity ~= "Common" then ABILITY else "",
		Stats = stats(item),
		Buttons = {
			{
				Id = "Equip",
				Label = "EQUIP",
				Style = "Green",
				Enabled = equipOk,
				Hint = hint or "Already equipped",
			},
			{
				Id = "Upgrade",
				Label = "UPGRADE",
				Style = "Gold",
				Enabled = upOk,
				Hint = upHint,
			},
			{
				Id = "Sell",
				Label = "SELL",
				Style = "Red",
				Icon = "Coins",
				Enabled = false,
				Hint = hint or "Copies level this die up",
			},
		},
	}
end

-- UNEQUIP ALL resets the loadout to the Catalog's starter deck (EquipDeck needs 5 dice); off when it already is.
function Dice.Footer(meta, catalog)
	local deck = meta and meta.Deck or {}
	local starter = catalog and catalog.StarterDeck
	local same = BagLogic.sameDeck(deck, starter)
	local icons, tints = {}, {}
	for i, id in deck do
		icons[i] = art(id) or Sprites.Icon.Roll
		local info = Display.Dice[id]
		tints[i] = if art(id) == nil and info then info.Color else Color3.new(1, 1, 1)
	end
	return {
		Label = ("EQUIPPED LOADOUT (%d/5)"):format(#deck),
		Slots = icons,
		Tints = tints,
		Button = {
			Label = "UNEQUIP ALL",
			Enabled = starter ~= nil and not same,
			Hint = if same then "Already the starter deck" else "Still loading",
			Deck = starter,
		},
	}
end

return Dice
