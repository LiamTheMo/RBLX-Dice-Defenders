-- Persisted player profile, v10 (docs/MVP.md "Profile"). Pure: no Instances.
-- Default() builds a new profile; Migrate() validates stored data. The store
-- metadata (profileRevision, sessionLease) rides along but is not gameplay data.

local Achievements = require(script.Parent.Parent.Config.Achievements)
local Codes = require(script.Parent.Parent.Config.Codes)
local Dice = require(script.Parent.Parent.Config.Dice)
local Inventory = require(script.Parent.Parent.Config.Inventory)
local Milestones = require(script.Parent.Parent.Config.Milestones)
local Progression = require(script.Parent.Parent.Config.Progression)
local Quests = require(script.Parent.Parent.Config.Quests)
local RollConfig = require(script.Parent.Parent.Config.Roll)
local ShopConfig = require(script.Parent.Parent.Config.Shop)
local SettingsDefs = require(game:GetService("ReplicatedStorage").Shared.SettingsDefs)
local Deck = require(script.Parent.Deck)
local Tutorial = require(script.Parent.Tutorial)
local Validate = require(script.Parent.Validate)

local ProfileSchema = {}

ProfileSchema.VERSION = 11

local LEGACY_STARTER_GEMS = 50 -- old profiles migrating from v3 once (v3 -> v4)

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

-- Rolls since the last Pity.Rarity die per Config/Roll pool: an integer in 0..Max-1, else 0. Walks the pools, so a
-- huge stored table costs nothing.
local function cleanRollPity(stored: any)
	local pity = {}
	for _, pool in RollConfig.Pools do
		local n = if type(stored) == "table" then stored[pool.Id] else nil
		pity[pool.Id] = if Validate.IsInt(n, 0, pool.Pity.Max - 1) then n else 0
	end
	return pity
end

-- Purchases per limited Config/Shop offer: an integer in 1..Limit (0 is not stored). Walks the offers.
local function cleanPurchases(stored: any)
	local purchases = {}
	if type(stored) == "table" then
		for _, offer in ShopConfig.Offers do
			local n = stored[offer.Id]
			if offer.Limit and Validate.IsInt(n, 1, offer.Limit) then
				purchases[offer.Id] = n
			end
		end
	end
	return purchases
end

-- Marketplace PurchaseIds already granted: strings of 1..64 bytes, deduped, the newest MaxReceipts kept in order.
local function cleanReceipts(stored: any)
	local newest, seen = {}, {}
	if type(stored) == "table" then
		for i = #stored, 1, -1 do
			local id = stored[i]
			if type(id) == "string" and #id >= 1 and #id <= 64 and not seen[id] then
				seen[id] = true
				table.insert(newest, 1, id)
				if #newest >= ShopConfig.MaxReceipts then
					break
				end
			end
		end
	end
	return newest
end

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
		Redeemed = {},
		Gems = LEGACY_STARTER_GEMS,
		Xp = 0,
		Materials = {},
		Items = {},
		Cosmetics = { Owned = {}, Equipped = {} },
		Stats = { Kills = 0, Wins = 0, Rolls = 0 },
		Weekly = { Week = 0, Kills = 0, Runs = 0, Claimed = {} },
		Login = { Streak = 0, LastDay = 0 },
		Milestones = {},
		Achievements = {},
		Mastery = {},
		Settings = {},
		Locked = {},
		RollPity = cleanRollPity(nil),
		Purchases = {},
		Receipts = {},
	}
end

local function newProfile()
	local profile = ProfileSchema.Default()
	profile.Gems = 0
	profile.Dice = {}
	profile.Deck = {}
	profile.Tutorial = { Stage = "Roll", Rolls = {} }
	return profile
end

-- v10 -> v11: retired die -> same-rarity replacement.
local RETIRED = { E02 = "E08", E04 = "E07", L03 = "L06" }

local function clampInt(value: any, min: number, max: number, fallback: number): number
	return if Validate.IsInt(value, min, max) then value else fallback
end

