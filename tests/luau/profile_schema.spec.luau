-- Profile v1: defaults, nil -> default, Corrupt / NewerVersion reported (never
-- repaired), field sanitising, store metadata kept, input never mutated.

local Server = game:GetService("ServerScriptService").Server
local ProfileSchema = require(Server.Rules.ProfileSchema)

local NAN, INF = 0 / 0, math.huge

test("default profile has the v1 fields", function()
	local p = ProfileSchema.Default()
	expectEq(p.Version, 1, "version")
	expectEq(p.Gold, 0, "gold")
	expectEq(p.BestWave, 0, "best wave")
	expectEq(p.RunsPlayed, 0, "runs")
	expectEq(p.TrialCleared, false, "cleared")
	expectEq(p.LastRewardRunId, 0, "last reward run")
	expectEq(p.profileRevision, 0, "revision")
	expectEq(p.sessionLease, nil, "no lease")
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
	local p, problem = ProfileSchema.Migrate({ Version = 2, Gold = 5 })
	expect(p == nil and problem == "NewerVersion", "v2 refused")
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
