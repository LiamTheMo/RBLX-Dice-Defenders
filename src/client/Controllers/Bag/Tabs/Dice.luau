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
		Aura = s and s.Aura,
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
	local shards = 0
	for _, stack in meta and meta.Materials or {} do
		if stack.Id == "DieShard" then
			shards = stack.Quantity
			break
		end
	end
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
				AttackSpeed = s and s.AttackSpeed,
				Aura = s and s.Aura,
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
				Shards = shards,
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
		table.insert(items, lockedItem(id, info.Name, info.Rarity, "Not owned", "Not owned", stats[id]))
	end
	for _, die in Display.Locked do
		table.insert(items, lockedItem(die.Id, die.Name, die.Rarity, "Locked", "Not available yet"))
	end
	return items
end

-- Damage, Attack Speed (seconds per attack at 1 pip) and the extra effect (Aura: the attack-speed bonus an aura die
-- gives adjacent dice, in percent) come from the Catalog; a dash when the Catalog lacks it or the die has none.
local DASH = "\u{2013}"
local function num(v, suffix: string?): string
	return if type(v) == "number" then string.format("%g", v) .. (suffix or "") else DASH
end
local function stats(item)
	return {
		{ Icon = "IconSword", Label = "Damage", Value = num(item.Damage) },
		{ Icon = "IconHourglass", Label = "Attack Speed", Value = num(item.AttackSpeed, "s") },
		{ Icon = "IconFlame", Label = "Aura", Value = if item.Aura then "+" .. num(item.Aura, "%") else DASH },
	}
end

function Dice.Detail(item)
	local locked = item.Locked == true
	local equipped = item.Equipped == true
	local hint = if locked then item.Footer else nil
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
		BtnW = { 117, 100, 101 },
		TopY = 16,
		ArtY = 28,
		ArtH = 105,
		NameY = 126,
		Ys = { Sub = 166, Desc = 194, Extra = 280 },
		Subline = if copies
			then {
				Kind = "Level",
				Value = item.Level,
				Max = max,
				Copies = copies,
				Progress = if atMax then 1 else math.min(1, item.Copies / cost), -- the bar: spare copies toward the next level
			}
			else nil,
		Description = if item.Ability then item.Ability elseif locked then item.Note else "",
		Stats = stats(item),
		Buttons = {
			{
				Id = if equipped then "Unequip" else "Equip",
				Label = if equipped then "UNEQUIP" else "EQUIP",
				Style = if equipped then "Grey" else "Green",
				Enabled = not locked,
				Hint = hint,
			},
			{
				Id = "Upgrade",
				Label = "UPGRADE",
				Style = "Grey",
				Enabled = upOk,
				Hint = upHint,
			},
			{
				Id = "ConvertShard",
				Label = "USE SHARD",
				Style = "Grey",
				Enabled = not locked and (item.Shards or 0) > 0,
				Hint = hint or "One Dice Shard gives one spare copy",
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
		Button = {
			Label = "UNEQUIP ALL",
			Enabled = #deck > 0,
			Hint = if meta then "No dice equipped" else "Still loading",
		},
	}
end

return Dice