-- Moves the retired entries of data.Dice and data.Mastery onto their targets (data is a copy).
local function convertRetired(data)
	local dice, mastery = data.Dice, data.Mastery
	for old, new in RETIRED do
		if type(dice) == "table" and type(dice[old]) == "table" then
			local from, to = dice[old], dice[new]
			local copies = clampInt(from.Copies, 0, Validate.MAX_INT, 0)
			if type(to) == "table" then
				dice[new] = {
					Level = math.max(
						clampInt(from.Level, 1, Progression.DieLevel.Max, 1),
						clampInt(to.Level, 1, Progression.DieLevel.Max, 1)
					),
					Copies = math.min(Validate.MAX_INT, copies + clampInt(to.Copies, 0, Validate.MAX_INT, 0) + 1),
				}
			else
				dice[new] = { Level = from.Level, Copies = from.Copies }
			end
		end
		if type(dice) == "table" then
			dice[old] = nil
		end
		if type(mastery) == "table" and type(mastery[old]) == "table" then
			local from, to = mastery[old], mastery[new]
			if type(to) == "table" then
				local claimed = if type(to.Claimed) == "table" then table.clone(to.Claimed) else {}
				if type(from.Claimed) == "table" then
					for level, flag in from.Claimed do
						claimed[level] = flag
					end
				end
				mastery[new] = {
					Xp = math.min(
						Validate.MAX_INT,
						clampInt(from.Xp, 0, Validate.MAX_INT, 0) + clampInt(to.Xp, 0, Validate.MAX_INT, 0)
					),
					Claimed = claimed,
				}
			else
				mastery[new] = from
			end
			mastery[old] = nil
		end
	end
	if type(data.Deck) == "table" then
		for slot, id in data.Deck do
			if RETIRED[id] then
				data.Deck[slot] = RETIRED[id]
			end
		end
	end
end

-- Pure migrations: MIGRATIONS[n] upgrades a version-n profile (a copy) to n + 1.
local MIGRATIONS: { [number]: (any) -> any } = {
	-- v1 -> v2: the new fields start empty; sanitising below fills the defaults.
	[1] = function(data)
		data.Dice, data.Deck, data.Claimed, data.Daily = nil, nil, nil, nil
		return data
	end,
	-- v2 -> v3: Redeemed starts empty (any stray value is dropped).
	[2] = function(data)
		data.Redeemed = nil
		return data
	end,
	-- v3 -> v4: the starter Gems; any stray value of a new field is dropped.
	[3] = function(data)
		data.Gems, data.Xp, data.Materials, data.Items, data.Cosmetics = LEGACY_STARTER_GEMS, nil, nil, nil, nil
		return data
	end,
	-- v4 -> v5: the progress fields start empty (any stray value is dropped).
	[4] = function(data)
		data.Stats, data.Weekly, data.Login = nil, nil, nil
		data.Milestones, data.Achievements, data.Mastery = nil, nil, nil
		return data
	end,
	-- v5 -> v6: Settings starts empty (any stray value is dropped).
	[5] = function(data)
		data.Settings = nil
		return data
	end,
	-- v6 -> v7: Locked and Cosmetics.Equipped start empty (any stray value is dropped).
	[6] = function(data)
		data.Locked = nil
		if type(data.Cosmetics) == "table" then
			data.Cosmetics.Equipped = nil
		end
		return data
	end,
	-- v7 -> v8: RollPity and Stats.Rolls start empty (any stray value is dropped).
	[7] = function(data)
		data.RollPity = nil
		if type(data.Stats) == "table" then
			data.Stats.Rolls = nil
		end
		return data
	end,
	-- v8 -> v9: Purchases and Receipts start empty (any stray value is dropped).
	[8] = function(data)
		data.Purchases, data.Receipts = nil, nil
		return data
	end,
	-- v9 -> v10: the die level cap drops from 10 to Progression.DieLevel.Max. Levels above it clamp
	-- to it, with no refund: no code path ever raised a level before v10 (levels 8-10 can only be
	-- hand edits, never paid for). From v10 on, any future cap cut needs a refunding migration.
	[9] = function(data)
		local max = Progression.DieLevel.Max
		if type(data.Dice) == "table" then
			for id in Dice.Types do
				local entry = data.Dice[id]
				if type(entry) == "table" and Validate.IsInt(entry.Level, max + 1, 10) then
					entry.Level = max
				end
			end
		end
		return data
	end,
	-- v10 -> v11: E02/E04/L03 are removed; owned copies, mastery and deck slots move to E08/E07/L06.
	[10] = function(data)
		convertRetired(data)
		return data
	end,
}

