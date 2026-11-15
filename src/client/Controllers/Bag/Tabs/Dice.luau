-- DICE tab: owned dice from the Meta payload, then unowned playable dice ("Not owned"), then the
-- unreleased catalogue (Display.Locked). Pure data -> models; no UI, no authority.

local Sprites = require(script.Parent.Parent.Parent.Sprites)
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

-- Die art asset id, or nil (the grid then tints its fallback glyph).
local function art(id: string): string?
	local name = Sprites.DieArt[id]
	return name and Sprites.Dice[name] or nil
end

local function inDeck(meta, id: string): boolean
	return meta ~= nil and meta.Deck ~= nil and table.find(meta.Deck, id) ~= nil
end

-- Unowned card: the locked look, no EQUIP. `footer` doubles as the button hint; `note` is the detail text.
local function lockedItem(id: string, name: string, rarity: string, footer: string, note: string)
	return {
		Id = id,
		Name = name,
		Rarity = rarity,
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

function Dice.GetItems(meta)
	local items = {}
	local owned = {}
	for _, die in meta and meta.Dice or {} do
		owned[die.Id] = true
		local info = Display.Dice[die.Id]
		if info then
			local equipped = inDeck(meta, die.Id)
			table.insert(items, {
				Id = die.Id,
				Name = info.Name,
				Rarity = info.Rarity,
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
		table.insert(items, lockedItem(id, info.Name, info.Rarity, "Not owned", "Not owned"))
	end
	for _, die in Display.Locked do
		table.insert(items, lockedItem(die.Id, die.Name, die.Rarity, "Locked", "Not available yet"))
	end
	return items
end

-- Per-die combat numbers live only in the server config: the rows render a dash until the client gets them.
local STATS = {
	{ Icon = "IconSword", Label = "Damage", Value = "\u{2013}" },
	{ Icon = "IconTarget", Label = "Range", Value = "\u{2013}" },
	{ Icon = "IconHourglass", Label = "Attack Speed", Value = "\u{2013}" },
	{ Icon = "IconFlame", Label = "Burn Damage", Value = "\u{2013}" },
}

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
		Description = if locked then item.Note else "",
		Stats = STATS,
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
				Hint = hint or "Coming soon",
			},
			{
				Id = "Sell",
				Label = "SELL",
				Style = "Red",
				Icon = "Coins",
				Enabled = false,
				Hint = hint or "Coming soon",
			},
		},
	}
end

function Dice.Footer(meta)
	local deck = meta and meta.Deck or {}
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
		Button = { Label = "UNEQUIP ALL", Enabled = false, Hint = "Coming soon" },
	}
end

return Dice
