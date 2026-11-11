-- MATERIALS tab: sample data only (SampleData); every action is a disabled preview.

local BagLogic = require(script.Parent.Parent.BagLogic)
local SampleData = require(script.Parent.Parent.SampleData)

local Materials = {}

Materials.Id = "MATERIALS"
Materials.Label = "MATERIALS"
Materials.Icon = "IconCrystals"
Materials.Fallback = "IconCrystals"
Materials.Grid = "Materials"
Materials.Placeholder = "Search materials..."
Materials.SortOptions = {
	{ Id = "Rarity", Label = "Rarity" },
	{ Id = "Quantity", Label = "Quantity" },
	{ Id = "Name", Label = "Name" },
}
Materials.DefaultSort = "Rarity"
Materials.EmptyText = "No materials yet"

function Materials.GetItems()
	local items = {}
	for i, m in SampleData.Materials do
		items[i] = {
			Id = m.Id,
			Name = m.Name,
			Rarity = m.Rarity,
			Quantity = m.Quantity,
			Description = m.Description,
			Icon = m.Icon,
			TopTag = string.upper(m.Rarity),
			Footer = "x" .. BagLogic.formatCount(m.Quantity),
		}
	end
	return items
end

function Materials.Detail(item)
	return {
		Name = item.Name,
		Rarity = item.Rarity,
		Header = string.upper(item.Rarity) .. " MATERIAL",
		Upper = true,
		TopY = 10,
		ArtY = 57,
		ArtH = 140,
		NameY = 197,
		Gap = 6,
		DescBox = true,
		Icon = item.Icon,
		Subline = { Kind = "Qty", Text = "Quantity: x" .. BagLogic.formatCount(item.Quantity), W = 229, H = 34 },
		Description = item.Description,
		Stepper = { Qty = 1, Max = item.Quantity, Enabled = false },
		Buttons = {
			{ Id = "Lock", Label = "LOCK", Style = "Purple", Icon = "Lock", Enabled = false, Hint = "Coming soon" },
			{ Id = "Sell", Label = "SELL", Style = "Gold", Icon = "Coins", Enabled = false, Hint = "Coming soon" },
		},
	}
end

return Materials
