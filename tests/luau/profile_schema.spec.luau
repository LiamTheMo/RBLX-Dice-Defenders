-- Profile v13: defaults, nil -> tutorial, Corrupt / NewerVersion reported (never
-- repaired), field sanitising, store metadata kept, input never mutated.

local Server = game:GetService("ServerScriptService").Server
local ProfileSchema = require(Server.Rules.ProfileSchema)
local Dice = require(Server.Config.Dice)

local NAN, INF = 0 / 0, math.huge

test("default profile has the v13 fields", function()
	local p = ProfileSchema.Default()
	expectEq(p.Version, 13, "version")
	expectEq(p.RollPity.Standard, 0, "no rolls toward the Standard guarantee")
	expectEq(p.Stats.Rolls, 0, "no rolls")
	expectEq(p.Gold, 0, "gold")
	expectEq(p.Gems, 50, "starter gems")
	expectEq(p.Xp, 0, "xp")
	expect(next(p.Materials) == nil and next(p.Items) == nil, "no materials or items")
	expect(type(p.Cosmetics) == "table" and next(p.Cosmetics.Owned) == nil, "no cosmetics")
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
	expect(next(p.Redeemed) == nil, "nothing redeemed")
	expect(type(p.Settings) == "table" and next(p.Settings) == nil, "no saved settings")
	expect(type(p.Locked) == "table" and next(p.Locked) == nil, "nothing locked")
	expect(type(p.Cosmetics.Equipped) == "table" and next(p.Cosmetics.Equipped) == nil, "nothing equipped")
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
	local p, problem = ProfileSchema.Migrate({ Version = ProfileSchema.VERSION + 1, Gold = 5 })
	expect(p == nil and problem == "NewerVersion", "newer version refused")
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

test("v1 -> v8 keeps stats, adds starters and 50 Gems, claims and redeems nothing, input untouched", function()
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
		Deck = table.freeze({ [2] = "C01" }),
		Redeemed = table.freeze({ welcome = true }),
		Gems = 999, -- stray v4-shaped data too
		Materials = table.freeze({ Fragment = 9 }),
	})
	local p = ProfileSchema.Migrate(stored)
	expect(p.Version == 13 and p.Gold == 70 and p.BestWave == 6 and p.RunsPlayed == 3, "stats kept")
	expect(p.TrialCleared == true and p.LastRewardRunId == 99 and p.profileRevision == 4, "rest kept")
	expectEq(#p.Deck, 5, "starter deck")
	expect(p.Dice.C05 ~= nil, "starters")
	expect(next(p.Claimed) == nil, "nothing claimed")
	expectEq(p.Daily.Day, 0, "daily empty")
	expect(next(p.Redeemed) == nil, "nothing redeemed")
	expect(p.Gems == 50 and p.Xp == 0 and next(p.Materials) == nil, "v4 starts: 50 Gems, no stray inventory")
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
			{ [2] = "C01" },
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
	for _, deck in { {}, { "C02", "C01" } } do
		local saved = ProfileSchema.Migrate({ Version = ProfileSchema.VERSION, Deck = deck })
		expectEq(table.concat(saved.Deck, ","), table.concat(deck, ","), "empty and partial loadouts survive loading")
	end
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

test("v2 -> v8 keeps every v2 field, starts Redeemed empty, never touches a frozen input", function()
	local stored = table.freeze({
		Version = 2,
		Gold = 70,
		BestWave = 6,
		RunsPlayed = 3,
		TrialCleared = true,
		LastRewardRunId = 99,
		profileRevision = 4,
		Dice = table.freeze({ C01 = table.freeze({ Level = 3, Copies = 2 }) }),
		Deck = table.freeze({ "C05", "C04", "C03", "C02", "C01" }),
		Claimed = table.freeze({ S1 = true }),
		Daily = table.freeze({ Day = 7, Kills = 3, Claimed = table.freeze({ D1 = true }) }),
		sessionLease = table.freeze({ jobId = "A", expiresAt = 9 }),
		Redeemed = table.freeze({ welcome = true }), -- stray: v2 had no codes
	})
	local p = ProfileSchema.Migrate(stored)
	expect(p.Version == 13 and p.Gold == 70 and p.BestWave == 6 and p.RunsPlayed == 3, "stats kept")
	expect(p.TrialCleared == true and p.LastRewardRunId == 99 and p.profileRevision == 4, "rest kept")
	expectEq(p.Gems, 50, "starter gems")
	expect(p.Dice.C01.Level == 3 and p.Dice.C01.Copies == 2 and p.Deck[1] == "C05", "dice and deck kept")
	expect(p.Claimed.S1 == true and p.Daily.Day == 7 and p.Daily.Claimed.D1 == true, "quests kept")
	expectEq(p.sessionLease.jobId, "A", "lease kept")
	expect(type(p.Redeemed) == "table" and next(p.Redeemed) == nil, "Redeemed starts empty")
	expectEq(stored.Version, 2, "input untouched")
end)

test("Redeemed keeps only true flags for catalog code ids; junk and oversized input cost nothing", function()
	local p = ProfileSchema.Migrate({
		Version = 4,
		Redeemed = { welcome = true, nope = true, WELCOME = true, [1] = true, x = false },
	})
	expectEq(p.Redeemed.welcome, true, "catalog id kept")
	local count = 0
	for _ in p.Redeemed do
		count += 1
	end
	expectEq(count, 1, "only the catalog id")
	for _, bad in { { welcome = "true" }, { welcome = 1 }, { welcome = {} }, { welcome = false }, "x", 5, true } do
		local q = ProfileSchema.Migrate({ Version = 4, Redeemed = bad })
		expect(type(q.Redeemed) == "table" and next(q.Redeemed) == nil, "junk -> empty: " .. tostring(bad))
	end
	local huge = { welcome = true }
	for i = 1, 100_000 do
		huge["junk" .. i] = true
		huge[i] = true
	end
	local r = ProfileSchema.Migrate({ Version = 4, Redeemed = huge })
	count = 0
	for id in r.Redeemed do
		count += 1
		expectEq(id, "welcome", "only catalog ids survive")
	end
	expectEq(count, 1, "oversized input bounded by the catalog")
	local again = ProfileSchema.Migrate(ProfileSchema.DeepCopy(r))
	expectEq(again.Redeemed.welcome, true, "idempotent")
end)

test("v3 -> v8 keeps every v3 value, adds 50 Gems and empty inventories, never touches a frozen input", function()
	local stored = table.freeze({
		Version = 3,
		Gold = 70,
		BestWave = 6,
		RunsPlayed = 3,
		TrialCleared = true,
		LastRewardRunId = 99,
		profileRevision = 4,
		Dice = table.freeze({ C01 = table.freeze({ Level = 3, Copies = 2 }) }),
		Deck = table.freeze({ "C05", "C04", "C03", "C02", "C01" }),
		Claimed = table.freeze({ S1 = true }),
		Daily = table.freeze({ Day = 7, Kills = 3, Claimed = table.freeze({ D1 = true }) }),
		Redeemed = table.freeze({ welcome = true }),
		sessionLease = table.freeze({ jobId = "A", expiresAt = 9 }),
		-- stray: v3 had none of these
		Gems = 999,
		Xp = 500,
		Materials = table.freeze({ Fragment = 9 }),
		Items = table.freeze({ XpTome = 2 }),
		Cosmetics = table.freeze({ Owned = table.freeze({ ThornDice = true }) }),
	})
	local p = ProfileSchema.Migrate(stored)
	expect(p.Version == 13 and p.Gold == 70 and p.BestWave == 6 and p.RunsPlayed == 3, "stats kept")
	expect(p.TrialCleared == true and p.LastRewardRunId == 99 and p.profileRevision == 4, "rest kept")
	expect(p.Dice.C01.Level == 3 and p.Dice.C01.Copies == 2 and p.Deck[1] == "C05", "dice and deck kept")
	expect(p.Claimed.S1 == true and p.Daily.Day == 7 and p.Daily.Claimed.D1 == true, "quests kept")
	expect(p.Redeemed.welcome == true and p.sessionLease.jobId == "A", "redeems and lease kept")
	expectEq(p.Gems, 50, "starter gems, stray value dropped")
	expectEq(p.Xp, 0, "stray xp dropped")
	expect(next(p.Materials) == nil and next(p.Items) == nil, "stray materials and items dropped")
	expect(next(p.Cosmetics.Owned) == nil, "stray cosmetics dropped")
	expectEq(stored.Version, 3, "input untouched")
	local again = ProfileSchema.Migrate(ProfileSchema.DeepCopy(p))
	expect(again.Gems == 50 and again.Version == 13, "idempotent: no second grant")
end)

test("Gems, Xp, Materials, Items and Cosmetics keep only valid counts for catalogue ids", function()
	local p = ProfileSchema.Migrate({
		Version = 4,
		Gems = 120,
		Xp = 345,
		Materials = { Fragment = 3, Nope = 5, XpTome = 1, [1] = 2 },
		Items = { XpTome = 2, GoldPouch = 7, Fragment = 4, ThornDice = 1 },
		Cosmetics = { Owned = { ThornDice = true, SproutCap = 1, FireflyTrail = "true", Nope = true } },
	})
	expect(p.Gems == 120 and p.Xp == 345, "valid counters kept")
	expectEq(p.Materials.Fragment, 3, "material kept")
	expect(p.Materials.Nope == nil and p.Materials.XpTome == nil and p.Materials[1] == nil, "unknown material ids")
	expect(p.Items.XpTome == 2 and p.Items.GoldPouch == 7, "items kept")
	expect(p.Items.Fragment == nil and p.Items.ThornDice == nil, "ids from other catalogues dropped")
	expectEq(p.Cosmetics.Owned.ThornDice, true, "owned cosmetic kept")
	expect(p.Cosmetics.Owned.SproutCap == nil and p.Cosmetics.Owned.FireflyTrail == nil, "non-true flags dropped")
	expectEq(p.Cosmetics.Owned.Nope, nil, "unknown cosmetic dropped")

	for _, bad in { 0, -1, 1.5, NAN, INF, -INF, "3", true, {}, 2e9 } do
		local q = ProfileSchema.Migrate({
			Version = 4,
			Gems = bad,
			Xp = bad,
			Materials = { Fragment = bad },
			Items = { XpTome = bad },
		})
		expect(q.Gems == 0 and q.Xp == 0, "bad counter -> 0: " .. tostring(bad))
		expect(next(q.Materials) == nil and next(q.Items) == nil, "bad count dropped: " .. tostring(bad))
	end
	for _, bad in { "x", 5, true, { ThornDice = true }, { Owned = "x" } } do
		local q = ProfileSchema.Migrate({ Version = 4, Materials = bad, Items = bad, Cosmetics = bad })
		expect(next(q.Materials) == nil and next(q.Items) == nil, "non-table -> empty")
		expect(type(q.Cosmetics.Owned) == "table" and next(q.Cosmetics.Owned) == nil, "cosmetics -> empty")
	end
	local missing = ProfileSchema.Migrate({ Version = 4 })
	expect(missing.Gems == 0 and missing.Xp == 0, "a v4 save without Gems gets no second grant")
	local again = ProfileSchema.Migrate(ProfileSchema.DeepCopy(p))
	expect(again.Materials.Fragment == 3 and again.Items.XpTome == 2 and again.Cosmetics.Owned.ThornDice, "idempotent")
end)

test("a 10,000-entry junk Materials table loads fast and clean", function()
	local junk = { Fragment = 4 }
	for i = 1, 10_000 do
		junk["junk" .. i] = i
	end
	local started = os.clock()
	local p = ProfileSchema.Migrate({ Version = 4, Materials = junk, Items = junk })
	expect(os.clock() - started < 0.5, "bounded by the catalogue")
	local count = 0
	for id in p.Materials do
		count += 1
		expectEq(id, "Fragment", "only catalogue ids survive")
	end
	expectEq(count, 1, "one material")
	expect(next(p.Items) == nil, "no junk items")
end)

-- Deterministic dump (sorted keys) for deep-equality checks.
local function snap(value)
	if type(value) ~= "table" then
		return tostring(value)
	end
	local keys = {}
	for k in value do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, k in keys do
		table.insert(parts, type(k) .. ":" .. tostring(k) .. "=" .. snap(value[k]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

test("default profile starts every v5 progress field empty", function()
	local p = ProfileSchema.Default()
	expect(p.Stats.Kills == 0 and p.Stats.Wins == 0, "stats")
	expect(p.Weekly.Week == 0 and p.Weekly.Kills == 0 and p.Weekly.Runs == 0, "weekly counts")
	expect(next(p.Weekly.Claimed) == nil, "weekly claims")
	expect(p.Login.Streak == 0 and p.Login.LastDay == 0, "login")
	expect(next(p.Milestones) == nil and next(p.Achievements) == nil and next(p.Mastery) == nil, "flags and mastery")
end)

test("v4 -> v8 keeps every v4 value and drops stray values of the new fields; frozen input untouched", function()
	local f = table.freeze
	local stored = f({
		Version = 4,
		Gold = 70,
		Gems = 120,
		Xp = 345,
		BestWave = 6,
		RunsPlayed = 3,
		TrialCleared = true,
		LastRewardRunId = 99,
		profileRevision = 4,
		Dice = f({ C01 = f({ Level = 3, Copies = 2 }), R01 = f({ Level = 1, Copies = 0 }) }),
		Deck = f({ "R01", "C02", "C03", "C04", "C05" }),
		Claimed = f({ S1 = true }),
		Daily = f({ Day = 7, Kills = 3, Claimed = f({ D1 = true }) }),
		Redeemed = f({ welcome = true }),
		Materials = f({ Fragment = 9 }),
		Items = f({ XpTome = 2 }),
		Cosmetics = f({ Owned = f({ ThornDice = true }) }),
		sessionLease = f({ jobId = "A", expiresAt = 9 }),
		-- stray: v4 had none of these
		Stats = f({ Kills = 500, Wins = 3 }),
		Weekly = f({ Week = 9, Kills = 9, Runs = 9, Claimed = f({ W1 = true }) }),
		Login = f({ Streak = 3, LastDay = 7 }),
		Milestones = f({ P10 = true }),
		Achievements = f({ A1 = true }),
		Mastery = f({ C01 = f({ Xp = 50, Claimed = f({ ["5"] = true }) }) }),
	})
	local p = ProfileSchema.Migrate(stored)
	expect(p.Version == 13 and p.Gold == 70 and p.Gems == 120 and p.Xp == 345, "counters kept, no second Gem grant")
	expect(p.BestWave == 6 and p.RunsPlayed == 3 and p.TrialCleared and p.LastRewardRunId == 99, "stats kept")
	expect(p.Dice.C01.Copies == 2 and p.Dice.R01 ~= nil and p.Deck[1] == "R01", "dice and deck kept")
	expect(p.Claimed.S1 and p.Daily.Day == 7 and p.Daily.Claimed.D1 and p.Redeemed.welcome, "claims kept")
	expect(p.Materials.Fragment == 9 and p.Items.XpTome == 2 and p.Cosmetics.Owned.ThornDice, "inventory kept")
	expect(p.profileRevision == 4 and p.sessionLease.jobId == "A", "store metadata kept")
	expect(p.Stats.Kills == 0 and p.Stats.Wins == 0, "stray stats dropped")
	expect(p.Weekly.Week == 0 and p.Weekly.Runs == 0 and next(p.Weekly.Claimed) == nil, "stray weekly dropped")
	expect(p.Login.Streak == 0 and p.Login.LastDay == 0, "stray login dropped")
	expect(next(p.Milestones) == nil and next(p.Achievements) == nil, "stray flags dropped")
	expect(next(p.Mastery) == nil, "stray mastery dropped")
	expectEq(stored.Version, 4, "input untouched")
	expectEq(snap(ProfileSchema.Migrate(ProfileSchema.DeepCopy(p))), snap(p), "idempotent")
end)

test("v1 -> v8 chain ends with the v5, v6 and v8 defaults", function()
	local p = ProfileSchema.Migrate(table.freeze({
		Version = 1,
		Gold = 5,
		Login = table.freeze({ Streak = 4 }),
		Settings = table.freeze({ shadows = false }),
	}))
	expect(p.Version == 13 and p.Gold == 5 and p.Gems == 50, "v1 data kept, starter Gems once")
	expect(p.Login.Streak == 0 and p.Stats.Kills == 0 and next(p.Mastery) == nil, "v5 fields start empty")
	expect(next(p.Settings) == nil, "v6 Settings start empty")
	expect(p.RollPity.Standard == 0 and p.Stats.Rolls == 0, "v8 roll fields start empty")
end)

test("v5 fields keep only valid counts, known ids, true flags and milestone levels", function()
	local p = ProfileSchema.Migrate({
		Version = 5,
		Stats = { Kills = 1200, Wins = 2 },
		Weekly = {
			Week = 2900,
			Kills = 40,
			Runs = 3,
			Claimed = { W1 = true, W2 = "yes", S1 = true, D1 = true, Nope = true },
		},
		Login = { Streak = 4, LastDay = 20000 },
		Claimed = { S1 = true, W1 = true, D1 = true },
		Milestones = { P10 = true, P20 = 1, A1 = true, Nope = true },
		Achievements = { A1 = true, A2 = false, P10 = true, A9 = true },
		Mastery = {
			C01 = {
				Xp = 60,
				Claimed = { ["5"] = true, ["10"] = "true", ["7"] = true, [5] = true, ["05"] = true, ["20"] = true },
			},
			R01 = { Xp = 7, Claimed = {} },
			Z99 = { Xp = 5, Claimed = {} },
			C02 = "x",
			C03 = { Xp = -1, Claimed = "x" },
		},
	})
	expect(p.Stats.Kills == 1200 and p.Stats.Wins == 2, "stats kept")
	expect(p.Weekly.Week == 2900 and p.Weekly.Kills == 40 and p.Weekly.Runs == 3, "weekly counts kept")
	expectEq(snap(p.Weekly.Claimed), snap({ W1 = true }), "only true flags of weekly quests")
	expectEq(snap(p.Claimed), snap({ S1 = true }), "one-time claims: not daily, not weekly")
	expect(p.Login.Streak == 4 and p.Login.LastDay == 20000, "login kept")
	expectEq(snap(p.Milestones), snap({ P10 = true }), "milestone flags")
	expectEq(snap(p.Achievements), snap({ A1 = true }), "achievement flags")
	expectEq(p.Mastery.C01.Xp, 60, "mastery xp")
	expectEq(snap(p.Mastery.C01.Claimed), snap({ ["5"] = true, ["20"] = true }), "only milestone levels, as set keys")
	expect(p.Mastery.R01 ~= nil and p.Mastery.R01.Xp == 7, "any known die")
	expect(p.Mastery.Z99 == nil and p.Mastery.C02 == nil, "unknown die and non-table entry dropped")
	expect(p.Mastery.C03.Xp == 0 and next(p.Mastery.C03.Claimed) == nil, "bad xp and claims reset")
	local numeric = ProfileSchema.Migrate({ Version = 5, Mastery = { C01 = { Xp = 60, Claimed = { [10] = true } } } })
	expectEq(snap(numeric.Mastery.C01.Claimed), snap({ ["10"] = true }), "a numeric level key still reads as claimed")

	for _, bad in { -1, 1.5, NAN, INF, "3", true, {}, 2e9 } do
		local q = ProfileSchema.Migrate({
			Version = 5,
			Stats = { Kills = bad, Wins = bad },
			Weekly = { Week = bad, Kills = bad, Runs = bad },
			Login = { Streak = bad, LastDay = bad },
			Mastery = { C01 = { Xp = bad } },
		})
		expect(q.Stats.Kills == 0 and q.Stats.Wins == 0, "bad stats -> 0: " .. tostring(bad))
		expect(q.Weekly.Week == 0 and q.Weekly.Kills == 0 and q.Weekly.Runs == 0, "bad weekly -> 0")
		expect(q.Login.Streak == 0 and q.Login.LastDay == 0, "bad login -> 0")
		expectEq(q.Mastery.C01.Xp, 0, "bad mastery xp -> 0")
	end
	expectEq(ProfileSchema.Migrate({ Version = 5, Login = { Streak = 8 } }).Login.Streak, 0, "streak above 7")
	expectEq(ProfileSchema.Migrate({ Version = 5, Login = { Streak = 7 } }).Login.Streak, 7, "streak 7 kept")
	for _, bad in { "x", 5, true } do
		local q = ProfileSchema.Migrate({
			Version = 5,
			Stats = bad,
			Weekly = bad,
			Login = bad,
			Milestones = bad,
			Achievements = bad,
			Mastery = bad,
		})
		expect(q.Stats.Kills == 0 and q.Weekly.Week == 0 and q.Login.Streak == 0, "non-table -> default")
		expect(next(q.Milestones) == nil and next(q.Achievements) == nil and next(q.Mastery) == nil, "-> empty")
	end
	expectEq(snap(ProfileSchema.Migrate(ProfileSchema.DeepCopy(p))), snap(p), "idempotent")
end)

test("oversized junk Mastery, Milestones and Achievements tables load fast and clean", function()
	local junk = { P10 = true, A1 = true, C01 = { Xp = 5, Claimed = { ["5"] = true } } }
	for i = 1, 20_000 do
		junk["junk" .. i] = true
		junk[i] = { Xp = 1 }
	end
	local started = os.clock()
	local p = ProfileSchema.Migrate({ Version = 5, Milestones = junk, Achievements = junk, Mastery = junk })
	expect(os.clock() - started < 0.5, "bounded by the config")
	expectEq(snap(p.Milestones), snap({ P10 = true }), "milestones")
	expectEq(snap(p.Achievements), snap({ A1 = true }), "achievements")
	expectEq(snap(p.Mastery), snap({ C01 = { Xp = 5, Claimed = { ["5"] = true } } }), "mastery: C01 only")
end)

test("v5 -> v8 keeps every v5 value and drops a stray Settings; frozen input untouched", function()
	local f = table.freeze
	local fields = {
		Version = 5,
		Gold = 70,
		Gems = 120,
		Xp = 345,
		BestWave = 6,
		RunsPlayed = 3,
		TrialCleared = true,
		LastRewardRunId = 99,
		profileRevision = 4,
		Dice = f({
			C01 = f({ Level = 3, Copies = 2 }),
			C02 = f({ Level = 1, Copies = 0 }),
			C03 = f({ Level = 1, Copies = 0 }),
			C04 = f({ Level = 1, Copies = 0 }),
			C05 = f({ Level = 1, Copies = 0 }),
			R01 = f({ Level = 2, Copies = 1 }),
		}),
		Deck = f({ "R01", "C02", "C03", "C04", "C05" }),
		Claimed = f({ S1 = true }),
		Daily = f({ Day = 7, Kills = 3, Claimed = f({ D1 = true }) }),
		Redeemed = f({ welcome = true }),
		Materials = f({ Fragment = 9 }),
		Items = f({ XpTome = 2 }),
		Cosmetics = f({ Owned = f({ ThornDice = true }) }),
		Stats = f({ Kills = 500, Wins = 3 }),
		Weekly = f({ Week = 9, Kills = 9, Runs = 9, Claimed = f({ W1 = true }) }),
		Login = f({ Streak = 3, LastDay = 7 }),
		Milestones = f({ P10 = true }),
		Achievements = f({ A1 = true }),
		Mastery = f({ C01 = f({ Xp = 50, Claimed = f({ ["5"] = true }) }) }),
		sessionLease = f({ jobId = "A", expiresAt = 9 }),
		Settings = f({ shadows = false, uiScale = 80 }), -- stray: v5 had no settings
	}
	local stored = f(fields)
	local p = ProfileSchema.Migrate(stored)
	expectEq(p.Version, 13, "version")
	expect(next(p.Settings) == nil, "stray Settings dropped")
	for key, value in fields do
		if key == "Cosmetics" then
			expectEq(snap(p.Cosmetics.Owned), snap(value.Owned), "Cosmetics.Owned kept")
		elseif key == "Stats" then
			expectEq(snap(p.Stats), snap({ Kills = 500, Wins = 3, Rolls = 0 }), "Stats kept, Rolls starts at 0")
		elseif key ~= "Version" and key ~= "Settings" then
			expectEq(snap(p[key]), snap(value), key .. " kept")
		end
	end
	for key in ProfileSchema.Default() do
		expect(
			key == "Settings"
				or key == "Locked"
				or key == "RollPity"
				or key == "Purchases"
				or key == "Receipts"
				or fields[key] ~= nil,
			"the v5 sample covers " .. key
		)
	end
	expectEq(stored.Version, 5, "input untouched")
	expectEq(snap(ProfileSchema.Migrate(ProfileSchema.DeepCopy(p))), snap(p), "idempotent")
end)

test("v6 Settings keep only registry keys with cleaned values", function()
	local p = ProfileSchema.Migrate({
		Version = 6,
		Settings = {
			shadows = false,
			autoSkipWaves = true,
			effectsQuality = "Low",
			uiScale = 73, -- snaps to 75
			masterVolume = 500, -- clamps to 100
			musicVolume = -3, -- clamps to 0
			effectScale = NAN,
			sfxVolume = INF,
			ambienceVolume = "50",
			showFps = 1,
			language = "French",
			highContrast = { true },
			nope = true,
			[1] = true,
		},
	})
	expectEq(
		snap(p.Settings),
		snap({
			shadows = false,
			autoSkipWaves = true,
			effectsQuality = "Low",
			uiScale = 75,
			masterVolume = 100,
			musicVolume = 0,
		}),
		"cleaned"
	)
	for _, bad in { "x", 5, true } do
		expect(next(ProfileSchema.Migrate({ Version = 6, Settings = bad }).Settings) == nil, "non-table -> empty")
	end
	expectEq(snap(ProfileSchema.Migrate(ProfileSchema.DeepCopy(p))), snap(p), "idempotent")
end)

test("a 10,000-entry junk Settings table loads fast and clean", function()
	local junk = { shadows = false }
	for i = 1, 10_000 do
		junk["junk" .. i] = true
		junk[i] = 50
	end
	local started = os.clock()
	local p = ProfileSchema.Migrate({ Version = 6, Settings = junk })
	expect(os.clock() - started < 0.5, "bounded by the registry")
	expectEq(snap(p.Settings), snap({ shadows = false }), "only the registry key survives")
end)

test("v6 -> v8 keeps every v6 value and drops stray Locked and Equipped; frozen input untouched", function()
	local f = table.freeze
	local fields = {
		Version = 6,
		Gold = 70,
		Gems = 120,
		Xp = 345,
		BestWave = 6,
		RunsPlayed = 3,
		TrialCleared = true,
		LastRewardRunId = 99,
		profileRevision = 4,
		Dice = f({
			C01 = f({ Level = 3, Copies = 2 }),
			C02 = f({ Level = 1, Copies = 0 }),
			C03 = f({ Level = 1, Copies = 0 }),
			C04 = f({ Level = 1, Copies = 0 }),
			C05 = f({ Level = 1, Copies = 0 }),
			R01 = f({ Level = 2, Copies = 1 }),
		}),
		Deck = f({ "R01", "C02", "C03", "C04", "C05" }),
		Claimed = f({ S1 = true }),
		Daily = f({ Day = 7, Kills = 3, Claimed = f({ D1 = true }) }),
		Redeemed = f({ welcome = true }),
		Materials = f({ Fragment = 9 }),
		Items = f({ XpTome = 2 }),
		Cosmetics = f({ Owned = f({ ThornDice = true }), Equipped = f({ DiceSkin = "ThornDice" }) }), -- stray Equipped
		Stats = f({ Kills = 500, Wins = 3 }),
		Weekly = f({ Week = 9, Kills = 9, Runs = 9, Claimed = f({ W1 = true }) }),
		Login = f({ Streak = 3, LastDay = 7 }),
		Milestones = f({ P10 = true }),
		Achievements = f({ A1 = true }),
		Mastery = f({ C01 = f({ Xp = 50, Claimed = f({ ["5"] = true }) }) }),
		Settings = f({ shadows = false, uiScale = 75 }),
		sessionLease = f({ jobId = "A", expiresAt = 9 }),
		Locked = f({ Fragment = true }), -- stray: v6 had no locks
	}
	local stored = f(fields)
	local p = ProfileSchema.Migrate(stored)
	expectEq(p.Version, 13, "version")
	expect(next(p.Locked) == nil, "stray Locked dropped")
	expect(next(p.Cosmetics.Equipped) == nil, "stray Equipped dropped")
	expectEq(snap(p.Cosmetics.Owned), snap(fields.Cosmetics.Owned), "Cosmetics.Owned kept")
	for key, value in fields do
		if key == "Stats" then
			expectEq(snap(p.Stats), snap({ Kills = 500, Wins = 3, Rolls = 0 }), "Stats kept, Rolls starts at 0")
		elseif key ~= "Version" and key ~= "Locked" and key ~= "Cosmetics" then
			expectEq(snap(p[key]), snap(value), key .. " kept")
		end
	end
	for key in ProfileSchema.Default() do
		expect(
			key == "RollPity" or key == "Purchases" or key == "Receipts" or fields[key] ~= nil,
			"the v6 sample covers " .. key
		)
	end
	expectEq(stored.Version, 6, "input untouched")
	expectEq(snap(ProfileSchema.Migrate(ProfileSchema.DeepCopy(p))), snap(p), "idempotent")
end)

test("v7 Locked keeps only true flags for Material and Item ids", function()
	local p = ProfileSchema.Migrate({
		Version = 7,
		Locked = {
			Fragment = true,
			XpTome = true,
			GoldPouch = "true",
			ThornDice = true,
			C01 = true,
			Nope = true,
			[1] = true,
		},
	})
	expectEq(snap(p.Locked), snap({ Fragment = true, XpTome = true }), "catalogue Materials and Items only")
	for _, bad in { "x", 5, true } do
		expect(next(ProfileSchema.Migrate({ Version = 7, Locked = bad }).Locked) == nil, "non-table -> empty")
	end
	expectEq(snap(ProfileSchema.Migrate(ProfileSchema.DeepCopy(p))), snap(p), "idempotent")
end)

test("v7 Cosmetics.Equipped keeps an owned id in its own slot only", function()
	local p = ProfileSchema.Migrate({
		Version = 7,
		Cosmetics = {
			Owned = { ThornDice = true, SproutCap = true },
			Equipped = {
				DiceSkin = "ThornDice", -- owned, right slot: kept
				Hat = "ThornDice", -- wrong slot
				Effect = "FireflyTrail", -- not owned
				Nope = "SproutCap", -- unknown slot
				[1] = "SproutCap",
			},
		},
	})
	expectEq(snap(p.Cosmetics.Equipped), snap({ DiceSkin = "ThornDice" }), "sanitised")
	for _, bad in { "x", 5, true } do
		local q = ProfileSchema.Migrate({ Version = 7, Cosmetics = { Owned = { ThornDice = true }, Equipped = bad } })
		expect(next(q.Cosmetics.Equipped) == nil and q.Cosmetics.Owned.ThornDice, "non-table Equipped -> empty")
	end
	local junk = { DiceSkin = "ThornDice" }
	for i = 1, 10_000 do
		junk["junk" .. i] = "ThornDice"
	end
	local started = os.clock()
	local q = ProfileSchema.Migrate({
		Version = 7,
		Cosmetics = { Owned = { ThornDice = true }, Equipped = junk },
		Locked = junk,
	})
	expect(os.clock() - started < 0.5, "bounded by the config")
	expectEq(snap(q.Cosmetics.Equipped), snap({ DiceSkin = "ThornDice" }), "junk dropped")
	expectEq(snap(ProfileSchema.Migrate(ProfileSchema.DeepCopy(p))), snap(p), "idempotent")
end)

test("v7 -> v8 keeps every v7 value, starts RollPity and Stats.Rolls empty; frozen input untouched", function()
	local f = table.freeze
	local fields = {
		Version = 7,
		Gold = 70,
		Gems = 120,
		Xp = 345,
		BestWave = 6,
		RunsPlayed = 3,
		TrialCleared = true,
		LastRewardRunId = 99,
		profileRevision = 4,
		Dice = f({
			C01 = f({ Level = 3, Copies = 2 }),
			C02 = f({ Level = 1, Copies = 0 }),
			C03 = f({ Level = 1, Copies = 0 }),
			C04 = f({ Level = 1, Copies = 0 }),
			C05 = f({ Level = 1, Copies = 0 }),
			R01 = f({ Level = 2, Copies = 1 }),
		}),
		Deck = f({ "R01", "C02", "C03", "C04", "C05" }),
		Claimed = f({ S1 = true }),
		Daily = f({ Day = 7, Kills = 3, Claimed = f({ D1 = true }) }),
		Redeemed = f({ welcome = true }),
		Materials = f({ Fragment = 9 }),
		Items = f({ XpTome = 2 }),
		Cosmetics = f({ Owned = f({ ThornDice = true }), Equipped = f({ DiceSkin = "ThornDice" }) }),
		Stats = f({ Kills = 500, Wins = 3, Rolls = 40 }), -- stray Rolls: v7 had no rolls
		Weekly = f({ Week = 9, Kills = 9, Runs = 9, Claimed = f({ W1 = true }) }),
		Login = f({ Streak = 3, LastDay = 7 }),
		Milestones = f({ P10 = true }),
		Achievements = f({ A1 = true }),
		Mastery = f({ C01 = f({ Xp = 50, Claimed = f({ ["5"] = true }) }) }),
		Settings = f({ shadows = false, uiScale = 75 }),
		Locked = f({ Fragment = true }),
		sessionLease = f({ jobId = "A", expiresAt = 9 }),
		RollPity = f({ Standard = 50 }), -- stray: v7 had no pity
	}
	local stored = f(fields)
	local p = ProfileSchema.Migrate(stored)
	expectEq(p.Version, 13, "version")
	expectEq(snap(p.RollPity), snap({ Standard = 0 }), "stray RollPity dropped")
	expectEq(snap(p.Stats), snap({ Kills = 500, Wins = 3, Rolls = 0 }), "stray Stats.Rolls dropped, the rest kept")
	for key, value in fields do
		if key ~= "Version" and key ~= "RollPity" and key ~= "Stats" then
			expectEq(snap(p[key]), snap(value), key .. " kept")
		end
	end
	for key in ProfileSchema.Default() do
		expect(key == "Purchases" or key == "Receipts" or fields[key] ~= nil, "the v7 sample covers " .. key)
	end
	expectEq(stored.Version, 7, "input untouched")
	expectEq(snap(ProfileSchema.Migrate(ProfileSchema.DeepCopy(p))), snap(p), "idempotent")
	local bare = ProfileSchema.Migrate({ Version = 7, Stats = "x" })
	expect(bare.Stats.Rolls == 0 and bare.RollPity.Standard == 0, "a v7 without Stats gets the defaults")
end)

test("v8 RollPity keeps an integer in 0..Max-1 per Config/Roll pool; Stats.Rolls is a count", function()
	local p = ProfileSchema.Migrate({
		Version = 8,
		RollPity = { Standard = 79, Event = 5, [1] = 3 },
		Stats = { Rolls = 1234 },
	})
	expectEq(snap(p.RollPity), snap({ Standard = 79 }), "79 kept, unknown pools dropped")
	expectEq(p.Stats.Rolls, 1234, "rolls kept")
	for _, bad in { 80, 81, -1, 1.5, 0 / 0, math.huge, "5", true, {} } do
		local q = ProfileSchema.Migrate({ Version = 8, RollPity = { Standard = bad } })
		expectEq(q.RollPity.Standard, 0, "pity " .. tostring(bad) .. " -> 0")
	end
	for _, bad in { -1, 1.5, 0 / 0, math.huge, "5", true, {} } do
		expectEq(
			ProfileSchema.Migrate({ Version = 8, Stats = { Rolls = bad } }).Stats.Rolls,
			0,
			"rolls " .. tostring(bad)
		)
	end
	for _, bad in { "x", 5, true } do
		expectEq(ProfileSchema.Migrate({ Version = 8, RollPity = bad }).RollPity.Standard, 0, "non-table -> 0")
	end
	expectEq(ProfileSchema.Migrate({ Version = 8, Stats = { Rolls = 2e9 } }).Stats.Rolls, 0, "above 1e9 -> 0")
	local junk = { Standard = 7 }
	for i = 1, 10_000 do
		junk["junk" .. i] = 1
		junk[i] = 1
	end
	local started = os.clock()
	local q = ProfileSchema.Migrate({ Version = 8, RollPity = junk })
	expect(os.clock() - started < 0.5, "bounded by Config/Roll")
	expectEq(snap(q.RollPity), snap({ Standard = 7 }), "junk dropped")
	expectEq(snap(ProfileSchema.Migrate(ProfileSchema.DeepCopy(p))), snap(p), "idempotent")
end)

test("v8 -> v9 keeps every v8 value, starts Purchases and Receipts empty; frozen input untouched", function()
	local v8 = ProfileSchema.DeepCopy(ProfileSchema.Default())
	v8.Version = 8
	v8.Purchases, v8.Receipts = nil, nil
	v8.Gold, v8.Gems = 123, 456
	v8.Stats.Rolls = 7
	v8.RollPity.Standard = 5
	local stray = ProfileSchema.DeepCopy(v8)
	stray.Purchases, stray.Receipts = { Starter = 1 }, { "forged" } -- v8 had none
	local function freeze(t)
		for _, v in t do
			if type(v) == "table" then
				freeze(v)
			end
		end
		return table.freeze(t)
	end
	for _, stored in { v8, stray } do
		freeze(stored)
		local p = ProfileSchema.Migrate(stored)
		expectEq(p.Version, 13, "version")
		expect(next(p.Purchases) == nil and #p.Receipts == 0, "starts empty")
		expect(p.Gold == 123 and p.Gems == 456 and p.Stats.Rolls == 7 and p.RollPity.Standard == 5, "v8 fields kept")
		expectEq(snap(ProfileSchema.Migrate(ProfileSchema.DeepCopy(p))), snap(p), "idempotent")
	end
	expectEq(v8.Version, 8, "input untouched")
end)

test(
	"v9 Purchases keep 1..Limit for limited Config/Shop offers only; Receipts are deduped, 1..64 bytes, newest 100",
	function()
		local p =
			ProfileSchema.Migrate({ Version = 9, Purchases = { Starter = 1, Gems400 = 1, Nope = 1, XpTome1 = 1 } })
		expectEq(snap(p.Purchases), snap({ Starter = 1 }), "only the limited offer")
		for _, bad in { 0, 2, -1, 1.5, "1", true, NAN, INF, {} } do
			expect(
				next(ProfileSchema.Migrate({ Version = 9, Purchases = { Starter = bad } }).Purchases) == nil,
				"bad " .. tostring(bad)
			)
		end
		expect(next(ProfileSchema.Migrate({ Version = 9, Purchases = "x" }).Purchases) == nil, "non-table")
		local ring = { "a", "b", "a", "", ("x"):rep(65), 5, "c", ("y"):rep(64) }
		local r = ProfileSchema.Migrate({ Version = 9, Receipts = ring }).Receipts
		expectEq(
			table.concat(r, ","),
			"b,a,c," .. ("y"):rep(64),
			"valid ids, the newest of a duplicate kept, order kept"
		)
		expect(#ProfileSchema.Migrate({ Version = 9, Receipts = "x" }).Receipts == 0, "non-table")
		local many = {}
		for i = 1, 5000 do
			many[i] = "id" .. i
		end
		local kept = ProfileSchema.Migrate({ Version = 9, Receipts = many }).Receipts
		expect(#kept == 100 and kept[1] == "id4901" and kept[100] == "id5000", "newest 100")
	end
)

test("newer version is NewerVersion and never repaired", function()
	local p, problem = ProfileSchema.Migrate({ Version = ProfileSchema.VERSION + 1 })
	expect(p == nil and problem == "NewerVersion", "newer version refused")
end)

test("v9 -> v10 clamps die levels above the cap, no refund; corrupt v10 levels reset", function()
	local max = require(Server.Config.Progression).DieLevel.Max
	local stored = {
		Version = 9,
		Dice = {
			C01 = { Level = 10, Copies = 5 },
			C02 = { Level = max + 1, Copies = 6 },
			C03 = { Level = max, Copies = 7 },
			C04 = { Level = 11, Copies = 8 },
		},
	}
	local before = snap(stored)
	local p = ProfileSchema.Migrate(stored)
	expectEq(p.Dice.C01.Level, max, "10 -> cap")
	expectEq(p.Dice.C02.Level, max, "cap + 1 -> cap")
	expectEq(p.Dice.C03.Level, max, "cap kept")
	expectEq(p.Dice.C04.Level, 1, "11 was already corrupt -> 1")
	expect(p.Dice.C01.Copies == 5 and p.Dice.C02.Copies == 6 and p.Dice.C03.Copies == 7, "Copies unchanged")
	expect(p.Dice.C04.Copies == 8, "Copies of a corrupt level kept")
	expectEq(snap(stored), before, "stored is not mutated")
	expectEq(snap(ProfileSchema.Migrate(stored)), snap(p), "migrating the same v9 input again gives the same result")
	local once = snap(p)
	expectEq(snap(ProfileSchema.Migrate(p)), once, "re-migrating the v10 result changes nothing")
	expectEq(snap(p), once, "the v10 result is not mutated by a re-migration")

	local v10 = ProfileSchema.Migrate({ Version = 10, Dice = { C01 = { Level = max + 1, Copies = 4 } } })
	expect(v10.Dice.C01.Level == 1 and v10.Dice.C01.Copies == 4, "v10 level over the cap is corrupt -> 1")
end)

test("v9 -> v10 with a huge junk Dice table is cheap", function()
	local junk = { C01 = { Level = 9, Copies = 1 } }
	for i = 1, 20_000 do
		junk["junk" .. i] = { Level = 9, Copies = i }
	end
	local started = os.clock()
	local p = ProfileSchema.Migrate({ Version = 9, Dice = junk })
	expect(os.clock() - started < 0.5, "20,000 junk entries load in under 0.5 s")
	expect(p.Dice.C01.Level == require(Server.Config.Progression).DieLevel.Max and p.Dice.junk1 == nil, "junk dropped")
end)

local function v10(extra)
	local stored = {
		Version = 10,
		Gold = 77,
		Gems = 123,
		BestWave = 9,
		Dice = {},
		Deck = { "C01", "C02", "C03", "C04", "C05" },
		Mastery = {},
	}
	for k, v in extra do
		stored[k] = v
	end
	return stored
end

test("v10 -> v13: a retired die moves to a target that is not owned, keeping Level and Copies", function()
	local stored = v10({
		Dice = { E02 = { Level = 4, Copies = 6 }, E04 = { Level = 2, Copies = 1 }, L03 = { Level = 7, Copies = 3 } },
	})
	local before = snap(stored)
	local p = ProfileSchema.Migrate(stored)
	expect(p.Dice.E01.Level == 4 and p.Dice.E01.Copies == 6, "E02 -> E01")
	expect(p.Dice.E03.Level == 2 and p.Dice.E03.Copies == 1, "E04 -> E03")
	expect(p.Dice.L01.Level == 7 and p.Dice.L01.Copies == 3, "L03 -> L01")
	expect(p.Dice.E02 == nil and p.Dice.E04 == nil and p.Dice.L03 == nil, "retired ids gone")
	expectEq(snap(stored), before, "input untouched")
end)

test("v11: a save that still holds a retired id is converted, not dropped", function()
	local stored = v10({ Dice = { E02 = { Level = 3, Copies = 2 } }, Deck = { "C01", "C02", "C03", "C04", "E02" } })
	stored.Version = 11
	local before = snap(stored)
	local p = ProfileSchema.Migrate(stored)
	expect(p.Dice.E01.Level == 3 and p.Dice.E01.Copies == 2 and p.Dice.E02 == nil, "E02 restored and forwarded to E01")
	expectEq(p.Deck[5], "E01", "deck slot rewritten")
	expectEq(snap(stored), before, "input untouched")
end)

test("v10 -> v13: an owned target takes the higher Level and sums Copies + 1", function()
	local p =
		ProfileSchema.Migrate(v10({ Dice = { E02 = { Level = 4, Copies = 6 }, E08 = { Level = 6, Copies = 2 } } }))
	expect(p.Dice.E01.Level == 6 and p.Dice.E01.Copies == 9, "max level, 6 + 2 + 1 copies")
	local q =
		ProfileSchema.Migrate(v10({ Dice = { E02 = { Level = 7, Copies = 0 }, E08 = { Level = 3, Copies = 0 } } }))
	expect(q.Dice.E01.Level == 7 and q.Dice.E01.Copies == 1, "old die counts as one copy")
end)

test("v10 -> v13: merged Copies and Xp cap at 1e9", function()
	local p = ProfileSchema.Migrate(v10({
		Dice = { L03 = { Level = 1, Copies = 900_000_000 }, L06 = { Level = 1, Copies = 900_000_000 } },
		Mastery = { L03 = { Xp = 900_000_000, Claimed = {} }, L06 = { Xp = 900_000_000, Claimed = {} } },
	}))
	expectEq(p.Dice.L01.Copies, 1_000_000_000, "Copies capped")
	expectEq(p.Mastery.L01.Xp, 1_000_000_000, "Xp capped")
end)

test("v10 -> v13: Mastery moves, summing Xp and uniting Claimed", function()
	local p = ProfileSchema.Migrate(v10({
		Mastery = {
			E04 = { Xp = 50, Claimed = { ["5"] = true } },
			L03 = { Xp = 30, Claimed = { ["5"] = true } },
			L06 = { Xp = 20, Claimed = { ["10"] = true } },
		},
	}))
	expect(p.Mastery.E03.Xp == 50 and p.Mastery.E03.Claimed["5"] == true, "moved to an empty target")
	expect(p.Mastery.L01.Xp == 50 and p.Mastery.L01.Claimed["5"] and p.Mastery.L01.Claimed["10"], "merged")
	expect(p.Mastery.E04 == nil and p.Mastery.L03 == nil, "retired mastery gone")
end)

test("v10 -> v13: Deck slots are rewritten; a duplicate uses a starter in the retired slot", function()
	local d = ProfileSchema.Migrate(v10({
		Dice = { E02 = { Level = 1, Copies = 0 }, R01 = { Level = 1, Copies = 0 }, L03 = { Level = 1, Copies = 0 } },
		Deck = { "E02", "R01", "L03", "C01", "C02" },
	}))
	expect(table.concat(d.Deck, ",") == "E01,R01,L01,C01,C02", "slots rewritten")
	local dup = ProfileSchema.Migrate(v10({
		Dice = { E02 = { Level = 1, Copies = 0 }, E08 = { Level = 1, Copies = 0 } },
		Deck = { "E02", "E08", "C01", "C02", "C03" },
	}))
	expect(table.concat(dup.Deck, ",") == "C04,E01,C01,C02,C03", "duplicate fills only the retired slot")
end)

test("v10 -> v13: every other field is unchanged and v13 is idempotent", function()
	local stored = v10({ Dice = { R01 = { Level = 3, Copies = 2 } } })
	local p = ProfileSchema.Migrate(stored)
	expect(p.Version == 13 and p.Gold == 77 and p.Gems == 123 and p.BestWave == 9, "fields kept")
	expect(p.Dice.R01.Level == 3 and p.Dice.R01.Copies == 2, "other dice kept")
	expectEq(snap(ProfileSchema.Migrate(p)), snap(p), "re-migration changes nothing")
end)

test("v11 saves transfer every retired die to a supported roster slot", function()
	local stored = v10({
		Version = 11,
		Dice = {
			R06 = { Level = 4, Copies = 2 },
			R07 = { Level = 5, Copies = 1 },
			E06 = { Level = 2, Copies = 3 },
			E07 = { Level = 3, Copies = 5 },
			E08 = { Level = 6, Copies = 8 },
			E09 = { Level = 5, Copies = 1 },
			E10 = { Level = 2, Copies = 4 },
			L04 = { Level = 1, Copies = 1 },
			L05 = { Level = 2, Copies = 2 },
			L06 = { Level = 7, Copies = 6 },
			R02 = { Level = 1, Copies = 1 },
		},
		Deck = { "C01", "R06", "R02", "E09", "L06" },
		Mastery = { E06 = { Xp = 100, Claimed = { ["5"] = true } }, E09 = { Xp = 80, Claimed = { ["10"] = true } } },
	})
	local before = snap(stored)
	local p = ProfileSchema.Migrate(stored)
	expectEq(p.Version, 13, "upgraded")
	expectEq(table.concat(p.Deck, ","), "C01,C02,R02,E02,L01", "unaffected slots kept")
	expectEq(p.Dice.R02.Level, 4, "level survives conversion")
	expectEq(p.Dice.R02.Copies, 4, "owned target receives the base die and its copies")
	expectEq(p.Dice.R03.Copies, 1, "Wind and Rock map to separate Rare dice")
	expectEq(p.Dice.E01.Copies, 8, "Lightning transfers")
	expectEq(p.Dice.E02.Copies, 5, "Ice and Water merge")
	expectEq(p.Dice.E03.Copies, 10, "Leaf and Shadow merge")
	expectEq(p.Dice.L02.Copies, 4, "Sun and Fire merge")
	expectEq(p.Dice.L01.Level, 7, "Light transfers")
	expectEq(p.Mastery.E02.Xp, 180, "mastery combines")
	expect(p.Mastery.E02.Claimed["5"] and p.Mastery.E02.Claimed["10"], "claimed rewards stay claimed")
	for id in p.Dice do
		expect(Dice.Types[id] ~= nil, "only current dice")
	end
	expectEq(snap(stored), before, "input untouched")
	expectEq(snap(ProfileSchema.Migrate(p)), snap(p), "conversion is idempotent")
end)

test("v12 renames Mirror and Gravity without mixing their progression", function()
	local stored = v10({
		Version = 12,
		Dice = {
			E02 = { Level = 2, Copies = 3 }, -- Reactor in a restored legacy save
			E03 = { Level = 4, Copies = 9 },
			E05 = { Level = 7, Copies = 1 },
		},
		Deck = { "C01", "E03", "C02", "E05", "E02" },
		Mastery = {
			E03 = { Xp = 50, Claimed = { ["5"] = true } },
			E05 = { Xp = 180, Claimed = { ["10"] = true } },
		},
	})
	local before = snap(stored)
	local profile = ProfileSchema.Migrate(stored)
	expectEq(table.concat(profile.Deck, ","), "C01,E02,C02,E03,E01", "deck slots follow the renamed dice")
	expectEq(profile.Dice.E01.Copies, 3, "legacy Reactor keeps its old replacement")
	expectEq(profile.Dice.E02.Level, 4, "Mirror level")
	expectEq(profile.Dice.E02.Copies, 9, "Mirror copies")
	expectEq(profile.Dice.E03.Level, 7, "Gravity level")
	expectEq(profile.Dice.E03.Copies, 1, "Gravity copies")
	expect(profile.Mastery.E02.Xp == 50 and profile.Mastery.E02.Claimed["5"], "Mirror mastery")
	expect(profile.Mastery.E03.Xp == 180 and profile.Mastery.E03.Claimed["10"], "Gravity mastery")
	expect(profile.Dice.E05 == nil and profile.Mastery.E05 == nil, "former Gravity ID removed")
	expectEq(snap(stored), before, "input untouched")
	expectEq(snap(ProfileSchema.Migrate(profile)), snap(profile), "current IDs are not renamed again")
end)
