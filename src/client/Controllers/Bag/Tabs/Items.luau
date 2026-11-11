-- ITEMS tab: sample data only (SampleData); every action is a disabled preview.

local BagLogic = require(script.Parent.Parent.BagLogic)
local SampleData = require(script.Parent.Parent.SampleData)

local Items = {}

Items.Id = "ITEMS"
Items.Label = "ITEMS"
Items.Icon = "IconPotion"
Items.Fallback = "IconPotion"
Items.Grid = "Items"
Items.Placeholder = "Search items..."
Items.SortOptions = {
	{ Id = "Rarity", Label = "Rarity" },
	{ Id = "Quantity", Label = "Quantity" },
	{ Id = "Name", Label = "Name" },
}
Items.DefaultSort = "Quantity"
Items.EmptyText = "No items yet"

function Items.GetItems()
	local items = {}
	for i, it in SampleData.Items do
		items[i] = {
			Id = it.Id,
			Name = it.Name,
			Rarity = it.Rarity,
			Quantity = it.Quantity,
			Description = it.Description,
			Icon = it.Icon,
			TopTag = string.upper(it.Rarity),
			Footer = "x" .. BagLogic.formatCount(it.Quantity),
		}
	end
	return items
end

function Items.Detail(item)
	return {
		Name = item.Name,
		Rarity = item.Rarity,
		Header = string.upper(item.Rarity) .. " ITEM",
		DescBox = true,
		Icon = item.Icon,
		Subline = { Kind = "Qty", Text = "Quantity: x" .. BagLogic.formatCount(item.Quantity) },
		Description = item.Description,
		Stepper = { Qty = 1, Max = item.Quantity, Enabled = false },
		Buttons = {
			{ Id = "Use", Label = "USE", Style = "Green", Enabled = false, Hint = "Coming soon" },
			{ Id = "Lock", Label = "LOCK", Style = "Purple", Icon = "Lock", Enabled = false, Hint = "Coming soon" },
			{ Id = "Sell", Label = "SELL", Style = "Red", Icon = "Coins", Enabled = false, Hint = "Coming soon" },
		},
	}
end

return Items
