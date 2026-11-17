-- ITEMS tab: owned items from Meta + Catalog (BagLogic.inventory). USE (items with a Catalog Use text), SELL
-- (Sell x qty) and LOCK / UNLOCK send BagAction; the server applies its own config bundle and price.

local BagLogic = require(script.Parent.Parent.BagLogic)

local Items = {}

Items.Id = "ITEMS"
Items.Label = "ITEMS"
Items.Icon = "IconPotion"
Items.Fallback = "IconPotion"
Items.Grid = "Items"
Items.Placeholder = "Search items..."
Items.SortOptions = {
	{ Id = "Rarity", Label = "Rarity" },
	{ Id = "Quantity", Label = "Quantity (High to Low)" },
	{ Id = "Name", Label = "Name" },
}
Items.DefaultSort = "Quantity"
Items.DetailW = 340 -- mockup detail panel width
Items.EmptyText = "No items yet"

function Items.GetItems(meta, catalog, sprites) -- sprites = BagSprites (nil in headless specs)
	local items = {}
	for i, it in BagLogic.inventory(meta, catalog, "Items") do
		items[i] = {
			Id = it.Id,
			Name = it.Name,
			Rarity = it.Rarity,
			Quantity = it.Quantity,
			Description = it.Description,
			Icon = BagLogic.iconFor(it.Id, it.Icon, sprites),
			Sell = it.Sell,
			Use = it.Use,
			UserLocked = it.UserLocked,
			CornerBadge = if it.UserLocked then "Lock" else nil, -- the padlock badge; not Locked (= unowned, sorted last)
			TopTag = string.upper(it.Rarity),
			Footer = "x" .. BagLogic.formatCount(it.Quantity),
		}
	end
	return items
end

-- `qty` = the stepper's pick (1 when nil), used by both USE and SELL.
function Items.Detail(item, qty: number?)
	local locked = item.UserLocked == true
	local useHint = if locked then "Unlock it first" elseif item.Use == nil then "Can't be used" else nil
	local sellHint = if locked then "Unlock it first" elseif item.Sell == nil then "Can't be sold" else nil
	return {
		BtnW = { 104, 101, 102 },
		Name = item.Name,
		Rarity = item.Rarity,
		NameRibbon = true, -- the Title Case name sits on the gold-rim ribbon
		ArtY = 24,
		ArtH = 184,
		NameY = 211,
		NameDY = -9, -- the ribbon body sits above its box centre: lift the name onto it
		NameMax = 42, -- ref name is 219 px wide (46 gave 238)
		Divider = true,
		DividerLine = true, -- the ref draws a plain thin line here
		DescSize = 26,
		StepInline = true,
		Icon = item.Icon,
		Subline = {
			Kind = "Qty",
			Text = "Quantity: x" .. BagLogic.formatCount(item.Quantity),
			Gold = true,
			W = 223,
			H = 38,
		},
		Description = item.Description
			.. (if item.Sell then (" Sells for %s Gold each."):format(BagLogic.formatCount(item.Sell)) else ""),
		Stepper = {
			Qty = qty or 1,
			Max = item.Quantity,
			Enabled = useHint == nil or sellHint == nil,
			Hint = useHint or sellHint,
		},
		Buttons = {
			{
				Id = "Use",
				Label = "USE",
				Style = "Green",
				Icon = "IconFlaskWhite",
				Enabled = useHint == nil,
				Hint = useHint,
				Send = true,
			},
			BagLogic.lockButton(locked),
			{
				Id = "Sell",
				Label = "SELL",
				Style = "Red",
				Icon = "Coins",
				Enabled = sellHint == nil,
				Hint = sellHint,
				Send = true,
			},
		},
	}
end

return Items
