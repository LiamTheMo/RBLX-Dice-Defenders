-- Balance sim: which wave does a deck reach? Run: python tools/balance_sim.py [seeds] [name filter]  (bots summon and merge; real Match/Formulas/Balance)
-- A scenario = deck + die level(s) + collection (crit bonus from every owned die, Progression.CritOf). Real Match plays the abilities.
-- Targets: new player (starter Commons lv1) 12-16, early (Commons+Rares) ~50, mid (Epics+Rares) ~80, late (Legendary/Mythic) 120-150.
-- Both bots also buy in-match power-ups (Match.TryPowerUp) when the board is full and no merge is wanted.
local Server = game:GetService("ServerScriptService").Server
local Match = require(Server.Rules.Match)
local Dice = require(Server.Config.Dice)
local Formulas = require(Server.Rules.Formulas)
local CoopWaves = require(Server.Config.CoopWaves)
local Progression = require(Server.Config.Progression)
local DiceClasses = require(Server.Config.DiceClasses)
local Layout = require(game:GetService("ReplicatedStorage").Shared.Layout)

local P = { seeds = __SEEDS or 40, dt = 0.25, maxWave = 200, only = __ONLY or "" } -- dt = Balance.MaxStep; the live tick is 0.1

-- Bots. "eager": summon, then merge any lowest-pip pair at once. "full": a careful player: summon until
-- the board is full, then merge the pair that loses the least DPS, only when the next summon is affordable.
local dieDps

-- Power-up policy: the deck type with the most pips on the board that is not at max tier gets its next tier
-- when affordable (so the cheapest tier of the type that matters most).
local function powerUp(state)
	local pips = {}
	for _, die in state.board do
		if die then
			pips[die.type] = (pips[die.type] or 0) + die.pip
		end
	end
	local best
	for _, t in state.deck do
		if pips[t] and Formulas.PowerUpCost(state.tiers[t]) and (not best or pips[t] > pips[best]) then
			best = t
		end
	end
	return best ~= nil and Match.TryPowerUp(state, best)
end

local function eager(state)
	while Match.TrySummon(state) do
	end
	local merged = true
	while merged do
		merged = false
		local best -- {pip, from, to}
		for i = 1, 15 do
			local a = state.board[i]
			if a and a.pip < 7 then
				for j = i + 1, 15 do
					local b = state.board[j]
					if b and b.type == a.type and b.pip == a.pip and (not best or a.pip < best[1]) then
						best = { a.pip, i, j }
						break
					end
				end
			end
		end
		if best and Match.TryMerge(state, best[2], best[3]) then
			merged = true
			while Match.TrySummon(state) do
			end
		end
	end
	while not table.find(state.board, false) and powerUp(state) do
	end
end

local function full(state)
	while true do
		while Match.TrySummon(state) do
		end
		if table.find(state.board, false) then
			return
		end
		if state.mp < Match.SummonCost(state) then
			powerUp(state) -- no merge affordable yet: spend on a power-up instead of waiting
			return
		end
		local best, from, to
		for i = 1, 15 do
			local a = state.board[i]
			for j = i + 1, 15 do
				local b = state.board[j]
				if a.pip < 7 and b.type == a.type and b.pip == a.pip then
					local gain = 0
					for _, t in state.deck do
						gain += dieDps(t, a.pip + 1, state.tiers[t]) / #state.deck
					end
					local loss = dieDps(a.type, a.pip, state.tiers[a.type]) * 2 - gain
					if not best or loss < best then
						best, from, to = loss, i, j
					end
				end
			end
		end
		if not best or not Match.TryMerge(state, from, to) then
			powerUp(state)
			return
		end
	end
end

