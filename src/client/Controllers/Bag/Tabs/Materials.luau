-- MATERIALS tab: owned materials from Meta + Catalog (BagLogic.inventory). SELL (Sell x qty) and LOCK / UNLOCK
-- send BagAction; the server prices it from its own config.

local BagLogic = require(script.Parent.Parent.BagLogic)

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

function Materials.GetItems(meta, catalog)
	local items = {}
	for i, m in BagLogic.inventory(meta, catalog, "Materials") do
		items[i] = {
			Id = m.Id,
			Name = m.Name,
			Rarity = m.Rarity,
			Quantity = m.Quantity,
			Description = m.Description,
			Icon = m.Icon,
			Sell = m.Sell,
			UserLocked = m.UserLocked,
			CornerBadge = if m.UserLocked then "Lock" else nil, -- the padlock badge; not Locked (= unowned, sorted last)
			TopTag = string.upper(m.Rarity),
			Footer = "x" .. BagLogic.formatCount(m.Quantity),
		}
	end
	return items
end

-- `qty` = the stepper's pick (1 when nil).
function Materials.Detail(item, qty: number?)
	local locked = item.UserLocked == true
	local sellHint = if locked then "Unlock it first" elseif item.Sell == nil then "Can't be sold" else nil
	return {
		Name = item.Name,
		Rarity = item.Rarity,
		Header = string.upper(item.Rarity) .. " MATERIAL",
		Upper = true,
		TopY = 10,
		ArtY = 57,
		ArtH = 140,
		NameY = 197,
		DescBox = true,
		DescSize = 26,
		Icon = item.Icon,
		Subline = { Kind = "Qty", Text = "Quantity: x" .. BagLogic.formatCount(item.Quantity), W = 229, H = 34 },
		Description = item.Description
			.. (if item.Sell then (" Sells for %s Gold each."):format(BagLogic.formatCount(item.Sell)) else ""),
		Stepper = { Qty = qty or 1, Max = item.Quantity, Enabled = sellHint == nil, Hint = sellHint },
		Buttons = {
			BagLogic.lockButton(locked),
			{
				Id = "Sell",
				Label = "SELL",
				Style = "Gold",
				Icon = "Coins",
				Enabled = sellHint == nil,
				Hint = sellHint,
				Send = true,
			},
		},
	}
end

return Materials
