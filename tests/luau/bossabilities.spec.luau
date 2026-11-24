-- Boss abilities: the pure state machine (timers, first casts, hold) and its Match integration (portal summon, hammer lock, dice shuffle,
-- stop-and-resume movement, determinism, Duel lanes), all on the match clock.

local Server = game:GetService("ServerScriptService").Server
local Shared = game:GetService("ReplicatedStorage").Shared
local Match = require(Server.Rules.Match)
local Board = require(Server.Rules.Board)
local BossAbilities = require(Server.Rules.BossAbilities)
local Formulas = require(Server.Rules.Formulas)
local Dice = require(Server.Config.Dice)
local Layout = require(Shared.Layout)
local Bosses = require(Shared.Bosses)

local DT = 0.05
local AHEAD = 30 + Bosses.Ability.GoblinKing.PortalAhead -- boss parked at 30 in the summon tests

local function phases(events)
	local list = {}
	for _, e in events do
		table.insert(list, e.Phase)
	end
	return table.concat(list, ",")
end

-- An Active wave that never spawns or clears on its own; the spec adds bosses and enemies by hand.
local function openMatch(state)
	state.wave, state.waveState = 1, "Active"
	state.queue, state.qi, state.nextSpawnAt = { { kind = "Grunt", hp = 20 } }, 1, math.huge
	state.lives = 1e9
	if state.partner then
		state.partner.lives = 1e9
	end
end

local function add(state, kind: string, variant: string?, dist: number, seat: number?, hp: number?)
	local speed = if kind == "Boss" then 3 else 4
	local enemy = {
		id = state.nextEnemyId,
		kind = kind,
		hp = hp or 1e9,
		maxHp = hp or 1e9,
		speed = speed,
		spawnAt = state.lastNow - dist / speed,
		dist = dist,
		seat = seat or 1,
		ability = if variant then BossAbilities.New(variant, state.lastNow) else nil,
	}
	state.nextEnemyId += 1
	table.insert(state.enemies, enemy)
	return enemy
end

-- Parks an enemy at `dist` (speed ~0) so it stays put.
local function park(state, enemy, dist: number)
	enemy.speed = 0.0001
	enemy.dist = dist
	enemy.spawnAt = state.lastNow - dist / enemy.speed
end

local function run(state, seconds: number, each: (() -> ())?)
	for _ = 1, math.floor(seconds / DT + 0.5) do
		Match.Step(state, state.lastNow + DT)
		if each then
			each()
		end
	end
end

local function newSolo()
	local state = Match.New(1, Random.new(4), 0, Dice.Deck)
	openMatch(state)
	return state
end

test("timers: first cast delay, interval, windup lead and resume, per variant", function()
	for _, id in Bosses.List do
		local cfg = Bosses.Ability[id]
		local st = BossAbilities.New(id, 100)
		expectEq(st.castAt, 100 + cfg.First, "first cast " .. id)
		expectEq(
			#BossAbilities.Tick(st, 100 + cfg.First - cfg.CastAt - 0.001),
			0,
			"nothing before the first phase " .. id
		)
		expect(not BossAbilities.Holding(st), "idle before the windup")
		-- one big hitch past the whole cast: every phase fires once, in order, with its own time
		local events = BossAbilities.Tick(st, 100 + cfg.First + 5)
		expectEq(phases(events), "windup,cast,resume", "order " .. id)
		local at = {}
		for _, e in events do
			at[e.Phase] = e.At
		end
		expectEq(at.windup, 100 + cfg.First - cfg.CastAt, "windup time " .. id)
		expectEq(at.cast, 100 + cfg.First, "cast time " .. id)
		expectEq(at.resume, 100 + cfg.First - cfg.CastAt + cfg.ClipSeconds, "resume time " .. id)
		expectEq(st.castAt, 100 + cfg.First + cfg.Interval, "next cast = cast + interval " .. id)
		expect(not BossAbilities.Holding(st), "released after the clip " .. id)
	end
	expectEq(Bosses.Ability.GoblinKing.First, 8, "PortalSummon first")
	expectEq(Bosses.Ability.GoblinKing.Interval, 14, "PortalSummon interval")
	expectEq(Bosses.Ability.CursedKing.First, 9, "HammerLock first")
	expectEq(Bosses.Ability.CursedKing.Interval, 16, "HammerLock interval")
	expectEq(Bosses.Ability.CourtJester.First, 7, "DiceShuffle first")
	expectEq(Bosses.Ability.CourtJester.Interval, 12, "DiceShuffle interval")
end)