local function count(value: any): number
	return if Validate.IsInt(value, 0, Validate.MAX_INT) then value else 0
end

-- Owned dice: known catalog ids only, Level 1..DieLevel.Max (anything else resets to 1), Copies a count; starters always present.
local function cleanDice(stored: any, rolling: boolean)
	local owned = if rolling then {} else starterDice()
	if type(stored) == "table" then
		for id, entry in stored do
			if type(id) == "string" and Dice.Types[id] ~= nil and type(entry) == "table" then
				owned[id] = {
					Level = if Validate.IsInt(entry.Level, 1, Progression.DieLevel.Max) then entry.Level else 1,
					Copies = count(entry.Copies),
				}
			end
		end
	end
	return owned
end

-- Keeps only `true` flags for the `list` entries that pass `accept` (default: all).
-- Walks the config list, not the stored table, so an oversized stored table costs nothing.
local function cleanFlags(stored: any, list, accept: ((any) -> boolean)?)
	local flags = {}
	if type(stored) == "table" then
		for _, entry in list do
			if stored[entry.Id] == true and (accept == nil or accept(entry)) then
				flags[entry.Id] = true
			end
		end
	end
	return flags
end

-- Redeemed code ids: `true` flags for ids in the Codes catalog only. Walks the
-- catalog, not the stored table, so an oversized stored table costs nothing.
local function cleanRedeemed(stored: any)
	local redeemed = {}
	if type(stored) == "table" then
		for _, entry in Codes.List do
			if stored[entry.Id] == true then
				redeemed[entry.Id] = true
			end
		end
	end
	return redeemed
end

-- Positive counts for ids in `catalog` only; walks the catalog like cleanRedeemed.
local function cleanCounts(stored: any, catalog)
	local counts = {}
	if type(stored) == "table" then
		for id in catalog do
			if Validate.IsInt(stored[id], 1, Validate.MAX_INT) then
				counts[id] = stored[id]
			end
		end
	end
	return counts
end

-- Owned cosmetics, and Equipped = {[slot] = id} kept only for an owned id in its own Slot.
local function cleanCosmetics(stored: any)
	local owned, equipped = {}, {}
	local flags = if type(stored) == "table" then stored.Owned else nil
	local slots = if type(stored) == "table" then stored.Equipped else nil
	if type(flags) == "table" then
		for id, cosmetic in Inventory.Cosmetics do
			if flags[id] == true then
				owned[id] = true
				if type(slots) == "table" and slots[cosmetic.Slot] == id then
					equipped[cosmetic.Slot] = id
				end
			end
		end
	end
	return { Owned = owned, Equipped = equipped }
end

-- Locked Material and Item ids: `true` flags only; walks the catalogue like cleanCounts.
local function cleanLocked(stored: any)
	local locked = {}
	if type(stored) == "table" then
		for _, catalog in { Inventory.Materials, Inventory.Items } do
			for id in catalog do
				if stored[id] == true then
					locked[id] = true
				end
			end
		end
	end
	return locked
end

local function cleanDaily(stored: any)
	local daily = if type(stored) == "table" then stored else {}
	return {
		Day = count(daily.Day),
		Kills = count(daily.Kills),
		Claimed = cleanFlags(daily.Claimed, Quests.List, function(quest)
			return quest.Daily == true
		end),
	}
end

local function cleanWeekly(stored: any)
	local weekly = if type(stored) == "table" then stored else {}
	return {
		Week = count(weekly.Week),
		Kills = count(weekly.Kills),
		Runs = count(weekly.Runs),
		Claimed = cleanFlags(weekly.Claimed, Quests.List, function(quest)
			return quest.Weekly ~= nil
		end),
	}
end

