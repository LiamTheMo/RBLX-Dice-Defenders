-- Bag pure logic: search filter, stable sort, count formatting. No Roblox APIs (unit-tested headless).

local BagLogic = {}

local RANK = { Mythic = 6, Legendary = 5, Epic = 4, Rare = 3, Uncommon = 2, Common = 1 }

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
