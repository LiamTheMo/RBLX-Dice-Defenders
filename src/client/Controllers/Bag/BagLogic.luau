-- Bag pure logic: search filter, stable sort, count formatting, Meta + Catalog inventory rows, quantity stepper,
-- deck compare. No Roblox APIs (unit-tested headless).

local BagLogic = {}

BagLogic.MAX_QTY = 1_000_000 -- server's BagAction qty cap (Rules/Bag.MAX_QTY): a larger qty is a hard strike

local RANK = { Secret = 7, Mythic = 6, Legendary = 5, Epic = 4, Rare = 3, Uncommon = 2, Common = 1 }

function BagLogic.rarityRank(rarity: string?): number
	return RANK[rarity or ""] or 0
end

-- Case-insensitive substring on Name and Rarity; empty / blank query keeps everything.
function BagLogic.filter(items, query: string?)
	local q = string.lower(string.match(query or "", "^%s*(.-)%s*$") or "")
	if q == "" then
		return table.clone(items)
	end
	local out = {}
	for _, item in items do
		if
			string.find(string.lower(item.Name or ""), q, 1, true)
			or string.find(string.lower(item.Rarity or ""), q, 1, true)
		then
			table.insert(out, item)
		end
	end
	return out
end

-- Owned before locked, then the primary key per sort id; true = bigger first. Ties fall back to Name then Id, so the order is total (stable).
local KEYS = {
	Rarity = function(i)
		return BagLogic.rarityRank(i.Rarity), true
	end,
	Level = function(i)
		return i.Level or 0, true
	end,
	Quantity = function(i)
		return i.Quantity or 0, true
	end,
	Equipped = function(i)
		return if i.Equipped then 1 else 0, true
	end,
	Name = function(i)
		return string.lower(i.Name or ""), false
	end,
}

function BagLogic.sort(items, key: string)
	local out = table.clone(items)
	local get = KEYS[key] or KEYS.Name
	table.sort(out, function(a, b)
		if (a.Locked == true) ~= (b.Locked == true) then
			return b.Locked == true -- unowned items always sort after owned ones
		end
		local ka, desc = get(a)
		local kb = get(b)
		if ka ~= kb then
			if desc then
				return ka > kb
			end
			return ka < kb
		end
		local na, nb = string.lower(a.Name or ""), string.lower(b.Name or "")
		if na ~= nb then
			return na < nb
		end
		return tostring(a.Id) < tostring(b.Id)
	end)
	return out
end

local function group(n: number): string
	local s = tostring(n)
	while true do
		local r, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
		s = r
		if k == 0 then
			return s
		end
	end
end

-- 1,248 / 9,999 / 100K / 1.2M
function BagLogic.formatCount(n: number): string
	n = math.floor(n)
	if n >= 1000000 then
		local m = math.floor(n / 100000) / 10
		return (if m % 1 == 0 then string.format("%d", m) else string.format("%.1f", m)) .. "M"
	elseif n >= 100000 then
		return string.format("%d", math.floor(n / 1000)) .. "K"
	end
	return group(n)
end

-- Owned rows for the MATERIALS / ITEMS / COSMETICS tabs (kind = "Materials" | "Items" | "Cosmetics"): Meta's owned
-- ids and quantities joined with the Catalog's display fields (Sell price, Use text), in Meta order. Ids the Catalog
-- lacks are skipped. UserLocked = the player's lock (Meta.Locked); Equipped (cosmetics) comes from Meta.
function BagLogic.inventory(meta, catalog, kind: string)
	local info = {}
	for _, c in catalog and catalog[kind] or {} do
		info[c.Id] = c
	end
	local locked = {}
	for _, id in meta and meta.Locked or {} do
		locked[id] = true
	end
	local rows = {}
	for _, owned in meta and meta[kind] or {} do
		local c = info[owned.Id]
		if c then
			table.insert(rows, {
				Id = c.Id,
				Name = c.Name,
				Rarity = c.Rarity,
				Description = c.Description,
				Quantity = owned.Quantity,
				Icon = c.Icon,
				Type = c.Type,
				Sell = c.Sell,
				Use = c.Use,
				UserLocked = locked[c.Id] == true,
				Equipped = if kind == "Cosmetics" then owned.Equipped == true else nil,
			})
		end
	end
	return rows
end

-- Closest new-art icon (a BagSprites key) per Config/Inventory id. Used only once that sprite has an uploaded
-- image; until then (or for an id without art) `fallback` (the Catalog's own Icon, may be nil) stays.
local ICON = {
	Fragment = "MatSprout",
	XpTome = "ItemXpTicket",
	GoldPouch = "ItemCoinTicket",
	ThornDice = "CosLeafyDie",
	SproutCap = "CosCrown",
	FireflyTrail = "CosOrbitRing",
}
function BagLogic.iconFor(id: string, fallback: string?, sprites): string?
	local s = sprites and sprites[ICON[id]]
	return if s and s.Image ~= "" then ICON[id] else fallback
end

-- Stepper: qty after a step (-1, 1 or "max") within 1..min(owned, MAX_QTY).
function BagLogic.stepQty(qty: number?, delta, owned: number?): number
	local top = math.max(1, math.min(owned or 1, BagLogic.MAX_QTY))
	local q = if delta == "max" then top else (qty or 1) + (if type(delta) == "number" then delta else 0)
	return math.clamp(q, 1, top)
end

-- True when both decks hold the same ids in the same slots.
function BagLogic.sameDeck(a, b): boolean
	if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
		return false
	end
	for i, id in a do
		if b[i] ~= id then
			return false
		end
	end
	return true
end

-- LOCK / UNLOCK detail button for a Material or Item (sends BagAction Lock / Unlock). UNLOCK drops the
-- padlock so the longer label fits the shared action-row text size.
function BagLogic.lockButton(locked: boolean)
	return {
		Id = if locked then "Unlock" else "Lock",
		Label = if locked then "UNLOCK" else "LOCK",
		Style = "Grey",
		Icon = if locked then nil else "Lock",
		Enabled = true,
		Send = true,
	}
end

-- New 5-id deck with `slot` set to `id`, or nil unless the result is exactly 5 distinct owned ids (a malformed
-- EquipDeck is a hard strike on the server, so never send anything this does not return).
function BagLogic.replaceSlot(deck, ownedIds, id, slot)
	if type(deck) ~= "table" or type(ownedIds) ~= "table" or type(id) ~= "string" or #deck ~= 5 then
		return nil
	end
	if type(slot) ~= "number" or slot < 1 or slot > 5 or slot % 1 ~= 0 then
		return nil
	end
	local out = table.clone(deck)
	out[slot] = id
	local seen = {}
	for i = 1, 5 do
		local d = out[i]
		if type(d) ~= "string" or seen[d] or not table.find(ownedIds, d) then
			return nil
		end
		seen[d] = true
	end
	return out
end

return BagLogic
