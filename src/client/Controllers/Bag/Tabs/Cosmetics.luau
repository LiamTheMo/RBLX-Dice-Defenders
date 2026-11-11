-- COSMETICS tab: sample data only (SampleData); every action is a disabled preview.

local SampleData = require(script.Parent.Parent.SampleData)

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

function Cosmetics.GetItems()
	local items = {}
	for i, c in SampleData.Cosmetics do
		items[i] = {
			Id = c.Id,
			Name = c.Name,
			Rarity = c.Rarity,
			Type = c.Type,
			Description = c.Description,
			Equipped = c.Equipped,
			TopTag = string.upper(c.Rarity),
			Footer = if c.Equipped then "EQUIPPED" else nil,
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
		Gap = 8,
		StatusTag = if item.Equipped then "EQUIPPED" else nil,
		Subline = {
			Kind = "Type",
			Text = item.Type,
			Icon = if string.find(item.Type, "Dice") then "IconDice" else "IconCrown",
		},
		Divider = true,
		Description = item.Description,
		Buttons = {
			{ Id = "Equip", Label = "EQUIP", Style = "Green", Enabled = false, Hint = "Coming soon" },
			{ Id = "Unequip", Label = "UNEQUIP", Style = "Red", Enabled = false, Hint = "Coming soon" },
			{ Id = "Lock", Label = "LOCK", Style = "Purple", Icon = "Lock", Enabled = false, Hint = "Coming soon" },
		},
	}
end

return Cosmetics
