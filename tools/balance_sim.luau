-- Balance sim: which wave does a deck reach? Run: python tools/balance_sim.py [seeds]  (bots summon and merge; real Match/Formulas/Balance)
-- Targets (docs/MVP.md "Waves"): "starter eager" clears wave 10 (the tutorial), "starter full" ends at 15, the "only C0x" ceilings by ~18.
local Server = game:GetService("ServerScriptService").Server
local Match = require(Server.Rules.Match)
local Dice = require(Server.Config.Dice)
local Formulas = require(Server.Rules.Formulas)
local Layout = require(game:GetService("ReplicatedStorage").Shared.Layout)

local P = { seeds = __SEEDS or 40, dt = 0.25, maxWave = 200 } -- dt = Balance.MaxStep; the live tick is 0.1

-- Bots. "eager": summon, then merge any lowest-pip pair at once. "full": a careful player: summon until
-- the board is full, then merge the pair that loses the least DPS, only when the next summon is affordable.
local dieDps
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
end

local function full(state)
	while true do
		while Match.TrySummon(state) do
		end
		if table.find(state.board, false) or state.mp < Match.SummonCost(state) then
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
						gain += dieDps(t, a.pip + 1) / #state.deck
					end
					local loss = dieDps(a.type, a.pip) * 2 - gain
					if not best or loss < best then
						best, from, to = loss, i, j
					end
				end
			end
		end
		if not best or not Match.TryMerge(state, from, to) then
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
function dieDps(typeId, pip)
	local cfg = Dice.Types[typeId]
	local proc = if cfg.procEvery then cfg.procFlat / cfg.procEvery else 0
	return (Formulas.HitDamage(typeId, pip, "Grunt") * (cfg.shots or 1) + proc) / Formulas.Period(typeId)
end

local function gruntDps(state)
	local sum = 0
	for _, die in state.board do
		if die then
			sum += dieDps(die.type, die.pip)
		end
	end
	return sum
end

-- Returns the lost wave and per-wave stats: progress of each regular mob at death (0 spawn .. 1 exit),
-- in death order, regular leaks, lives and Grunt DPS at the last step of the wave.
local function run(deck, seed, bot)
	local state = Match.New(1, Random.new(seed), 0, deck)
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

local function batch(name, deck, bot, quiet)
	local waves, all = {}, {}
	for s = 1, P.seeds do
		local lost, stats = run(deck, s * 7919, bot)
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
	print(`{name}: deck={table.concat(deck, ",")} lost wave min/median/max = {waves[1]}/{m}/{waves[#waves]}`)
	if quiet then
		return
	end
	print(
		"  wave gruntHp | median-over-seeds: regular-mob median death progress, end-of-wave (last 3 deaths mean), leaks, lives, gruntDPS"
	)
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
					Formulas.EnemyHp("Grunt", w),
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

test("sim", function()
	batch("starter eager", Dice.Deck, eager)
	batch("starter full", Dice.Deck, full)
	for _, id in Dice.Deck do -- ceiling: every summon and merge result is the same Common
		batch("only " .. id, { id }, full, id ~= "C02")
	end
	local ids = {}
	for id, cfg in Dice.Types do
		if cfg.rarity == "Rare" or cfg.rarity == "Epic" or cfg.rarity == "Legendary" then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		local x, y = Dice.Types[a].base * Dice.Types[a].rate, Dice.Types[b].base * Dice.Types[b].rate
		if x ~= y then
			return x > y
		end
		return a < b
	end)
	batch("strong full", { ids[1], ids[2], ids[3], ids[4], ids[5] }, full, true)
	batch("rares full", { "R01", "R02", "R03", "R04", "R05" }, full, true)
end)
