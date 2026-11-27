-- Pip rate, tier damage, in-match Power Up legality, aura adjacency/cap, Catalog fields, Astral Singularity.

local Server = game:GetService("ServerScriptService").Server
local Match = require(Server.Rules.Match)
local Board = require(Server.Rules.Board)
local Formulas = require(Server.Rules.Formulas)
local Catalog = require(Server.Rules.Catalog)
local Balance = require(Server.Config.Balance)
local Dice = require(Server.Config.Dice)
local Enemies = require(Server.Config.Enemies)

local PU = Balance.PowerUp

local function newState(deck)
	return Match.New(1, Random.new(3), 0, deck or Dice.Deck)
end

local function place(state, cell, typeId, pip)
	Board.Summon(state.board, cell, typeId, state.nextDieId)
	state.nextDieId += 1
	state.board[cell].pip = pip or 1
end

-- An Active wave that never spawns on its own, with one far-from-exit enemy of huge HP to hit.
local function arena(deck)
	local state = newState(deck)
	state.wave, state.waveState, state.queue, state.qi, state.nextSpawnAt = 1, "Active", { "Grunt" }, 1, math.huge
	local enemy = { id = 1, kind = "Runner", hp = 1e6, maxHp = 1e6, speed = 0.01, spawnAt = 0, dist = 5 }
	table.insert(state.enemies, enemy)
	return state, enemy
end