local function median(t)
	local c = table.clone(t)
	table.sort(c)
	return c[(#c + 1) // 2]
end

-- Damage per second of one die on a Grunt (ignores First/overkill; Needle's proc averaged in).
local simLevels = {}
function dieDps(typeId, pip, tier)
	local rarity = Dice.Types[typeId].rarity
	local level = simLevels[typeId] or 1
	local cfg = DiceClasses.View(typeId, Progression.Class(rarity, level))
	local mul = Progression.DamageMul(rarity, level)
	local proc = if cfg.procEvery then math.floor(cfg.procFlat * mul) / cfg.procEvery else 0
	return (Formulas.HitDamage(typeId, "Grunt", nil, tier, nil, nil, nil, cfg, mul) * (cfg.shots or 1) + proc)
		/ Formulas.Period(typeId, pip)
end

local function gruntDps(state)
	local sum = 0
	for _, die in state.board do
		if die then
			sum += dieDps(die.type, die.pip, state.tiers[die.type])
		end
	end
	return sum
end

-- Returns the lost wave and per-wave stats: progress of each regular mob at death (0 spawn .. 1 exit),
-- in death order, regular leaks, lives and Grunt DPS at the last step of the wave.
local function run(deck, seed, bot, critBonus)
	local state = Match.New(1, Random.new(seed), 0, deck, nil, critBonus, nil, simLevels)
	local now = 0
	local info, stats = {}, {}
	for _ = 1, 3000000 do
		now += P.dt
		Match.Step(state, now)
		for _, s in state.out.S do
			info[s.Id] = { kind = s.Kind, speed = s.Speed, spawnAt = s.SpawnAt, wave = state.wave }
		end
		for _, r in state.out.R do
			local e = info[r.Id]
			if e and (e.kind == "Grunt" or e.kind == "Runner") then
				local w = stats[e.wave] or { prog = {}, leaks = 0 }
				stats[e.wave] = w
				if r.Why == "Kill" then
					table.insert(w.prog, math.min(1, e.speed * (state.lastNow - e.spawnAt) / Layout.PathLength))
				else
					w.leaks += 1
				end
			end
			info[r.Id] = nil
		end
		local w = stats[state.wave] or { prog = {}, leaks = 0 }
		stats[state.wave] = w
		w.lives, w.dps = state.lives, gruntDps(state)
		Match.TakeOut(state)
		if state.phase ~= "Playing" or state.wave > P.maxWave then
			break
		end
		bot(state)
	end
	return state.wave, stats
end

local function batch(name, deck, bot, quiet, critBonus)
	local waves, all = {}, {}
	for s = 1, P.seeds do
		local lost, stats = run(deck, s * 7919, bot, critBonus)
		if lost < 5 then
			print(
				"LOST",
				s * 7919,
				lost,
				stats[lost] and #stats[lost].prog,
				stats[lost] and stats[lost].leaks,
				stats[lost] and stats[lost].dps
			)
		end
		table.insert(waves, lost)
		table.insert(all, stats)
	end
	table.sort(waves)
	print("  all: " .. table.concat(waves, " "))
	local m = waves[(#waves + 1) // 2]
	print(`{name} [crit +{critBonus or 0}%]: deck={table.concat(deck, ",")} lost wave min/median/max = {waves[1]}/{m}/{waves[#waves]}`)
	local cleared = 0
	for _, w in waves do
		cleared += if w > 10 then 1 else 0
	end
	print(`  cleared wave 10 in {cleared}/{#waves} runs`)
	if quiet then
		return
	end
	print(
		"  wave gruntHp | median-over-seeds: regular-mob median death progress, end-of-wave (last 3 deaths mean), leaks, lives, gruntDPS"
	)
	local starts, base = {}, CoopWaves.InitialHp -- b of each wave (CoopWaves.Next)
	for w = 1, P.maxWave do
		starts[w] = base
		local _, nextBase = CoopWaves.Next(w, base)
		base = nextBase
	end
	for w = 1, waves[#waves] do
		local mid, tail, leaks, lives, dps = {}, {}, {}, {}, {}
		for _, stats in all do
			local x = stats[w]
			if x and #x.prog >= 3 and x.lives then -- the wave the run was lost in is partial but still counted
				local p = table.clone(x.prog)
				local n = #p
				table.insert(tail, (p[n] + p[n - 1] + p[n - 2]) / 3)
				table.sort(p)
				table.insert(mid, p[(#p + 1) // 2])
				table.insert(leaks, x.leaks)
				table.insert(lives, x.lives)
				table.insert(dps, x.dps)
			end
		end
		if #mid > 0 then
			print(
				string.format(
					"  w%-2d %6d | n=%-2d mid %.2f end %.2f leaks %d lives %d dps %.0f",
					w,
					starts[w],
					#mid,
					median(mid),
					median(tail),
					median(leaks),
					median(lives),
					median(dps)
				)
			)
		end
	end
end

-- Levels: `lv` is a level for every deck die (clamped to its rarity's cap; "top" = the cap), others default to `rest`
-- ("top" or a number) for the crit bonus of the rest of the collection (nil = only deck dice owned).
local function levelOf(id, v)
	local cap = Progression.MaxLevel(Dice.Types[id].rarity)
	return if v == "top" then cap else math.min(v, cap)
end

local function scenario(name, deck, lv, collection, bots)
	if not string.find(name, P.only, 1, true) then
		return
	end
	simLevels = {}
	local crit = 0
	for id, cfg in Dice.Types do
		local inDeck = table.find(deck, id)
		local v = if inDeck then lv else collection
		if v then
			local level = levelOf(id, v)
			if inDeck then
				simLevels[id] = level
			end
			crit += Progression.CritOf(cfg.rarity, level)
		end
	end
	for _, bot in bots or { "eager", "full" } do
		batch(`{name} {bot}`, deck, if bot == "eager" then eager else full, true, crit)
	end
end

test("sim", function()
	local R = { "R01", "R02", "R03", "R04", "R05" }
	scenario("starter C lv1", Dice.Deck, 1)
	scenario("starter C lv9", Dice.Deck, 9)
	scenario("starter C lv15", Dice.Deck, "top")
	scenario("4C+1R lv1", { "C01", "C02", "C03", "C04", "R01" }, 1)
	scenario("4C+1E lv1", { "C01", "C02", "C03", "C04", "E01" }, 1)
	scenario("rares lv1", R, 1)
	scenario("rares lv7", R, 7)
	scenario("rares top", R, "top", 7)
	scenario("early top", { "R01", "R04", "R05", "C02", "C05" }, "top", 7)
	scenario("mid top", { "E01", "E02", "E03", "R01", "R05" }, "top", 9)
	scenario("late top", { "M01", "L02", "L01", "E03", "R01" }, "top", "top")
end)
