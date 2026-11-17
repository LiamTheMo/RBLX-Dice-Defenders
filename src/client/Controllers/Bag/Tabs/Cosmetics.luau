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
	{ Id = "Rarity", Label = "Rarity (High to Low)" },
	{ Id = "Name", Label = "Name" },
	{ Id = "Equipped", Label = "Equipped" },
}
Cosmetics.DefaultSort = "Rarity"
Cosmetics.DetailW = 323 -- mockup detail panel width
Cosmetics.EmptyText = "No cosmetics yet"

function Cosmetics.GetItems(meta, catalog, sprites) -- sprites = BagSprites (nil in headless specs)
	local items = {}
	for i, c in BagLogic.inventory(meta, catalog, "Cosmetics") do
		items[i] = {
			Id = c.Id,
			Name = c.Name,
			Rarity = c.Rarity,
			Type = c.Type,
			Icon = BagLogic.iconFor(c.Id, nil, sprites),
			Description = c.Description,
			Equipped = c.Equipped,
			TopTag = string.upper(c.Rarity), -- card: rarity pill on top, name below, green EQUIPPED pill in its place when equipped
		}
	end
	return items
end

-- "24 / 60" counter beside the sort field: owned / total cosmetics in the Catalog (nil until it loads).
function Cosmetics.Count(meta, catalog): string?
	if not (catalog and catalog.Cosmetics) then
		return nil
	end
	return ("%d / %d"):format(#BagLogic.inventory(meta, catalog, "Cosmetics"), #catalog.Cosmetics)
end

function Cosmetics.Detail(item)
	return {
		BtnW = { 94, 94, 92 },
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
		Icon = item.Icon,
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
				Style = "Grey",
				Enabled = item.Equipped == true,
				Hint = "Not equipped",
				Send = true,
			},
			{
				Id = "Lock",
				Label = "LOCK",
				Style = "Grey",
				Icon = "Lock",
				Enabled = false,
				Hint = "Cosmetics can't be locked",
			},
		},
	}
end

return Cosmetics
