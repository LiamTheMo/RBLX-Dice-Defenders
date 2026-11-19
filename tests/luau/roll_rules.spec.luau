-- Config/Roll + Rules/Roll: the Standard pool's prices and weights, a seeded distribution, pity, ROLL 10 = ten single
-- draws, and Buy's checks (UnknownPool, UnknownPrice, Restricted, Insufficient, Overflow leave the profile deep-equal).

local Server = game:GetService("ServerScriptService").Server
local Roll = require(Server.Rules.Roll)
local RollConfig = require(Server.Config.Roll)
local Dice = require(Server.Config.Dice)
local Economy = require(Server.Rules.Economy)
local ProfileSchema = require(Server.Rules.ProfileSchema)

local STANDARD = RollConfig.ById.Standard

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

-- An rng whose rarity roll (1..10000) is always `bp` and whose die pick is always the first die of the rarity.
local function fixed(bp)
	return {
		NextInteger = function(_, lo, hi)
			return if hi == Roll.TOTAL_BP then bp else lo
		end,
	}
end

local function profile(gems)
	local p = ProfileSchema.Default()
	p.Gems = gems
	return p
end

-- Expects (false, code) and an untouched profile.
local function refused(p, poolId, count, allowed, code, label)
	local before = snap(p)
	local ok, got, result = Roll.Buy(p, poolId, count, allowed, Random.new(1))
	expect(not ok and got == code and result == nil, ("%s: %s (got %s)"):format(label, code, tostring(got)))
	expectEq(snap(p), before, label .. " leaves the profile deep-equal")
end

