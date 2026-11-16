-- Redeem codes (docs/MVP.md). Server-only: lives under ServerScriptService and is
-- never replicated, so clients cannot read the list.
--
-- To add a code, append an entry:
--   Id        stable key saved in profiles. NEW and unique; never rename or reuse one.
--   Code      what players type, already upper case: A-Z, 0-9, '-' and '_' only, at
--             most 32 characters. Players may type it in any case.
--   Gold      Gold granted once per player.
--   Gems      optional Gems granted with it (one Rules/Rewards bundle).
--   StartsAt  optional os.time() seconds (UTC): before it the code reads as Invalid.
--   ExpiresAt optional os.time() seconds (UTC): from then on it reads as Expired.
-- To retire a code, set ExpiresAt. Never delete an entry: saved flags for ids not in
-- this list are dropped on load, so re-adding that Id later would pay out again.
local function code(fields)
	return table.freeze(fields)
end

local List = table.freeze({
	code({ Id = "welcome", Code = "WELCOME", Gold = 100 }), -- = the D1 daily quest Gold
})

local FIELDS =
	{ Id = "string", Code = "string", Gold = "number", Gems = "number", StartsAt = "number", ExpiresAt = "number" }
local function whole(n: any): boolean
	return n == nil or (type(n) == "number" and n == math.floor(n) and n >= 0)
end

local ById, ByCode = {}, {}
for _, entry in List do
	for key, value in entry do -- a typo (Gem = 5) or a wrong type must fail at boot, not pay less or charge the player
		assert(FIELDS[key] == type(value), "Codes: bad field " .. tostring(key) .. " in " .. tostring(entry.Id))
	end
	assert(whole(entry.Gold) and (entry.Gold or 0) > 0, "Codes: Gold must be a positive whole number in " .. entry.Id)
	assert(whole(entry.Gems) and entry.Gems ~= 0, "Codes: Gems must be nil or a positive whole number in " .. entry.Id)
	assert(
		whole(entry.StartsAt) and whole(entry.ExpiresAt),
		"Codes: StartsAt / ExpiresAt must be whole seconds in " .. entry.Id
	)
	assert(ById[entry.Id] == nil and ByCode[entry.Code] == nil, "Codes: duplicate " .. entry.Id)
	ById[entry.Id] = entry
	ByCode[entry.Code] = entry
end

return table.freeze({ List = List, ById = table.freeze(ById), ByCode = table.freeze(ByCode) })
