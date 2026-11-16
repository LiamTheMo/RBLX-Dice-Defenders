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
Dice.MaxLevel = 10 -- ProfileSchema cap

local ABILITY = "Ability: coming soon" -- non-Common dice are stat-only until their abilities are built
local KEEP = "Copies are kept for future level-ups" -- why dice have no LOCK or SELL

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
	local items = {}
	local owned = {}
	for _, die in meta and meta.Dice or {} do
		owned[die.Id] = true
		local info = Display.Dice[die.Id]
		if info then
			local equipped = inDeck(meta, die.Id)
			local s = stats[die.Id]
			table.insert(items, {
				Id = die.Id,
				Name = info.Name,
				Rarity = info.Rarity,
				Damage = s and s.Damage,
				Rate = s and s.Rate,
				Level = die.Level,
				Equipped = equipped,
				Icon = art(die.Id),
				Tint = if art(die.Id) == nil then info.Color else nil, -- elemental art keeps its own colours
				TopTag = if equipped then "EQUIPPED" else nil,
				TopTagStyle = "Equipped",
				SubTag = string.upper(info.Rarity),
				Footer = "Lv. " .. tostring(die.Level),
			})
		end
	end
	local unowned = {}
	for id in Display.Dice do
		if not owned[id] then
			table.insert(unowned, id)
		end
	end
	table.sort(unowned)
	for _, id in unowned do
		local info = Display.Dice[id]
		local note = if info.Rarity == "Common" then "Not owned" else "Not owned. " .. ABILITY
		table.insert(items, lockedItem(id, info.Name, info.Rarity, "Not owned", note, stats[id]))
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
		{ Icon = "IconTarget", Label = "Range", Value = DASH },
		{ Icon = "IconHourglass", Label = "Attack Speed", Value = num(item.Rate) },
		{ Icon = "IconFlame", Label = "Burn Damage", Value = DASH },
	}
end

-- Buttons: one size, EQUIP only valid for an owned die not in the deck.
function Dice.Detail(item)
	local locked = item.Locked == true
	local equipped = item.Equipped == true
	local hint = if locked then item.Footer else nil
	local equipOk = not locked and not equipped
	return {
		Name = item.Name,
		Rarity = item.Rarity,
		StatusTag = if equipped then "EQUIPPED" else nil,
		Icon = item.Icon,
		Tint = item.Tint,
		Subline = if locked then nil else { Kind = "Level", Value = item.Level, Max = Dice.MaxLevel },
		Description = if locked then item.Note elseif item.Rarity ~= "Common" then ABILITY else "",
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
				Id = "Lock",
				Label = "LOCK",
				Style = "Gold",
				Icon = "Lock",
				Enabled = false,
				Hint = hint or KEEP,
			},
			{
				Id = "Sell",
				Label = "SELL",
				Style = "Red",
				Icon = "Coins",
				Enabled = false,
				Hint = hint or KEEP,
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
