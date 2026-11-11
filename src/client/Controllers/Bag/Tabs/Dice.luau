-- DICE tab: owned dice from the Meta payload + the unowned catalogue (locked). Pure data -> models; no UI, no authority.

local Sprites = require(script.Parent.Parent.Parent.Sprites)
local Display = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Display"))

local Dice = {}

Dice.Id = "DICE"
Dice.Label = "DICE"
Dice.Icon = "IconDice"
Dice.Fallback = Sprites.Icon.Roll -- tinted glyph for dice without art
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

function Dice.GetItems(meta)
	local items = {}
	for _, die in meta and meta.Dice or {} do
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
				Tint = info.Color,
				TopTag = if equipped then "EQUIPPED" else nil,
				TopTagStyle = "Equipped",
				SubTag = string.upper(info.Rarity),
				Footer = "Lv. " .. tostring(die.Level),
			})
		end
	end
	for _, die in Display.Locked do
		table.insert(items, {
			Id = die.Id,
			Name = die.Name,
			Rarity = die.Rarity,
			Level = 0,
			Locked = true,
			Equipped = false,
			Icon = art(die.Id),
			CornerBadge = "Lock",
			SubTag = string.upper(die.Rarity),
			Footer = "Locked",
		})
	end
	return items
end

-- Buttons: one size, EQUIP only valid for an owned die not in the deck.
function Dice.Detail(item)
	local locked = item.Locked == true
	local equipped = item.Equipped == true
	local hint = if locked then "Locked" else nil
	local equipOk = not locked and not equipped
	return {
		Name = item.Name,
		Rarity = item.Rarity,
		StatusTag = if equipped then "EQUIPPED" else nil,
		Icon = item.Icon,
		Tint = item.Tint,
		Subline = if locked then nil else { Kind = "Level", Value = item.Level, Max = Dice.MaxLevel },
		Description = if locked then "Not available yet" else "",
		Buttons = {
			{
				Id = "Equip",
				Label = "EQUIP",
				Style = "Green",
				Enabled = equipOk,
				Hint = hint or "Already equipped",
			},
			{ Id = "Lock", Label = "LOCK", Style = "Gold", Enabled = false, Hint = hint or "Coming soon" },
			{ Id = "Sell", Label = "SELL", Style = "Red", Enabled = false, Hint = hint or "Coming soon" },
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
