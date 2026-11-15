-- Redeem codes (docs/MVP.md). Server-only: lives under ServerScriptService and is
-- never replicated, so clients cannot read the list.
--
-- To add a code, append an entry:
--   Id        stable key saved in profiles. NEW and unique; never rename or reuse one.
--   Code      what players type, already upper case: A-Z, 0-9, '-' and '_' only, at
--             most 32 characters. Players may type it in any case.
--   Gold      Gold granted once per player.
--   StartsAt  optional os.time() seconds (UTC): before it the code reads as Invalid.
--   ExpiresAt optional os.time() seconds (UTC): from then on it reads as Expired.
-- To retire a code, set ExpiresAt. Never delete an entry: saved flags for ids not in
-- this list are dropped on load, so re-adding that Id later would pay out again.
local function code(fields)
	return table.freeze(fields)
end

local List = table.freeze({
	code({ Id = "welcome", Code = "WELCOME", Gold = 100 }), -- = the D1 daily quest reward
})

local ById, ByCode = {}, {}
for _, entry in List do
	assert(ById[entry.Id] == nil and ByCode[entry.Code] == nil, "Codes: duplicate " .. entry.Id)
	ById[entry.Id] = entry
	ByCode[entry.Code] = entry
end

return table.freeze({ List = List, ById = table.freeze(ById), ByCode = table.freeze(ByCode) })