test("Match: the boss stands still from windup start to clip end, then walks on", function()
	local state = newSolo()
	local boss = add(state, "Boss", "GoblinKing", 0)
	local cfg = Bosses.Ability.GoblinKing
	local spawn = state.lastNow
	run(state, cfg.First - cfg.CastAt - 0.2)
	expect(boss.dist > 1, "walking before the windup")
	expect(math.abs(boss.dist - 3 * (state.lastNow - spawn)) < 1e-6, "dist follows speed x time")
	run(state, 0.2 + DT) -- the windup has started
	local held = boss.dist
	expect(boss.speed < 0.01, "held speed ~0")
	local frozen = true
	run(state, cfg.ClipSeconds - DT - 0.1, function()
		frozen = frozen and math.abs(boss.dist - held) < 0.01
	end)
	expect(frozen, "no movement during the clip")
	run(state, 0.3) -- past the end of the clip
	expect(boss.speed > 2.9, "speed restored")
	run(state, 1)
	expect(boss.dist > held + 2, "walks again")
end)

test("Match: replication events carry Id, Ability, Phase and At (the cast time)", function()
	local state = newSolo()
	local boss = add(state, "Boss", "GoblinKing", 0)
	run(state, 9)
	local batch = Match.TakeOut(state)
	expectEq(#batch.A, 2, "windup + cast")
	expectEq(batch.A[1].Phase, "windup", "windup first")
	expectEq(batch.A[2].Phase, "cast", "then cast")
	for _, record in batch.A do
		expectEq(record.Id, boss.id, "Id")
		expectEq(record.Ability, "PortalSummon", "Ability")
		expectEq(record.At, 8, "At = cast time, spawn at 0")
	end
	expectEq(#Match.TakeOut(state).A, 0, "drained")
end)

test("hold composes with a slow and restores base x slow exactly", function()
	local state = newSolo()
	local boss = add(state, "Boss", "GoblinKing", 0)
	boss.slowMul, boss.slowUntil = 0.5, math.huge
	boss.baseSpeed = 3
	boss.speed = 1.5
	boss.spawnAt = state.lastNow
	run(state, 8.0 + DT)
	expect(boss.speed < 0.01, "held while slowed")
	run(state, 2.0)
	expect(math.abs(boss.speed - 1.5) < 1e-9, "back to base x slow, not the full speed")
	expectEq(boss.baseSpeed, 3, "base kept while a modifier is active")
end)

-- Dice helpers -------------------------------------------------------------------------------------------------------

local function place(state, cell: number, pip: number?, typeId: string?)
	Board.Summon(state.board, cell, typeId or "C01", state.nextDieId)
	state.nextDieId += 1
	state.board[cell].pip = pip or 1
	state.board[cell].cd = 0
end

local function lockedCells(state): { number }
	local cells = {}
	for cell = 1, 15 do
		if state.board[cell] and state.board[cell].lockedBy then
			table.insert(cells, cell)
		end
	end
	return cells
end

local function shotsByCell(state): { [number]: number }
	local shots = {}
	for _, f in Match.TakeOut(state).F do
		shots[f.Cell] = (shots[f.Cell] or 0) + 1
	end
	return shots
end

local function castRecord(batch)
	for _, a in batch.A do
		if a.Phase == "cast" then
			return a
		end
	end
	return nil
end

local function distinct(cells): boolean
	local seen = {}
	for _, c in cells do
		if seen[c] then
			return false
		end
		seen[c] = true
	end
	return true
end

-- PortalSummon ---------------------------------------------------------------------------------------------------------

local function summoned(state, boss)
	local list = {}
	for _, e in state.enemies do
		if e ~= boss and e.kind ~= "Boss" then
			table.insert(list, e)
		end
	end
	return list
end

test("PortalSummon: 3 Grunts and 1 Runner spawn one per regular interval, ahead of the boss", function()
	local state = newSolo()
	local boss = add(state, "Boss", "GoblinKing", 0)
	park(state, boss, 30)
	run(state, 8.0 - DT / 2)
	expectEq(#summoned(state, boss), 0, "nothing before the cast")
	Match.TakeOut(state)
	local records = {}
	local lastAt = 0
	run(state, 9, function()
		for _, r in Match.TakeOut(state).S do
			table.insert(records, r)
			lastAt = state.lastNow
			local dist = r.Speed * (state.lastNow - r.SpawnAt)
			expect(
				dist <= AHEAD + r.Speed * DT * 3 + 0.01 and dist >= AHEAD - 0.01,
				"starts at the boss: "
					.. dist
					.. " "
					.. r.Kind
					.. " speed "
					.. r.Speed
					.. " lateness "
					.. (state.lastNow - lastAt)
			)
			expectEq(r.Seat, 1, "lane")
			expectEq(r.Arena, "Solo", "arena")
		end
	end)
	expectEq(#records, 4, "4 spawned")
	local kinds = { Grunt = 0, Runner = 0 }
	for _, r in records do
		kinds[r.Kind] += 1
	end
	expectEq(kinds.Grunt, 3, "3 grunts")
	expectEq(kinds.Runner, 1, "1 runner")
	expectEq(records[2].Kind, "Runner", "the fast one is in the middle")
	local gap = Formulas.SpawnInterval(state.wave)
	expect(math.abs(lastAt - 8 - 3 * gap) <= DT + 1e-6, "spaced by the regular spawn interval: " .. (lastAt - 8))
	expectEq(#summoned(state, boss), 4, "all alive on the route")
end)

test("PortalSummon: the cast record carries Info (distance, lane); the summons keep walking from there", function()
	local state = newSolo()
	local boss = add(state, "Boss", "GoblinKing", 0)
	park(state, boss, 30)
	run(state, 8.0 + DT)
	local cast = castRecord(Match.TakeOut(state))
	expectEq(cast.Ability, "PortalSummon", "ability")
	expect(math.abs(cast.Info.Distance - AHEAD) < 0.01 and cast.Info.Lane == 1, "Info distance and lane")
	expect(math.abs(cast.Target - AHEAD) < 0.01, "Target = the portal distance, ahead of the boss")
	run(state, 10)
	local mine = summoned(state, boss)
	expectEq(#mine, 4, "alive")
	for _, e in mine do
		expect(e.dist > AHEAD and e.dist < Layout.PathLength, "walked on from the boss: " .. e.dist)
	end
end)

test("PortalSummon: not counted toward the wave quota; the wave waits for them, then clears", function()
	local state = newSolo()
	state.queue, state.qi = { { kind = "Grunt", hp = 20 } }, 2 -- the quota is fully spawned
	local boss = add(state, "Boss", "GoblinKing", 0, 1, 50)
	park(state, boss, 30)
	run(state, 8.0 + DT)
	boss.hp = 0 -- the boss dies right at the cast
	run(state, 0.3)
	expectEq(state.qi, 2, "queue index untouched")
	expectEq(state.waveState, "Active", "the wave waits for the pending and living summons")
	run(state, 9)
	expectEq(#summoned(state, boss), 4, "all 4 were created although the boss died")
	expectEq(state.waveState, "Active", "still active while they live")
	for _, e in state.enemies do
		e.hp = 0
	end
	run(state, 0.2)
	expectEq(state.waveState, "Prep", "cleared once they are dead")
	expect(state.kills >= 4, "kills count like any enemy")
end)

test("PortalSummon: breaching summons cost lives like normal enemies", function()
	local state = newSolo()
	state.lives = 20
	local boss = add(state, "Boss", "GoblinKing", 0)
	park(state, boss, Layout.PathLength * 0.7)
	run(state, 8.0 + DT)
	run(state, 3)
	expectEq(state.lives, 20, "not yet at the end")
	run(state, 20)
	expect(state.lives <= 20 - 4, "4 lives lost to the breach: " .. state.lives)
end)

test("PortalSummon: no summon when the boss is dead or past 95% of its route", function()
	local state = newSolo()
	local boss = add(state, "Boss", "GoblinKing", 0)
	park(state, boss, Layout.PathLength * 0.96)
	run(state, 9.5)
	expectEq(#summoned(state, boss), 0, "too close to the end")

	local dead = newSolo()
	local b2 = add(dead, "Boss", "GoblinKing", 0)
	park(dead, b2, 30)
	run(dead, 7.95)
	b2.hp = 0
	run(dead, 1.5)
	expectEq(#summoned(dead, b2), 0, "a dead boss summons nothing")
end)

test("PortalSummon: deterministic; each Duel lane summons on its own lane", function()
	local function simulate()
		local state = Match.NewDuel(9, Random.new(5), 0, Dice.Deck, Dice.Deck)
		openMatch(state)
		local a = add(state, "Boss", "GoblinKing", 0, 1)
		local b = add(state, "Boss", "GoblinKing", 0, 2)
		park(state, a, 20)
		park(state, b, 40)
		local trace = {}
		run(state, 18, function()
			for _, r in Match.TakeOut(state).S do
				table.insert(
					trace,
					string.format("%d|%s|%d|%.4f|%.4f|%d", r.Id, r.Kind, r.Seat, r.SpawnAt, r.Hp, r.Speed * 1000)
				)
			end
		end)
		return table.concat(trace, ","), state
	end
	local one, state = simulate()
	local two = simulate()
	expectEq(one, two, "same inputs, same summons")
	local perLane = { 0, 0 }
	for _, e in state.enemies do
		if e.kind ~= "Boss" then
			perLane[e.seat] += 1
			expect(e.dist > (if e.seat == 1 then 19 else 39), "starts at its own boss: " .. e.seat .. " " .. e.dist)
		end
	end
	expectEq(perLane[1], 4, "lane 1")
	expectEq(perLane[2], 4, "lane 2")
end)

-- DiceShuffle ----------------------------------------------------------------------------------------------------------

local function shuffleRun(dice: number)
	local state = newSolo()
	for cell = 1, dice do
		place(state, cell, 1 + cell % 3, if cell % 2 == 0 then "C01" else "C02")
	end
	local boss = add(state, "Boss", "CourtJester", 0)
	park(state, boss, 30)
	run(state, 7.0 + DT)
	return state, castRecord(Match.TakeOut(state))
end

test("DiceShuffle: 5 distinct dice get a random pip 1 to 7, types and cells stay, deterministic", function()
	local state, cast = shuffleRun(12)
	expectEq(cast.Ability, "DiceShuffle", "ability")
	expectEq(#cast.Target, 5, "5 dice")
	expect(distinct(cast.Target), "distinct")
	expectEq(#cast.Info.Pips, 5, "5 pips")
	local picked = {}
	for i, cell in cast.Target do
		picked[cell] = true
		local pip = cast.Info.Pips[i]
		expect(pip >= 1 and pip <= 7 and pip == math.floor(pip), "pip in range: " .. pip)
		expectEq(state.board[cell].pip, pip, "board updated")
	end
	for cell = 1, 12 do
		expectEq(state.board[cell].type, if cell % 2 == 0 then "C01" else "C02", "type stays")
		if not picked[cell] then
			expectEq(state.board[cell].pip, 1 + cell % 3, "others untouched")
		end
	end
	local _, cast2 = shuffleRun(12)
	expectEq(table.concat(cast2.Target, ","), table.concat(cast.Target, ","), "same dice")
	expectEq(table.concat(cast2.Info.Pips, ","), table.concat(cast.Info.Pips, ","), "same pips")
end)

test("DiceShuffle: fewer dice than 5 shuffle them all; an empty board is a no-op", function()
	local _, three = shuffleRun(3)
	expectEq(#three.Target, 3, "all three")
	local state, none = shuffleRun(0)
	expect(none.Target == nil, "nothing chosen")
	expectEq(#state.enemies, 1, "no error, the boss is still there")
end)

test("DiceShuffle: only the own seat of the boss is touched (Duel)", function()
	local state = Match.NewDuel(3, Random.new(2), 0, Dice.Deck, Dice.Deck)
	openMatch(state)
	for cell = 1, 8 do
		place(state, cell, 1)
		place(state.partner, cell, 1)
	end
	local boss = add(state, "Boss", "CourtJester", 0, 2)
	park(state, boss, 30)
	run(state, 7.0 + DT)
	for cell = 1, 8 do
		expectEq(state.board[cell].pip, 1, "seat 1 untouched")
	end
	local changed = 0
	for cell = 1, 8 do
		changed += if state.partner.board[cell].pip ~= 1 then 1 else 0
	end
	expect(changed >= 1, "seat 2 shuffled")
end)

-- HammerLock -----------------------------------------------------------------------------------------------------------

local function lockMatch(dice: number)
	local state = newSolo()
	local dummy = add(state, "Grunt", nil, 5)
	park(state, dummy, 5)
	for cell = 1, dice do
		place(state, cell, 1, "C01")
	end
	local boss = add(state, "Boss", "CursedKing", 0)
	park(state, boss, 30)
	return state, boss
end

test("HammerLock: locks 3 distinct unlocked dice recording the boss; they neither fire nor bank shots", function()
	local state, boss = lockMatch(10)
	run(state, 8.0)
	Match.TakeOut(state)
	run(state, 1.0 + DT) -- the cast lands at 9 s
	local cast = castRecord(Match.TakeOut(state))
	expectEq(cast.Ability, "HammerLock", "ability")
	expectEq(#cast.Target, 3, "3 cells")
	expect(distinct(cast.Target), "distinct")
	local locked = lockedCells(state)
	expectEq(#locked, 3, "3 locked")
	for _, cell in locked do
		expectEq(state.board[cell].lockedBy, boss.id, "records the boss")
	end
	run(state, 4)
	local shots = shotsByCell(state)
	for _, cell in locked do
		expect((shots[cell] or 0) == 0, "locked die does not fire: " .. cell)
	end
	local others = 0
	for cell = 1, 10 do
		if not state.board[cell].lockedBy then
			others += shots[cell] or 0
		end
	end
	expect(others > 0, "unlocked dice still fire")
end)

test("HammerLock: a locked die cannot be merged", function()
	local state = lockMatch(0)
	place(state, 1, 2)
	place(state, 2, 2)
	place(state, 3, 2)
	state.board[1].lockedBy = 99
	local ok, code = Match.TryMerge(state, 1, 2)
	expect(not ok and code == "IllegalMerge", "locked source refused")
	ok, code = Match.TryMerge(state, 2, 1)
	expect(not ok and code == "IllegalMerge", "locked target refused")
	expect(state.board[1] and state.board[2], "board untouched")
	ok = Match.TryMerge(state, 2, 3)
	expect(ok, "unlocked dice still merge")
end)

test("HammerLock: a lock ends the moment its boss dies, and the dice attack again", function()
	local state, boss = lockMatch(6)
	run(state, 9.0 + DT)
	expectEq(#lockedCells(state), 3, "locked")
	run(state, 2)
	Match.TakeOut(state)
	boss.hp = 0
	run(state, DT * 2)
	expectEq(#lockedCells(state), 0, "all released on the death")
	run(state, 2)
	local shots = shotsByCell(state)
	for cell = 1, 6 do
		expect((shots[cell] or 0) > 0, "every die fires again: " .. cell)
	end
end)

test("HammerLock: a boss that leaves by breaching also releases its locks", function()
	local state, boss = lockMatch(6)
	run(state, 9.0 + DT)
	expectEq(#lockedCells(state), 3, "locked")
	run(state, 2)
	boss.speed = 50
	boss.spawnAt = state.lastNow - Layout.PathLength / 50
	run(state, DT * 2)
	expectEq(#lockedCells(state), 0, "released when the boss is gone")
end)

test("HammerLock: later casts lock 3 more, never more than 6 by one boss; nothing left, nothing happens", function()
	local state = lockMatch(15)
	run(state, 9.0 + DT)
	expectEq(#lockedCells(state), 3, "first cast")
	run(state, 16)
	expectEq(#lockedCells(state), 6, "second cast: 6")
	run(state, 16)
	expectEq(#lockedCells(state), 6, "capped at MaxLocked")

	local small = lockMatch(2)
	run(small, 9.0 + DT)
	expectEq(#lockedCells(small), 2, "only 2 dice exist")
	run(small, 16)
	expectEq(#lockedCells(small), 2, "no unlocked dice remain: no change")
end)

test("HammerLock: each Duel lane locks only its own board, deterministic", function()
	local function simulate()
		local state = Match.NewDuel(7, Random.new(2), 0, Dice.Deck, Dice.Deck)
		openMatch(state)
		for cell = 1, 10 do
			place(state, cell, 1)
			place(state.partner, cell, 1)
		end
		local a = add(state, "Boss", "CursedKing", 0, 1)
		local b = add(state, "Boss", "CursedKing", 0, 2)
		park(state, a, 30)
		park(state, b, 30)
		b.ability.castAt += 4
		run(state, 9.0 + DT)
		local first = { #lockedCells(state), #lockedCells(state.partner) }
		run(state, 4)
		return state, a, b, first
	end
	local state, a, b, first = simulate()
	expectEq(first[1], 3, "lane 1 locked")
	expectEq(first[2], 0, "lane 2 not yet")
	expectEq(#lockedCells(state.partner), 3, "lane 2 locked later")
	for cell = 1, 10 do
		local x, y = state.board[cell].lockedBy, state.partner.board[cell].lockedBy
		expect(x == nil or x == a.id, "seat 1 dice only by boss 1")
		expect(y == nil or y == b.id, "seat 2 dice only by boss 2")
	end
	local again = simulate()
	expectEq(table.concat(lockedCells(again), ","), table.concat(lockedCells(state), ","), "deterministic")
end)

test("determinism and Duel: two lanes run on the same clock independently", function()
	local function simulate()
		local state = Match.NewDuel(9, Random.new(5), 0, Dice.Deck, Dice.Deck)
		openMatch(state)
		local a = add(state, "Boss", "GoblinKing", 0, 1)
		local b = add(state, "Boss", "GoblinKing", 0, 2)
		local trace = {}
		run(state, 20, function()
			table.insert(trace, string.format("%.4f|%.4f", a.dist, b.dist))
		end)
		return table.concat(trace, ","), a, b
	end
	local one, a, b = simulate()
	local two = simulate()
	expectEq(one, two, "same inputs, same trajectory")
	expect(a.ability ~= b.ability, "separate state per boss")
	expectEq(a.ability.castAt, b.ability.castAt, "same schedule")
	local s2 = Match.NewDuel(9, Random.new(5), 0, Dice.Deck, Dice.Deck)
	openMatch(s2)
	local x = add(s2, "Boss", "GoblinKing", 0, 1)
	local y = add(s2, "Boss", "GoblinKing", 0, 2)
	y.ability.castAt += 4
	run(s2, 7.2)
	expect(x.speed < 0.01, "lane 1 is in its windup")
	expect(y.speed > 2.9, "lane 2 still walking")
end)

test("a dead boss simply stops; non-boss enemies have no ability state", function()
	local state = newSolo()
	local boss = add(state, "Boss", "GoblinKing", 0)
	local grunt = add(state, "Grunt", nil, 3)
	expect(grunt.ability == nil, "grunt has none")
	run(state, 7.5)
	boss.hp = 0
	run(state, 3)
	expectEq(#state.enemies, 1, "boss removed, grunt remains")
	for _, a in Match.TakeOut(state).A do
		expectEq(a.Id, boss.id, "only the boss emits")
	end
end)

test("client: a missing clip module is skipped; the blend weight ramps in, holds, ramps out and ends", function()
	local Player = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.BossAbilityPlayer)
	expect(Player.Data("GoblinKing") == nil, "no data module yet: no animation")
	expect(Player.Sample(nil, 1.8, 0.5) == nil, "no data, no override")
	expect(Player.Weight(1.8, -0.1) == nil, "before the start")
	expect(math.abs(Player.Weight(1.8, Player.BlendIn / 2) - 0.5) < 1e-9, "half blended in")
	expectEq(Player.Weight(1.8, 1.0), 1, "full while playing")
	expect(math.abs(Player.Weight(1.8, 1.8 + Player.BlendOut / 2) - 0.5) < 1e-9, "half blended out")
	expect(Player.Weight(1.8, 1.8 + Player.BlendOut + 0.01) == nil, "finished")
end)
