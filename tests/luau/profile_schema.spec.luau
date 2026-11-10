-- Profile v2: defaults, nil -> default, Corrupt / NewerVersion reported (never
-- repaired), field sanitising, store metadata kept, input never mutated.

local Server = game:GetService("ServerScriptService").Server
local ProfileSchema = require(Server.Rules.ProfileSchema)
local Dice = require(Server.Config.Dice)

local NAN, INF = 0 / 0, math.huge

test("default profile has the v2 fields", function()
	local p = ProfileSchema.Default()
	expectEq(p.Version, 2, "version")
	expectEq(p.Gold, 0, "gold")
	expectEq(p.BestWave, 0, "best wave")
	expectEq(p.RunsPlayed, 0, "runs")
	expectEq(p.TrialCleared, false, "cleared")
	expectEq(p.LastRewardRunId, 0, "last reward run")
	expectEq(p.profileRevision, 0, "revision")
	expectEq(p.sessionLease, nil, "no lease")
	expectEq(#p.Deck, 5, "starter deck")
	for i, id in Dice.Deck do
		expectEq(p.Deck[i], id, "deck slot " .. i)
		expect(p.Dice[id].Level == 1 and p.Dice[id].Copies == 0, "starter die " .. id)
	end
	expect(next(p.Claimed) == nil, "nothing claimed")
	expect(p.Daily.Day == 0 and p.Daily.Kills == 0 and next(p.Daily.Claimed) == nil, "daily empty")
	expect(p.Deck ~= Dice.Deck, "deck is a fresh table")
end)

test("nil is a new player", function()
	local p, problem = ProfileSchema.Migrate(nil)
	expect(p ~= nil and problem == nil, "default returned")
	expectEq(p.Gold, 0, "default gold")
end)

test("bad shape is Corrupt, a newer version is NewerVersion; neither is repaired", function()
	for _, bad in
		{
			"garbage",
			5,
			true,
			{},
			{ Gold = 5 },
			{ Version = "1" },
			{ Version = 0 },
			{ Version = -1 },
			{ Version = 1.5 },
			{ Version = NAN },
			{ Version = INF },
		}
	do
		local p, problem = ProfileSchema.Migrate(bad)
		expect(
			p == nil and problem == "Corrupt",
			"Corrupt for " .. tostring(type(bad) == "table" and bad.Version or bad)
		)
	end
	local p, problem = ProfileSchema.Migrate({ Version = 3, Gold = 5 })
	expect(p == nil and problem == "NewerVersion", "v3 refused")
	local p2, problem2 = ProfileSchema.Migrate({ Version = 99 })
	expect(p2 == nil and problem2 == "NewerVersion", "v99 refused")
end)

test("every field is sanitised to an integer in [0, 1e9] or its default", function()
	local stored = {
		Version = 1,
		Gold = -5.7,
		BestWave = 3.5,
		RunsPlayed = INF,
		TrialCleared = "yes",
		LastRewardRunId = NAN,
		profileRevision = "x",
		Extra = 1,
	}
	local p = ProfileSchema.Migrate(stored)
	expectEq(p.Gold, 0, "negative fraction")
	expectEq(p.BestWave, 0, "fraction")
	expectEq(p.RunsPlayed, 0, "inf")
	expectEq(p.TrialCleared, false, "non-boolean")
	expectEq(p.LastRewardRunId, 0, "nan")
	expectEq(p.profileRevision, 0, "string revision")
	expectEq(p.Extra, nil, "unknown field dropped")

	local big = ProfileSchema.Migrate({ Version = 1, Gold = 2e9, BestWave = 7 })
	expectEq(big.Gold, 0, "over 1e9")
	expectEq(big.BestWave, 7, "valid value kept")

	local missing = ProfileSchema.Migrate({ Version = 1 })
	expect(missing.Gold == 0 and missing.BestWave == 0 and missing.TrialCleared == false, "nil -> default per field")
end)

test("a well-formed lease and revision are kept; a malformed lease is dropped", function()
	local p = ProfileSchema.Migrate({
		Version = 1,
		Gold = 12,
		TrialCleared = true,
		profileRevision = 41,
		sessionLease = { jobId = "A", expiresAt = 1234.5, junk = 1 },
	})
	expectEq(p.profileRevision, 41, "revision kept")
	expect(p.sessionLease ~= nil and p.sessionLease.jobId == "A" and p.sessionLease.expiresAt == 1234.5, "lease kept")
	expectEq(p.sessionLease.junk, nil, "lease fields trimmed")
	expectEq(p.TrialCleared, true, "boolean kept")
	for _, lease in
		{
			"x",
			{},
			{ jobId = 1, expiresAt = 5 },
			{ jobId = "A" },
			{ jobId = "A", expiresAt = NAN },
			{ jobId = "A", expiresAt = INF },
		}
	do
		local q = ProfileSchema.Migrate({ Version = 1, sessionLease = lease })
		expectEq(q.sessionLease, nil, "malformed lease dropped")
	end
end)

test("Migrate never mutates its input and is idempotent", function()
	local stored = table.freeze({
		Version = 1,
		Gold = -3,
		BestWave = 4,
		sessionLease = table.freeze({ jobId = "A", expiresAt = 9 }),
	})
	local p = ProfileSchema.Migrate(stored) -- would error on a write to the frozen table
	expectEq(stored.Gold, -3, "input untouched")
	expect(p ~= stored and p.sessionLease ~= stored.sessionLease, "fresh tables")
	local again = ProfileSchema.Migrate(p)
	expectEq(again.BestWave, 4, "stable")
	expectEq(again.Gold, 0, "stable")
	expectEq(again.sessionLease.jobId, "A", "lease stable")
end)

test("DeepCopy copies nested tables", function()
	local a = { x = { y = 1 } }
	local b = ProfileSchema.DeepCopy(a)
	b.x.y = 2
	expectEq(a.x.y, 1, "independent")
end)

test("LastRewardRunId keeps any 31-bit run id; larger or fractional values reset to 0", function()
	expectEq(ProfileSchema.Migrate({ Version = 1, LastRewardRunId = 2e9 }).LastRewardRunId, 2e9, "2e9 kept")
	expectEq(
		ProfileSchema.Migrate({ Version = 1, LastRewardRunId = 2 ^ 31 - 1 }).LastRewardRunId,
		2 ^ 31 - 1,
		"max kept"
	)
	expectEq(ProfileSchema.Migrate({ Version = 1, LastRewardRunId = 2 ^ 31 }).LastRewardRunId, 0, "above max")
	expectEq(ProfileSchema.Migrate({ Version = 1, LastRewardRunId = 5.5 }).LastRewardRunId, 0, "fractional")
end)

test("v1 -> v2 keeps stats, adds starters, claims nothing, never touches a frozen input", function()
	local stored = table.freeze({
		Version = 1,
		Gold = 70,
		BestWave = 6,
		RunsPlayed = 3,
		TrialCleared = true,
		LastRewardRunId = 99,
		profileRevision = 4,
		-- stray v2-shaped data in a v1 record is discarded by the migration
		Claimed = table.freeze({ S1 = true }),
		Deck = table.freeze({ "C01" }),
	})
	local p = ProfileSchema.Migrate(stored)
	expect(p.Version == 2 and p.Gold == 70 and p.BestWave == 6 and p.RunsPlayed == 3, "stats kept")
	expect(p.TrialCleared == true and p.LastRewardRunId == 99 and p.profileRevision == 4, "rest kept")
	expectEq(#p.Deck, 5, "starter deck")
	expect(p.Dice.C05 ~= nil, "starters")
	expect(next(p.Claimed) == nil, "nothing claimed")
	expectEq(p.Daily.Day, 0, "daily empty")
end)

test("Dice are sanitised: unknown ids, bad entries, levels and copies; starters re-added", function()
	local p = ProfileSchema.Migrate({
		Version = 2,
		Dice = {
			C01 = { Level = 99, Copies = -1 },
			C02 = { Level = 4.5, Copies = 7 },
			C03 = { Level = 3, Copies = 12 },
			Z99 = { Level = 1, Copies = 1 },
			C04 = "x",
			[1] = { Level = 1, Copies = 1 },
		},
	})
	expect(p.Dice.C01.Level == 1 and p.Dice.C01.Copies == 0, "bad level/copies reset")
	expect(p.Dice.C02.Level == 1 and p.Dice.C02.Copies == 7, "fractional level reset, copies kept")
	expect(p.Dice.C03.Level == 3 and p.Dice.C03.Copies == 12, "valid kept")
	expectEq(p.Dice.Z99, nil, "unknown id dropped")
	expect(p.Dice.C04.Level == 1 and p.Dice.C04.Copies == 0, "non-table entry replaced by starter")
	expectEq(p.Dice[1], nil, "non-string key dropped")
	expect(p.Dice.C05 ~= nil, "missing starter re-added")
end)

test("an illegal Deck resets to the starter deck; a legal one is kept as a copy", function()
	local stored = { Version = 2, Deck = { "C05", "C04", "C03", "C02", "C01" } }
	local p = ProfileSchema.Migrate(stored)
	expectEq(p.Deck[1], "C05", "legal permutation kept")
	expect(p.Deck ~= stored.Deck, "copied")
	for _, bad in
		{
			{ "C01" },
			{ "C01", "C01", "C02", "C03", "C04" },
			{ "C01", "C02", "C03", "C04", "ZZZ" },
			{ "C01", "C02", "C03", "C04", "C05", x = 1 },
			"C01",
		}
	do
		local q = ProfileSchema.Migrate({ Version = 2, Deck = bad })
		expect(#q.Deck == 5 and q.Deck[1] == "C01" and q.Deck[5] == "C05", "reset to starter")
	end
	local unowned = ProfileSchema.Migrate({ Version = 2, Deck = { "C01", "C02", "C03", "C04", "R01" } })
	expectEq(unowned.Deck[5], "C05", "unknown die resets deck")
end)

test("Claimed and Daily keep only true flags of the right kind and sane counts", function()
	local p = ProfileSchema.Migrate({
		Version = 2,
		Claimed = { S1 = true, S2 = false, S3 = "yes", D1 = true, Nope = true, [1] = true },
		Daily = { Day = 20000.5, Kills = 2e9, Claimed = { D1 = true, S1 = true, Nope = true, X = false } },
	})
	expect(p.Claimed.S1 == true and p.Claimed.S2 == nil and p.Claimed.S3 == nil, "one-time flags")
	expectEq(p.Claimed.D1, nil, "daily id not a one-time claim")
	expectEq(p.Claimed.Nope, nil, "unknown id")
	expect(p.Daily.Day == 0 and p.Daily.Kills == 0, "bad counts reset")
	expect(p.Daily.Claimed.D1 == true and p.Daily.Claimed.S1 == nil and p.Daily.Claimed.Nope == nil, "daily flags")
	local q = ProfileSchema.Migrate({ Version = 2, Claimed = "x", Daily = "y" })
	expect(next(q.Claimed) == nil and q.Daily.Day == 0, "non-tables default")
	local r = ProfileSchema.Migrate({ Version = 2, Daily = { Day = 20000, Kills = 12 } })
	expect(r.Daily.Day == 20000 and r.Daily.Kills == 12, "valid daily kept")
end)

test("Migrate is idempotent on v2 and never mutates a frozen v2 input", function()
	local first = ProfileSchema.Migrate({
		Version = 2,
		Gold = 5,
		Deck = { "C02", "C01", "C03", "C04", "C05" },
		Claimed = { S1 = true },
		Daily = { Day = 7, Kills = 3, Claimed = { D1 = true } },
	})
	local second = ProfileSchema.Migrate(ProfileSchema.DeepCopy(first))
	expectEq(second.Deck[1], "C02", "deck stable")
	expect(second.Claimed.S1 == true and second.Daily.Claimed.D1 == true and second.Daily.Day == 7, "flags stable")
	local frozen = table.freeze({ Version = 2, Dice = table.freeze({ C01 = table.freeze({ Level = 2, Copies = 1 }) }) })
	local p = ProfileSchema.Migrate(frozen)
	expectEq(p.Dice.C01.Level, 2, "read from frozen")
end)
