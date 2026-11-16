-- COSMETICS tab: owned cosmetics from Meta + Catalog (BagLogic.inventory). EQUIP / UNEQUIP send BagAction (one
-- cosmetic per slot, EQUIPPED from Meta); cosmetics have no in-game visuals yet and cannot be locked.

local BagLogic = require(script.Parent.Parent.BagLogic)

local Cosmetics = {}

Cosmetics.Id = "COSMETICS"
Cosmetics.Label = "COSMETICS"
Cosmetics.Icon = "IconCrown"
Cosmetics.Fallback = "IconCrown"
Cosmetics.Grid = "Cosmetics"
Cosmetics.Placeholder = "Search cosmetics..."
Cosmetics.SortOptions = {
	{ Id = "Rarity", Label = "Rarity" },
	{ Id = "Name", Label = "Name" },
	{ Id = "Equipped", Label = "Equipped" },
}
Cosmetics.DefaultSort = "Rarity"
Cosmetics.EmptyText = "No cosmetics yet"

function Cosmetics.GetItems(meta, catalog)
	local items = {}
	for i, c in BagLogic.inventory(meta, catalog, "Cosmetics") do
		items[i] = {
			Id = c.Id,
			Name = c.Name,
			Rarity = c.Rarity,
			Type = c.Type,
			Description = c.Description,
			Equipped = c.Equipped,
			TopTag = if c.Equipped then "EQUIPPED" else nil, -- Dice-style card: EQUIPPED pill, rarity pill, and the type where Dice shows Lv.
			TopTagStyle = "Equipped",
			SubTag = string.upper(c.Rarity),
			Footer = (string.gsub(c.Type, " %(Cosmetic%)$", "")),
		}
	end
	return items
end

function Cosmetics.Detail(item)
	return {
		Name = item.Name,
		Rarity = item.Rarity,
		Upper = true,
		CenterTag = true,
		Ring = true,
		Flags = true,
		TopY = 18,
		ArtY = 66,
		ArtH = 175,
		NameY = 254,
		StatusTag = if item.Equipped then "EQUIPPED" else nil,
		Subline = {
			Kind = "Type",
			Text = item.Type,
			Icon = if string.find(item.Type, "Dice") then "IconDice" else "IconCrown",
		},
		Divider = true,
		DescSize = 23,
		Description = item.Description .. " No visual effect yet.",
		Buttons = {
			{
				Id = "Equip",
				Label = "EQUIP",
				Style = "Green",
				Enabled = not item.Equipped,
				Hint = "Already equipped",
				Send = true,
			},
			{
				Id = "Unequip",
				Label = "UNEQUIP",
				Style = "Red",
				Enabled = item.Equipped == true,
				Hint = "Not equipped",
				Send = true,
			},
			{
				Id = "Lock",
				Label = "LOCK",
				Style = "Purple",
				Icon = "Lock",
				Enabled = false,
				Hint = "Cosmetics can't be locked",
			},
		},
	}
end

return Cosmetics
