-- Deck rules: up to SIZE distinct owned die ids in a dense array. Pure.
local Dice = require(script.Parent.Parent.Config.Dice)

local Deck = {}

Deck.SIZE = 5

-- True for a dense array of up to SIZE distinct strings of 1..8 bytes. Untrusted input:
-- stops counting past SIZE entries, so a huge table is never fully scanned.
function Deck.Shape(ids: any): boolean
	if type(ids) ~= "table" then
		return false
	end
	local n = 0
	local seen = {}
	for key, id in ids do
		n += 1
		if n > Deck.SIZE then
			return false
		end
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > Deck.SIZE then
			return false
		end
		if type(id) ~= "string" or #id < 1 or #id > 8 or seen[id] then
			return false
		end
		seen[id] = true
	end
	for i = 1, n do
		if ids[i] == nil then
			return false
		end
	end
	return true
end

-- Codes: BadDeck (shape), UnknownDie (not in the catalog), NotOwned.
function Deck.Check(owned: any, ids: any): (boolean, string?)
	if not Deck.Shape(ids) or type(owned) ~= "table" then
		return false, "BadDeck"
	end
	for _, id in ids do
		if Dice.Types[id] == nil then
			return false, "UnknownDie"
		end
	end
	for _, id in ids do
		if type(owned[id]) ~= "table" then
			return false, "NotOwned"
		end
	end
	return true, nil
end

-- Validates, then replaces profile.Deck with a copy. A rejected call changes nothing.
function Deck.Equip(profile: any, ids: any): (boolean, string?)
	local ok, code = Deck.Check(profile.Dice, ids)
	if not ok then
		return false, code
	end
	profile.Deck = table.clone(ids)
	return true, nil
end

function Deck.IsReady(profile): boolean
	return Deck.Check(profile.Dice, profile.Deck) and #profile.Deck == Deck.SIZE
end

return Deck
