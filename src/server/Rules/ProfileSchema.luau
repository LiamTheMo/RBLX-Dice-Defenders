-- Persisted player profile, v1 (docs/MVP.md "Profile v1"). Pure: no Instances.
-- Default() builds a new profile; Migrate() validates stored data. The store
-- metadata (profileRevision, sessionLease) rides along but is not gameplay data.

local Validate = require(script.Parent.Validate)

local ProfileSchema = {}

ProfileSchema.VERSION = 1

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

function ProfileSchema.Default()
	return {
		Version = ProfileSchema.VERSION,
		Gold = 0,
		BestWave = 0,
		RunsPlayed = 0,
		TrialCleared = false,
		LastRewardRunId = 0,
		profileRevision = 0,
	}
end

-- Pure migrations: MIGRATIONS[n] upgrades a version-n profile (a copy) to n + 1.
local MIGRATIONS: { [number]: (any) -> any } = {}

local function count(value: any): number
	return if Validate.IsInt(value, 0, Validate.MAX_INT) then value else 0
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

	local profile = {
		Version = ProfileSchema.VERSION,
		Gold = count(data.Gold),
		BestWave = count(data.BestWave),
		RunsPlayed = count(data.RunsPlayed),
		TrialCleared = data.TrialCleared == true,
		LastRewardRunId = count(data.LastRewardRunId),
		profileRevision = Validate.IsInt(data.profileRevision, 0, 2 ^ 52) and data.profileRevision or 0,
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