test("PipRate is 1..7 and attack period is 1 / (rate x PipRate[pip])", function()
	for pip = 1, Board.MAX_PIP do
		expectEq(Balance.PipRate[pip], pip, "PipRate " .. pip)
	end
	expectEq(#Balance.PipRate, Board.MAX_PIP, "one entry per pip")
	for id, cfg in Dice.Types do
		for pip = 1, Board.MAX_PIP do
			expectNear(Formulas.Period(id, pip), 1 / (cfg.rate * pip), 1e-9, id .. " pip " .. pip)
		end
	end
	expectNear(Formulas.Period("C01", 1, 0.5), 1 / 1.5, 1e-9, "aura shortens the period")
end)

test("MaxAttacksPerTick covers the fastest die at 7 pips with a full aura over one MaxStep", function()
	local fastest = 0
	for _, cfg in Dice.Types do
		fastest = math.max(fastest, cfg.rate)
	end
	local needed = Balance.MaxStep * fastest * Board.MAX_PIP * (1 + Balance.AuraCap)
	expect(Balance.MaxAttacksPerTick >= math.ceil(needed), "cap " .. Balance.MaxAttacksPerTick .. " >= " .. needed)
end)

test("a pip-7 die fires 7x as often as a pip-1 die and each hit deals the same damage", function()
	local hits = {}
	for _, pip in { 1, 7 } do
		local state, enemy = arena()
		place(state, 5, "C01", pip)
		for i = 1, 100 do
			Match.Step(state, i * 0.1)
		end
		hits[pip] = (enemy.maxHp - enemy.hp) / Formulas.HitDamage("C01", "Runner") -- a whole number of equal hits
		expectNear(hits[pip], math.floor(hits[pip] + 0.5), 1e-9, "equal hits, pip " .. pip)
	end
	expectNear(hits[7] / hits[1], 7, 0.7, "7 pips shoot about 7x as often")
	expect(hits[1] >= 9, "pip 1 fires about once a second for 10 s")
end)

test("tier multiplier and damage: 1 + DamagePerTier x (tier - 1), floored, never below 1", function()
	expectEq(Formulas.TierMul(1), 1, "tier 1")
	for tier = 1, PU.Max do
		expectNear(Formulas.TierMul(tier), 1 + PU.DamagePerTier * (tier - 1), 1e-12, "tier " .. tier)
		local expected = math.floor(Dice.Types.C03.base * Formulas.TierMul(tier) + 1e-9)
		expectEq(Formulas.HitDamage("C03", "Grunt", nil, tier), expected, "hammer tier " .. tier)
	end
	expect(Formulas.HitDamage("C03", "Grunt", nil, PU.Max) > Formulas.HitDamage("C03", "Grunt", nil, 1), "grows")
	expectEq(Formulas.HitDamage("C02", "Grunt", 8, 1), 17, "flat proc added after")
	expectEq(
		Formulas.HitDamage("C02", "Grunt", 8, PU.Max) - Formulas.HitDamage("C02", "Grunt", nil, PU.Max),
		8,
		"tier leaves the proc alone"
	)
	expectEq(Formulas.HitDamage("C04", "Grunt", nil, nil), Formulas.HitDamage("C04", "Grunt", nil, 1), "nil tier is 1")
end)

test("PowerUp config: Max 5 with Max - 1 whole, rising costs", function()
	expectEq(PU.Max, 5, "Max")
	expectEq(#PU.Costs, PU.Max - 1, "one cost per purchase")
	for i, c in PU.Costs do
		expect(c >= 1 and c == math.floor(c), "whole cost " .. i)
		expect(i == 1 or c > PU.Costs[i - 1], "rising " .. i)
	end
	expectEq(Formulas.PowerUpCost(PU.Max), nil, "no cost at max")
end)

test("TryPowerUp: climbs the table, pays through MP, then MaxTier", function()
	local state = newState()
	for tier = 1, PU.Max - 1 do
		state.mp = PU.Costs[tier]
		local ok, code = Match.TryPowerUp(state, "C01")
		expect(ok and code == nil, "tier " .. tier)
		expectEq(state.mp, 0, "paid exactly " .. PU.Costs[tier])
		expectEq(state.tiers.C01, tier + 1, "tier up")
	end
	state.mp = 1e6
	local ok, code = Match.TryPowerUp(state, "C01")
	expect(not ok and code == "MaxTier", "MaxTier")
	expectEq(state.mp, 1e6, "MaxTier costs nothing")
	expectEq(state.tiers.C02, 1, "other types unchanged")
end)

test("TryPowerUp rejections change nothing; MP never goes negative", function()
	local state = newState()
	state.mp = PU.Costs[1] - 1
	local ok, code = Match.TryPowerUp(state, "C01")
	expect(not ok and code == "NoMP", "NoMP")
	expectEq(state.mp, PU.Costs[1] - 1, "mp untouched")
	expectEq(state.tiers.C01, 1, "tier untouched")
	state.mp = 1e6
	for _, bad in { "R01", "", "c01", 5, true, {}, 0 / 0 } do
		local okB, codeB = Match.TryPowerUp(state, bad)
		expect(not okB and codeB == "NotInDeck", "NotInDeck " .. tostring(bad))
	end
	expectEq(state.mp, 1e6, "mp untouched")
	state.phase = "Ended"
	local okE, codeE = Match.TryPowerUp(state, "C01")
	expect(not okE and codeE == "WrongPhase", "WrongPhase")
	expectEq(state.tiers.C01, 1, "tier untouched when ended")
	local s2 = newState()
	local rng = Random.new(5)
	for _ = 1, 500 do
		s2.mp = rng:NextInteger(0, 1500)
		Match.TryPowerUp(s2, Dice.Deck[rng:NextInteger(1, #Dice.Deck)])
		expect(s2.mp >= 0, "mp >= 0")
	end
end)

test("a power-up applies to dice on the board and summoned later; resets per match", function()
	local state, enemy = arena({ "C03" })
	state.mp = 1000
	Match.TrySummon(state) -- before
	Match.TryPowerUp(state, "C03")
	Match.TryPowerUp(state, "C03")
	Match.TrySummon(state) -- after
	local per = Formulas.HitDamage("C03", "Runner", nil, 3)
	expect(per > Formulas.HitDamage("C03", "Runner", nil, 1), "tier 3 hits harder")
	Match.Step(state, 0.1)
	local dealt = enemy.maxHp - enemy.hp
	expectEq(dealt, per * 2, "both the earlier and the later die hit once, at tier 3")
	expectEq(newState({ "C03" }).tiers.C03, 1, "a new match starts at tier 1")
	expectEq(state.tiers.C03, 3, "the old one is untouched")
end)

test("TiersView: deck order, Cost nil at max", function()
	local state = newState({ "C03", "C01", "C03" })
	state.tiers.C01 = PU.Max
	local v = Match.TiersView(state)
	expectEq(#v, 2, "duplicates listed once")
	expect(v[1].Id == "C03" and v[1].Tier == 1 and v[1].Cost == PU.Costs[1], "first row")
	expect(v[2].Id == "C01" and v[2].Tier == PU.Max and v[2].Cost == nil, "max row has no cost")
end)

test("Board.Neighbours: orthogonal only, no wrap across rows", function()
	local function sorted(list)
		table.sort(list)
		return table.concat(list, ",")
	end
	expectEq(sorted(Board.Neighbours(1)), "2,6", "corner")
	expectEq(sorted(Board.Neighbours(5)), "4,10", "right edge does not wrap to 6")
	expectEq(sorted(Board.Neighbours(6)), "1,7,11", "left edge does not wrap to 5")
	expectEq(sorted(Board.Neighbours(8)), "3,7,9,13", "centre")
	expectEq(sorted(Board.Neighbours(15)), "10,14", "far corner")
end)

test("aura: formula, adjacency, cap, recomputed (no accumulation)", function()
	expectNear(Formulas.Aura("R05", 1, 1), 0.06, 1e-9, "beacon base")
	expectNear(Formulas.Aura("R05", 4, 3), 0.06 + 0.01 * 3 + 0.01 * 2, 1e-9, "beacon pip 4 tier 3")
	expectEq(Formulas.Aura("C01", 7, 5), 0, "no aura, no bonus")

	local state = newState({ "R05", "C01" })
	place(state, 8, "R05", 1)
	local a = Match.Auras(state)
	expectNear(a[7], 0.06, 1e-9, "left neighbour")
	expectNear(a[9], 0.06, 1e-9, "right neighbour")
	expectNear(a[3], 0.06, 1e-9, "above")
	expectNear(a[13], 0.06, 1e-9, "below")
	expectEq(a[8], nil, "not the source itself")
	expectEq(a[2], nil, "diagonal gets nothing")
	expectEq(a[4], nil, "two away gets nothing")
	-- Many sources add, then the total caps at AuraCap.
	place(state, 6, "R05", 7)
	place(state, 12, "R05", 7)
	place(state, 2, "R05", 7)
	state.tiers.R05 = PU.Max
	local b = Match.Auras(state)
	for cell, v in b do
		expect(v <= Balance.AuraCap + 1e-12, "cap at cell " .. cell)
	end
	expectNear(b[7], Balance.AuraCap, 1e-12, "stacked sources hit the cap")
	local c = Match.Auras(state) -- nothing accumulates between calls
	for cell, v in b do
		expectNear(c[cell], v, 1e-15, "repeatable " .. cell)
	end
	expect(Formulas.Period("C01", 1, b[7]) < Formulas.Period("C01", 1, nil), "shorter period")
end)

test("aura follows the board: removing a source removes its bonus at once", function()
	local state = newState({ "R05" })
	place(state, 1, "R05", 1)
	place(state, 2, "R05", 1)
	expectNear(Match.Auras(state)[1], 0.06, 1e-9, "neighbour gives its aura")
	state.board[2] = false
	expectEq(Match.Auras(state)[1], nil, "gone with the source")
end)

test("Catalog dice rows: AttackSpeed (2 dp, 1 pip) for all, Aura (base %) for aura dice, PowerUp block", function()
	local c = Catalog.Build()
	local byId = {}
	for _, row in c.Dice do
		byId[row.Id] = row
		local t = Dice.Types[row.Id]
		expectEq(row.AttackSpeed, math.floor(1 / t.rate * 100 + 0.5) / 100, row.Id .. " AttackSpeed")
		if t.aura then
			expectEq(row.Aura, math.floor(Formulas.Aura(row.Id, 1, 1) * 1000 + 0.5) / 10, row.Id .. " Aura")
		else
			expectEq(row.Aura, nil, row.Id .. " no Aura")
		end
	end
	expectEq(byId.R05.Aura, 6, "Beacon 6%")
	expectEq(byId.C01.AttackSpeed, 1, "Pebble 1.00 s")
	expectEq(byId.C02.AttackSpeed, 0.57, "Needle 0.57 s")
	expectEq(c.PowerUp.Max, PU.Max, "PowerUp.Max")
	expectEq(c.PowerUp.DamagePerTier, PU.DamagePerTier, "PowerUp.DamagePerTier")
	expectEq(#c.PowerUp.Costs, #PU.Costs, "PowerUp.Costs")
	for i, v in PU.Costs do
		expectEq(c.PowerUp.Costs[i], v, "cost " .. i)
	end
	c.PowerUp.Costs[1] = -1
	expect(PU.Costs[1] > 0, "the Catalog holds a copy")
end)

test("no die deals a zero-damage hit to any enemy kind", function()
	for id in Dice.Types do
		for kind in Enemies.Kinds do
			expect(Formulas.HitDamage(id, kind) >= 1, id .. " vs " .. kind)
		end
	end
end)

test("Singularity applies only to the sole Astral on a board", function()
	local astral = { type = "M01", pip = 3 }
	expect(not Formulas.HasSingularity({ false, { type = "C01" } }), "zero Astral")
	expect(Formulas.HasSingularity({ false, astral, { type = "C01" } }), "one Astral at any pip count")
	expect(not Formulas.HasSingularity({ astral, false, { type = "M01" } }), "two Astrals disable it")
	expectEq(Formulas.HitDamage("M01", "Grunt"), 140, "unbuffed")
	expectEq(Formulas.HitDamage("M01", "Grunt", nil, 1, true, false), 700, "exactly five times base")
	expectEq(Formulas.HitDamage("M01", "Grunt", nil, 1, true, true), 1400, "crit doubles the buffed hit")
	expectEq(Formulas.HitDamage("M01", "Grunt", nil, 2, true, true), 1540, "crit stacks with Power Up")
	expectEq(Formulas.HitDamage("C01", "Grunt", nil, 1, true, true), 16, "other dice keep their own damage")
end)

test("Singularity crits on ten of one hundred tickets and skips the RNG when inactive", function()
	local ticket, draws = 10, 0
	local rng = {
		NextInteger = function(_, low, high)
			draws += 1
			expectEq(low, 1, "lower bound")
			expectEq(high, 100, "upper bound")
			return ticket
		end,
	}
	expect(Formulas.SingularityCrit("M01", true, rng), "ticket ten crits")
	ticket = 11
	expect(not Formulas.SingularityCrit("M01", true, rng), "ticket eleven misses")
	expect(not Formulas.SingularityCrit("M01", false, rng), "inactive")
	expect(not Formulas.SingularityCrit("C01", true, rng), "other dice never crit from this ability")
	expectEq(draws, 2, "unrelated combat keeps the existing RNG stream")
end)