-- Per known die: mastery Xp and the claimed milestone levels. Claimed is a set keyed
-- by the level as a string ("5"): DataStores and remotes drop sparse numeric keys.
local function cleanMastery(stored: any)
	local mastery = {}
	if type(stored) == "table" then
		for id in Dice.Types do
			local entry = stored[id]
			if type(entry) == "table" then
				local claimed = {}
				if type(entry.Claimed) == "table" then
					for _, level in Progression.Mastery.Milestones do
						if entry.Claimed[tostring(level)] == true or entry.Claimed[level] == true then
							claimed[tostring(level)] = true
						end
					end
				end
				mastery[id] = { Xp = count(entry.Xp), Claimed = claimed }
			end
		end
	end
	return mastery
end

-- Saved client settings: the cleaned value of each registry key that has one (a missing key
-- reads as its default on the client). Walks the registry, so a huge stored table costs nothing.
local function cleanSettings(stored: any)
	local settings = {}
	if type(stored) == "table" then
		for _, def in SettingsDefs.DEFS do
			settings[def.id] = SettingsDefs.clean(def, stored[def.id])
		end
	end
	return settings
end

-- Returns (profile) or (nil, problem). Problems: "Corrupt", "NewerVersion". A nil
-- A nil `stored` starts onboarding. Never mutates `stored`.
function ProfileSchema.Migrate(stored: any)
	if stored == nil then
		return newProfile()
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
	-- Idempotent: also repairs a current-version save that still holds a retired id (hand-edited or restored).
	if data == stored then
		data = deepCopy(stored)
	end
	convertRetired(data)

	local rolling = type(data.Tutorial) == "table" and data.Tutorial.Stage == "Roll"
	local dice = cleanDice(data.Dice, rolling)
	local tutorial = Tutorial.Restore(data.Tutorial, dice)
	local stats = if type(data.Stats) == "table" then data.Stats else {}
	local login = if type(data.Login) == "table" then data.Login else {}
	local deck = if rolling
		then {}
		elseif Deck.Check(dice, data.Deck) then table.clone(data.Deck)
		else table.clone(Dice.Deck)

	local profile = {
		Version = ProfileSchema.VERSION,
		Gold = count(data.Gold),
		BestWave = count(data.BestWave),
		RunsPlayed = count(data.RunsPlayed),
		TrialCleared = data.TrialCleared == true,
		LastRewardRunId = if Validate.IsInt(data.LastRewardRunId, 0, 2 ^ 31 - 1) then data.LastRewardRunId else 0, -- run ids are 31-bit
		profileRevision = Validate.IsInt(data.profileRevision, 0, 2 ^ 52) and data.profileRevision or 0,
		adminEditId = if type(data.adminEditId) == "string" and #data.adminEditId == 36 then data.adminEditId else nil,
		Dice = dice,
		Deck = deck,
		Tutorial = tutorial,
		Claimed = cleanFlags(data.Claimed, Quests.List, function(quest)
			return quest.Daily ~= true and quest.Weekly == nil
		end),
		Daily = cleanDaily(data.Daily),
		Redeemed = cleanRedeemed(data.Redeemed),
		Gems = count(data.Gems),
		Xp = count(data.Xp),
		Materials = cleanCounts(data.Materials, Inventory.Materials),
		Items = cleanCounts(data.Items, Inventory.Items),
		Cosmetics = cleanCosmetics(data.Cosmetics),
		Stats = { Kills = count(stats.Kills), Wins = count(stats.Wins), Rolls = count(stats.Rolls) },
		Weekly = cleanWeekly(data.Weekly),
		Login = {
			Streak = if Validate.IsInt(login.Streak, 0, 7) then login.Streak else 0,
			LastDay = count(login.LastDay),
		},
		Milestones = cleanFlags(data.Milestones, Milestones.List),
		Achievements = cleanFlags(data.Achievements, Achievements.List),
		Mastery = cleanMastery(data.Mastery),
		Settings = cleanSettings(data.Settings),
		Locked = cleanLocked(data.Locked),
		RollPity = cleanRollPity(data.RollPity),
		Purchases = cleanPurchases(data.Purchases),
		Receipts = cleanReceipts(data.Receipts),
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