test(
	"Standard: 1 roll 100 Gems, 10 rolls 900; weights sum 10000, Mythic and Secret have positive odds; pity 80; Featured",
	function()
		expectEq(#RollConfig.Pools, 1, "one pool")
		expect(STANDARD ~= nil and RollConfig.Pools[1] == STANDARD and STANDARD.Id == "Standard", "Standard by id")
		local prices = {}
		for _, p in STANDARD.Prices do
			prices[p.Count] = p.Gems
		end
		expect(prices[1] == 100 and prices[10] == 900 and #STANDARD.Prices == 2, "prices")
		local sum, bp = 0, {}
		for _, o in STANDARD.Odds do
			sum += o.Bp
			bp[o.Rarity] = o.Bp
		end
		expectEq(sum, 10000, "weights sum")
		expectEq(Roll.TOTAL_BP, 10000, "TOTAL_BP")
		for rarity, want in { Common = 3989, Rare = 4500, Epic = 1400, Legendary = 100, Mythic = 10, Secret = 1 } do
			expectEq(bp[rarity], want, rarity .. " weight")
		end
		expect(STANDARD.Pity.Rarity == "Legendary" and STANDARD.Pity.Max == 80, "pity: Legendary on the 80th roll")
		expectEq(snap(STANDARD.Featured), snap({ "L01", "M01", "L02" }), "Astral is the center feature")
		-- the pool's dice are exactly the Config/Dice entries of a weighted rarity, each listed under its own rarity
		local n = 0
		for id, t in Dice.Types do
			if STANDARD.ByRarity[t.rarity] then
				n += 1
				expect(table.find(STANDARD.ByRarity[t.rarity], id) ~= nil, id .. " drawable under " .. t.rarity)
			end
		end
		expectEq(#STANDARD.Dice, n, "every die once")
		for i, d in STANDARD.Dice do
			expectEq(d.Rarity, Dice.Types[d.Id].rarity, d.Id .. " rarity")
			expect(i == 1 or STANDARD.Dice[i - 1].Id < d.Id, "sorted by Id")
		end
		expect(
			STANDARD.ByRarity.Mythic[1] == "M01" and STANDARD.ByRarity.Secret[1] == "S01",
			"Astral and Dragon are drawable"
		)
		for _, id in STANDARD.Featured do
			expect(
				Dice.Types[id] ~= nil and table.find(STANDARD.ByRarity[Dice.Types[id].rarity], id) ~= nil,
				id .. " is grantable"
			)
		end
		expect(table.isfrozen(STANDARD) and table.isfrozen(STANDARD.Odds), "frozen")
	end
)

test("a seeded 100,000-draw run follows the base distribution and awards valid dice", function()
	local rng, n = Random.new(20261115), 100000
	local byRarity, byId, bad = {}, {}, 0
	for _ = 1, n do
		local results, pity = Roll.Draw(0, STANDARD, 1, rng) -- base odds: the counter never reaches the guarantee
		local r = results[1]
		local t = Dice.Types[r.Id]
		if t == nil or t.rarity ~= r.Rarity or (pity ~= 0 and pity ~= 1) then
			bad += 1
		end
		byRarity[r.Rarity] = (byRarity[r.Rarity] or 0) + 1
		byId[r.Id] = (byId[r.Id] or 0) + 1
	end
	expectEq(bad, 0, "known ids of their own rarity")
	local shown = {}
	for rarity, want in { Common = 39.89, Rare = 45, Epic = 14, Legendary = 1 } do
		local pct = 100 * (byRarity[rarity] or 0) / n
		table.insert(shown, ("%s %.2f%%"):format(rarity, pct))
		expectNear(pct, want, 1, rarity .. " share")
	end
	table.sort(shown)
	print("    base distribution (100,000 draws): " .. table.concat(shown, ", "))
	expectNear(100 * (byRarity.Mythic or 0) / n, 0.1, 0.06, "Mythic share")
	expectNear(100 * (byRarity.Secret or 0) / n, 0.01, 0.009, "Secret share")
	for rarity, list in STANDARD.ByRarity do -- uniform within a rarity
		local each = (byRarity[rarity] or 0) / #list
		for _, id in list do
			expectNear(byId[id] or 0, each, each * 0.25, id .. " share of " .. rarity)
		end
	end
end)

test("with pity carried between draws no streak passes 80 rolls without a Legendary", function()
	local rng, n = Random.new(7), 100000
	local pity, streak, longest, legendary = 0, 0, 0, 0
	for _ = 1, n do
		local results
		results, pity = Roll.Draw(pity, STANDARD, 1, rng)
		if results[1].Rarity == "Legendary" then
			legendary += 1
			streak = 0
		else
			streak += 1
			longest = math.max(longest, streak)
		end
		expect(pity == streak, "the counter is the rolls since the last Legendary")
	end
	expect(longest <= 79, "longest streak without a Legendary " .. longest)
	local pct = 100 * legendary / n
	print(("    with pity (100,000 draws): Legendary %.2f%%, longest dry streak %d"):format(pct, longest))
	expect(pct >= 1 and pct <= 2, "effective Legendary rate " .. pct)
end)

test("pity: with no Legendary in 79 rolls the 80th is Legendary; any Legendary resets the counter", function()
	local results, pity = Roll.Draw(0, STANDARD, 80, fixed(1)) -- every roll a Common
	for i = 1, 79 do
		expectEq(results[i].Rarity, "Common", "roll " .. i)
	end
	expectEq(results[80].Rarity, "Legendary", "the 80th")
	expect(table.find(STANDARD.ByRarity.Legendary, results[80].Id) ~= nil, "a Legendary id")
	expectEq(pity, 0, "the guaranteed Legendary resets the counter")
	local _, p79 = Roll.Draw(0, STANDARD, 79, fixed(1))
	expectEq(p79, 79, "79 without one")
	local forced, after = Roll.Draw(79, STANDARD, 1, fixed(1))
	expect(forced[1].Rarity == "Legendary" and after == 0, "stored 79: the next roll is the guarantee")
	local _, p81 = Roll.Draw(0, STANDARD, 81, fixed(1))
	expectEq(p81, 1, "the counter climbs again after the guarantee")
	local natural, reset = Roll.Draw(40, STANDARD, 1, fixed(9950)) -- 9890..9989 is the Legendary band
	expect(natural[1].Rarity == "Legendary" and reset == 0, "a natural Legendary resets the counter")
	local epic, climbed = Roll.Draw(40, STANDARD, 1, fixed(9900))
	expect(epic[1].Rarity == "Epic" and climbed == 41, "an Epic does not")
	local bands = {
		[1] = "Common",
		[3989] = "Common",
		[3990] = "Rare",
		[8489] = "Rare",
		[8490] = "Epic",
		[9889] = "Epic",
		[9890] = "Legendary",
		[9989] = "Legendary",
		[9990] = "Mythic",
		[9999] = "Mythic",
		[10000] = "Secret",
	}
	for bp, want in bands do
		expectEq(Roll.Draw(0, STANDARD, 1, fixed(bp))[1].Rarity, want, "band at " .. bp)
	end
	expectEq(Roll.Draw(0, STANDARD, 1, fixed(10000))[1].Id, "S01", "last ticket grants Dragon")
end)

test("ROLL 10 with seed S equals ten single draws with seed S", function()
	for _, seed in { 1, 42, 99991 } do
		for _, start in { 0, 75 } do
			local ten, tenPity = Roll.Draw(start, STANDARD, 10, Random.new(seed))
			local rng, pity, singles = Random.new(seed), start, {}
			for i = 1, 10 do
				local one
				one, pity = Roll.Draw(pity, STANDARD, 1, rng)
				singles[i] = one[1]
			end
			expectEq(snap(ten), snap(singles), ("seed %d from %d: results"):format(seed, start))
			expectEq(tenPity, pity, ("seed %d from %d: pity"):format(seed, start))
		end
	end
end)

test("Buy: one roll costs exactly 100 Gems, ten cost 900; Stats.Rolls and RollPity follow; RollResult shape", function()
	local p = profile(1000)
	local ok, code, result = Roll.Buy(p, "Standard", 1, true, Random.new(3))
	expect(ok and code == nil, "ok " .. tostring(code))
	expectEq(p.Gems, 900, "100 Gems once")
	expectEq(p.Stats.Rolls, 1, "one roll counted")
	expect(result.Pool == "Standard" and #result.Results == 1 and result.Pity == p.RollPity.Standard, "payload")
	local r = result.Results[1]
	expect(type(r.Id) == "string" and r.Rarity == Dice.Types[r.Id].rarity and type(r.New) == "boolean", "row")
	local ok10, _, ten = Roll.Buy(p, "Standard", 10, true, Random.new(4))
	expect(ok10 and #ten.Results == 10, "ten results")
	expectEq(p.Gems, 0, "900 Gems once")
	expectEq(p.Stats.Rolls, 11, "eleven rolls counted")
	local copies = 0
	for _, die in p.Dice do
		copies += 1 + die.Copies
	end
	expectEq(copies, 5 + 11, "every roll is one die: starters + 11")
	refused(p, "Standard", 1, true, "Insufficient", "now broke")
end)

test("Buy rejections in order leave Gems, dice, pity and stats deep-equal", function()
	local rich = profile(5000)
	rich.RollPity.Standard = 33
	for _, id in { "Event", "standard", "", "Standard ", "__index" } do
		refused(rich, id, 1, true, "UnknownPool", "pool " .. id)
	end
	for _, count in { 5, 2, 9, 0, 11 } do
		refused(rich, "Standard", count, true, "UnknownPrice", "count " .. count)
	end
	for _, allowed in { false, "true", 1 } do
		refused(rich, "Standard", 1, allowed, "Restricted", "allowed " .. tostring(allowed))
	end
	refused(rich, "Standard", 10, nil, "Restricted", "unknown policy (nil) fails closed")
	refused(profile(99), "Standard", 1, true, "Insufficient", "99 Gems for one")
	refused(profile(899), "Standard", 10, true, "Insufficient", "899 Gems for ten")
	refused(profile(0), "Nope", 5, false, "UnknownPool", "pool checked first")
	refused(profile(0), "Standard", 5, false, "UnknownPrice", "then the price")
	refused(profile(0), "Standard", 1, false, "Restricted", "then the policy")
end)

test("Buy: duplicates become copies; a new die arrives at Level 1 and only its first copy is New", function()
	local p = profile(2000)
	local ok, _, owned = Roll.Buy(p, "Standard", 10, true, fixed(1)) -- ten C01 (a starter)
	expect(ok, "ok")
	expect(p.Dice.C01.Level == 1 and p.Dice.C01.Copies == 10, "ten copies of an owned die")
	for i, r in owned.Results do
		expect(r.Id == "C01" and r.New == false, "owned die is not new " .. i)
	end
	local _, _, fresh = Roll.Buy(p, "Standard", 10, true, fixed(4001)) -- ten R01 (not owned)
	expect(p.Dice.R01 ~= nil and p.Dice.R01.Level == 1 and p.Dice.R01.Copies == 9, "unlocked at Level 1 + 9 copies")
	expectEq(fresh.Results[1].New, true, "first R01 is new")
	for i = 2, 10 do
		expectEq(fresh.Results[i].New, false, "R01 " .. i .. " already unlocked by this roll")
	end
	expectEq(p.Gems, 200, "1800 spent")
end)

test("Buy: Overflow leaves the profile deep-equal; the 80th roll pays a Legendary and resets RollPity", function()
	local p = profile(1000)
	p.Dice.C01.Copies = Economy.MAX
	p.RollPity.Standard = 12
	local before = snap(p)
	local ok, code = Roll.Buy(p, "Standard", 1, true, fixed(1)) -- a C01 copy past the cap
	expect(not ok and code == "Overflow", "Overflow " .. tostring(code))
	expectEq(snap(p), before, "Gems, dice, pity and Stats.Rolls untouched")

	local q = profile(1000)
	q.RollPity.Standard = 79
	local okQ, _, result = Roll.Buy(q, "Standard", 1, true, fixed(1))
	expect(okQ and result.Results[1].Rarity == "Legendary", "guaranteed Legendary")
	expect(q.RollPity.Standard == 0 and result.Pity == 0, "counter reset")
	local _, _, again = Roll.Buy(q, "Standard", 1, true, fixed(1))
	expect(q.RollPity.Standard == 1 and again.Pity == 1, "and climbs again")

	local capped = profile(1000)
	capped.Stats.Rolls = Economy.MAX
	expect(Roll.Buy(capped, "Standard", 1, true, fixed(1)), "a capped roll counter still rolls")
	expectEq(capped.Stats.Rolls, Economy.MAX, "Stats.Rolls stays at the cap")
end)

test("Shape: pool a string of 1..16 bytes, count an integer in 1..10", function()
	for _, good in { { "Standard", 1 }, { "Standard", 10 }, { "x", 5 }, { ("x"):rep(16), 1 } } do
		expect(Roll.Shape(good[1], good[2]) == true, "well formed " .. good[1] .. " " .. good[2])
	end
	for i, bad in
		{
			{ "", 1 },
			{ ("x"):rep(17), 1 },
			{ 5, 1 },
			{ "Standard", 0 },
			{ "Standard", 11 },
			{ "Standard", 1.5 },
			{ "Standard", 0 / 0 },
			{ "Standard", math.huge },
			{ "Standard", "1" },
		}
	do
		expect(Roll.Shape(bad[1], bad[2]) == false, "malformed " .. i)
	end
end)

test("active roster has the requested counts; every drawable die can roll; removed ids are unknown", function()
	local counts = { Common = 0, Rare = 0, Epic = 0, Legendary = 0, Mythic = 0, Secret = 0 }
	for _, die in Dice.Types do
		counts[die.rarity] += 1
	end
	for rarity, count in { Common = 7, Rare = 7, Epic = 8, Legendary = 5, Mythic = 1, Secret = 1 } do
		expectEq(counts[rarity], count, rarity .. " roster")
	end
	for _, id in { "E02", "E04", "L03" } do
		expect(Dice.Types[id] == nil, id .. " removed from Config")
		for _, die in STANDARD.Dice do
			expect(die.Id ~= id, id .. " excluded from rolls")
		end
	end
	expect(Dice.Types.E08 and Dice.Types.E07 and Dice.Types.L06, "conversion targets exist")
end)
