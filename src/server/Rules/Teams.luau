-- Team presets: SIZE saved loadouts per profile (profile.Teams["1"]..["5"], each a Deck-shaped array). Pure.
-- Saving copies the equipped deck into a slot; loading equips a slot through Deck.Equip. Keys are strings so the
-- table stays a plain map in the data store.
local Deck = require(script.Parent.Deck)
local Validate = require(script.Parent.Validate)

local Teams = {}

Teams.SIZE = 5

-- (action, slot) after the leading seq: "Save" | "Load" and a slot 1..SIZE. Untrusted input.
function Teams.Shape(action: any, slot: any): boolean
	return (action == "Save" or action == "Load") and Validate.IsInt(slot, 1, Teams.SIZE)
end

-- Cleaned copy of a stored Teams table: only slots whose dice are all still owned and well formed (a die sold
-- or retired empties the team that held it).
function Teams.Clean(stored: any, owned: any): { [string]: { string } }
	local teams = {}
	if type(stored) ~= "table" then
		return teams
	end
	for slot = 1, Teams.SIZE do
		local key = tostring(slot)
		local ids = stored[key]
		if type(ids) == "table" and #ids >= 1 and Deck.Check(owned, ids) then
			teams[key] = table.clone(ids)
		end
	end
	return teams
end

-- Codes: BadTeam (action or slot), EmptyDeck (nothing equipped to save), EmptyTeam (nothing saved in that slot),
-- plus Deck.Equip's own codes when a load is refused.
function Teams.Run(profile: any, action: any, slot: any): (boolean, string?)
	if not Teams.Shape(action, slot) then
		return false, "BadTeam"
	end
	local key = tostring(slot)
	if action == "Save" then
		if #profile.Deck < 1 then
			return false, "EmptyDeck"
		end
		profile.Teams[key] = table.clone(profile.Deck)
		return true, nil
	end
	local ids = profile.Teams[key]
	if ids == nil then
		return false, "EmptyTeam"
	end
	return Deck.Equip(profile, ids)
end

return Teams
