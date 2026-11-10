-- Persisted player profile, v2 (docs/MVP.md "Profile"). Pure: no Instances.
-- Default() builds a new profile; Migrate() validates stored data. The store
-- metadata (profileRevision, sessionLease) rides along but is not gameplay data.

local Dice = require(script.Parent.Parent.Config.Dice)
local Quests = require(script.Parent.Parent.Config.Quests)
local Deck = require(script.Parent.Deck)
local Validate = require(script.Parent.Validate)

local ProfileSchema = {}

ProfileSchema.VERSION = 2

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = deepCopy(inner)
	end
	return copy
end
ProfileSchema.DeepCopy = deepCopy

local function starterDice()
	local owned = {}
	for _, id in Dice.Deck do
		owned[id] = { Level = 1, Copies = 0 }
	end
	return owned
end

function ProfileSchema.Default()
	return {
		Version = ProfileSchema.VERSION,
		Gold = 0,
		BestWave = 0,
		RunsPlayed = 0,
		TrialCleared = false,
		LastRewardRunId = 0,
		profileRevision = 0,
		Dice = starterDice(),
		Deck = table.clone(Dice.Deck),
		Claimed = {},
		Daily = { Day = 0, Kills = 0, Claimed = {} },
	}
end

-- Pure migrations: MIGRATIONS[n] upgrades a version-n profile (a copy) to n + 1.
local MIGRATIONS: { [number]: (any) -> any } = {
	-- v1 -> v2: the new fields start empty; sanitising below fills the defaults.
	[1] = function(data)
		data.Dice, data.Deck, data.Claimed, data.Daily = nil, nil, nil, nil
		return data
	end,
}

local function count(value: any): number
	return if Validate.IsInt(value, 0, Validate.MAX_INT) then value else 0
end

-- Owned dice: known catalog ids only, Level 1..10, Copies a count; starters always present.
local function cleanDice(stored: any)
	local owned = starterDice()
	if type(stored) == "table" then
		for id, entry in stored do
			if type(id) == "string" and Dice.Types[id] ~= nil and type(entry) == "table" then
				owned[id] = {
					Level = if Validate.IsInt(entry.Level, 1, 10) then entry.Level else 1,
					Copies = count(entry.Copies),
				}
			end
		end
	end
	return owned
end

-- Keeps only `true` flags for ids that exist in the catalog and pass `accept`.
local function cleanFlags(stored: any, accept: (any) -> boolean)
	local flags = {}
	if type(stored) == "table" then
		for id, flag in stored do
			if type(id) == "string" and flag == true then
				local quest = Quests.ById[id]
				if quest ~= nil and accept(quest) then
					flags[id] = true
				end
			end
		end
	end
	return flags
end

local function cleanDaily(stored: any)
	local daily = if type(stored) == "table" then stored else {}
	return {
		Day = count(daily.Day),
		Kills = count(daily.Kills),
		Claimed = cleanFlags(daily.Claimed, function(quest)
			return quest.Daily == true
		end),
	}
end

-- Returns (profile) or (nil, problem). Problems: "Corrupt", "NewerVersion". A nil
-- `stored` is a brand-new player and yields Default(). Never mutates `stored`.
function ProfileSchema.Migrate(stored: any)
	if stored == nil then
		return ProfileSchema.Default()
	end
	if type(stored) ~= "table" or not Validate.IsInt(stored.Version, 1, 2 ^ 31) then
		return nil, "Corrupt"
	end
	if stored.Version > ProfileSchema.VERSION then
		return nil, "NewerVersion"
	end

	local data = stored
	if data.Version < ProfileSchema.VERSION then
		data = deepCopy(stored)
		while data.Version < ProfileSchema.VERSION do
			local step = MIGRATIONS[data.Version]
			if step == nil then
				return nil, "Corrupt"
			end
			data = step(data)
			data.Version += 1
		end
	end

	local dice = cleanDice(data.Dice)
	local deck = if Deck.Check(dice, data.Deck) then table.clone(data.Deck) else table.clone(Dice.Deck)

	local profile = {
		Version = ProfileSchema.VERSION,
		Gold = count(data.Gold),
		BestWave = count(data.BestWave),
		RunsPlayed = count(data.RunsPlayed),
		TrialCleared = data.TrialCleared == true,
		LastRewardRunId = if Validate.IsInt(data.LastRewardRunId, 0, 2 ^ 31 - 1) then data.LastRewardRunId else 0, -- run ids are 31-bit
		profileRevision = Validate.IsInt(data.profileRevision, 0, 2 ^ 52) and data.profileRevision or 0,
		Dice = dice,
		Deck = deck,
		Claimed = cleanFlags(data.Claimed, function(quest)
			return quest.Daily ~= true
		end),
		Daily = cleanDaily(data.Daily),
	}

	-- Store metadata: keep a well-formed lease so a held lease is honoured.
	local lease = data.sessionLease
	if
		type(lease) == "table"
		and type(lease.jobId) == "string"
		and type(lease.expiresAt) == "number"
		and lease.expiresAt == lease.expiresAt
		and lease.expiresAt ~= math.huge
		and lease.expiresAt ~= -math.huge
	then
		profile.sessionLease = { jobId = lease.jobId, expiresAt = lease.expiresAt }
	end
	return profile
end

return ProfileSchema
