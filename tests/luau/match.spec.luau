-- Formulas, breach/loss, stipend, boss warning, kill MP, perk damage, First
-- targeting, layout geometry, and a scripted win.

local Server = game:GetService("ServerScriptService").Server
local Match = require(Server.Rules.Match)
local Board = require(Server.Rules.Board)
local Formulas = require(Server.Rules.Formulas)
local Balance = require(Server.Config.Balance)
local Dice = require(Server.Config.Dice)
local Enemies = require(Server.Config.Enemies)
local Layout = require(game:GetService("ReplicatedStorage").Shared.Layout)
local Display = require(game:GetService("ReplicatedStorage").Shared.Display)

local DT = 0.1

local function newState(now)
	return Match.New(1, Random.new(11), now or 0, Dice.Deck)
end

local function place(state, cell, typeId, pip)
	Board.Summon(state.board, cell, typeId, state.nextDieId)
	state.nextDieId += 1
	state.board[cell].pip = pip or 1
end

-- An Active wave that never spawns or clears on its own (one queued enemy whose
-- spawn time is never reached), so a spec controls the enemies by hand.
local function openWave(state)
	state.wave = 1
	state.waveState = "Active"
	state.queue = { "Grunt" }
	state.qi = 1
	state.nextSpawnAt = math.huge
end

local function addEnemy(state, kind, hp, dist)
	local speed = Enemies.Kinds[kind].speed
	local enemy = {
		id = state.nextEnemyId,
		kind = kind,
		hp = hp,
		maxHp = hp,
		speed = speed,
		spawnAt = state.lastNow - dist / speed,
		dist = dist,
	}
	state.nextEnemyId += 1
	table.insert(state.enemies, enemy)
	return enemy
end

local function runFor(state, seconds)
	local t = state.lastNow
	for _ = 1, math.floor(seconds / DT + 0.5) do
		t += DT
		Match.Step(state, t)
	end
end

test("wave formulas", function()
	expectEq(Formulas.WaveCount(1), 8, "wave 1 count")
	expectEq(Formulas.WaveCount(10), 11, "wave 10 count")
	expectEq(Formulas.WaveCount(200), 45, "count cap")
	expectNear(Formulas.SpawnInterval(1), 1.593, 1e-9, "interval 1")
	expectNear(Formulas.SpawnInterval(10), 1.53, 1e-9, "interval 10")
	expectEq(Formulas.SpawnInterval(1000), 0.35, "interval floor")
	expectEq(Formulas.SpeedMul(1), 1, "speed 1")
	expectNear(Formulas.SpeedMul(10), 1.054, 1e-9, "speed 10")
	expectEq(Formulas.SpeedMul(500), 1.6, "speed cap")
	expectEq(Formulas.EnemyHp("Grunt", 1), 80, "grunt hp 1")
	expectEq(Formulas.EnemyHp("Runner", 1), 56, "runner hp 1")
	expectEq(Formulas.EnemyHp("Brute", 5), 257, "brute hp 5")
	expectEq(Formulas.EnemyHp("Boss", 10), 1116, "boss hp 10")
	expectEq(Formulas.Stipend(1), 30, "stipend 1")
	expectEq(Formulas.Stipend(9), 30, "stipend 9")
	expectEq(Formulas.Stipend(10), 35, "stipend 10")
	expectEq(Formulas.RewardGold(0), 50, "reward 0")
	expectEq(Formulas.RewardGold(10), 80, "reward 10")
end)

test("composition: Brute from wave 5 every 5th, Runner from wave 3 every 3rd", function()
	expectEq(Formulas.KindAt(1, 3), "Grunt", "w1 i3")
	expectEq(Formulas.KindAt(1, 5), "Grunt", "w1 i5")
	expectEq(Formulas.KindAt(3, 3), "Runner", "w3 i3")
	expectEq(Formulas.KindAt(3, 5), "Grunt", "w3 i5")
	expectEq(Formulas.KindAt(4, 5), "Grunt", "w4 i5")
	expectEq(Formulas.KindAt(5, 5), "Brute", "w5 i5")
	expectEq(Formulas.KindAt(5, 15), "Brute", "brute beats runner at i15")
	expectEq(Formulas.KindAt(5, 6), "Runner", "w5 i6")
	expectEq(Formulas.KindAt(5, 7), "Grunt", "w5 i7")
end)

test("perk damage: hitDamage = max(1, floor(base * pip^0.85 * perk)) plus flat", function()
	expectEq(Formulas.HitDamage("C01", 1, "Grunt"), 16, "pebble vs grunt")
	expectEq(Formulas.HitDamage("C01", 3, "Grunt"), 42, "pebble pip 3 vs grunt (x1.05)")
	expectEq(Formulas.HitDamage("C01", 3, "Runner"), 40, "pebble pip 3 vs runner (no perk)")
	expectEq(Formulas.HitDamage("C03", 1, "Brute"), 33, "hammer vs armored x1.12")
	expectEq(Formulas.HitDamage("C03", 1, "Grunt"), 30, "hammer vs grunt")
	expectEq(Formulas.HitDamage("C03", 1, "Boss"), 30, "boss is not armored")
	expectEq(Formulas.HitDamage("C05", 1, "Boss"), 19, "longshot x0.9 vs boss")
	expectEq(Formulas.HitDamage("C05", 1, "Grunt"), 22, "longshot vs grunt")
	expectEq(Formulas.HitDamage("C04", 1, "Grunt"), 7, "twinshot shot x0.7")
	expectEq(Formulas.HitDamage("C02", 1, "Grunt"), 9, "needle plain")
	expectEq(Formulas.HitDamage("C02", 1, "Grunt", 8), 17, "needle with proc")
	expectEq(Formulas.HitDamage("C04", 1, "Grunt") >= 1, true, "never below 1")
end)

test("layout: path length, clamped PositionAt, constant Y, camera, cell grid", function()
	expect(Layout.PathLength >= 110 and Layout.PathLength <= 150, "path length " .. Layout.PathLength)
	local crossing = Layout.PathLength / Enemies.Kinds.Grunt.speed
	expect(crossing >= 18 and crossing <= 25, "grunt crossing ~20 s: " .. crossing)
	expect(Layout.PositionAt(-5) == Layout.Waypoints[1], "clamped below")
	expect(Layout.PositionAt(0) == Layout.Waypoints[1], "start")
	expect(Layout.PositionAt(Layout.PathLength) == Layout.Waypoints[#Layout.Waypoints], "end")
	expect(Layout.PositionAt(1e9) == Layout.Waypoints[#Layout.Waypoints], "clamped above")
	for d = 0, Layout.PathLength, 3 do
		expectEq(Layout.PositionAt(d).Y, Layout.Y, "constant Y at " .. d)
	end
	local a, b = Layout.PositionAt(40), Layout.PositionAt(41)
	expectNear((b - a).Magnitude, 1, 1e-6, "unit speed along a segment")
	expect(Layout.Camera.Position ~= nil and Layout.Camera.LookAt ~= nil, "camera")
	expectEq(Balance.BoardCells, Layout.COLS * Layout.ROWS, "board size matches layout")
	expect(Layout.CellPosition(1).X < Layout.CellPosition(5).X, "row-major columns")
	expect(Layout.CellPosition(1).Z < Layout.CellPosition(11).Z, "row-major rows")
	expectEq(Layout.CellPosition(8).X, 0, "centre cell on the origin")
	expectEq(Layout.CellPosition(8).Z, 0, "centre cell on the origin")
end)

test("display data covers every die and enemy; pip 7 shows as 7 star", function()
	for _, id in { "C01", "C02", "C03", "C04", "C05" } do
		expect(Display.Dice[id] ~= nil and Display.Dice[id].Name ~= nil, "dice " .. id)
	end
	for kind in Enemies.Kinds do
		expect(Display.Enemies[kind] ~= nil, "enemy " .. kind)
	end
	expectEq(Display.PipLabel(3), "3", "pip 3")
	expectEq(Display.PipLabel(6), "6", "pip 6")
	expectEq(Display.PipLabel(7), "7\u{2605}", "pip 7")
end)

test("first wave starts 4 s after Start and spawns on schedule", function()
	local state = newState(100)
	expectEq(state.nextWaveAt, 104, "first wave at +4")
	runFor(state, 3.5)
	expectEq(state.wave, 0, "not yet")
	runFor(state, 1)
	expectEq(state.wave, 1, "wave 1 started")
	expectEq(state.waveState, "Active", "active")
	expectEq(#state.queue, 8, "8 spawns queued")
	expectEq(#state.enemies >= 1, true, "first enemy out")
	local batch = Match.TakeOut(state)
	expectEq(batch.S[1].Kind, "Grunt", "spawn record kind")
	expectEq(batch.S[1].Hp, 80, "spawn record hp")
	expectEq(batch.S[1].Speed, 6, "wave 1 speed")
	local again = Match.TakeOut(state)
	expectEq(#again.S, 0, "outbox drained")
end)

test("breach costs a life, loss at 0, no reward state change by Match", function()
	local state = newState()
	openWave(state)
	addEnemy(state, "Grunt", 80, Layout.PathLength - 0.1)
	runFor(state, 0.3)
	expectEq(state.lives, 19, "grunt breach -1")
	expectEq(#state.enemies, 0, "removed")
	local batch = Match.TakeOut(state)
	expectEq(batch.R[1].Why, "Breach", "breach record")

	local boss = newState()
	openWave(boss)
	addEnemy(boss, "Boss", 1116, Layout.PathLength - 0.1)
	runFor(boss, 0.5)
	expectEq(boss.lives, 15, "boss breach -5")

	local dying = newState()
	dying.lives = 1
	openWave(dying)
	addEnemy(dying, "Grunt", 80, Layout.PathLength - 0.1)
	runFor(dying, 0.3)
	expectEq(dying.phase, "Ended", "ended")
	expectEq(dying.result, "Lost", "lost")
	expectEq(dying.lives, 0, "lives floor at 0")
	expectEq(dying.rewardGranted, false, "Match never grants")
	local before = dying.lastNow
	Match.Step(dying, before + 5)
	expectEq(dying.lastNow, before, "no stepping after the end")
end)

test("an undefended run is lost after the breaches add up", function()
	local state = newState()
	runFor(state, 600)
	expectEq(state.phase, "Ended", "ended")
	expectEq(state.result, "Lost", "lost")
	expectEq(state.lives, 0, "lives 0")
	expectEq(state.wavesCompleted, 2, "two waves cleared by breaching before the third finished the run")
end)

test("kill MP: Grunt 15, Runner 15, Brute 25, Boss 150", function()
	for kind, expected in { Grunt = 15, Runner = 15, Brute = 25, Boss = 150 } do
		local state = newState()
		state.mp = 0
		openWave(state)
		place(state, 5, "C03", 7) -- Hammer pip 7: one-shots any 1 hp target
		local enemy = addEnemy(state, kind, 1, 55)
		runFor(state, 2)
		expect(enemy.hp <= 0, kind .. " died")
		expectEq(state.mp, expected, kind .. " kill mp")
		local batch = Match.TakeOut(state)
		local why
		for _, r in batch.R do
			if r.Id == enemy.id then
				why = r.Why
			end
		end
		expectEq(why, "Kill", kind .. " removal reason")
	end
end)

test("Global First: the alive enemy closest to the exit is hit, wherever it is", function()
	local state = newState()
	openWave(state)
	place(state, 1, "C01", 1) -- cell 1 at (-12, -6), far from the enemies below
	local back = addEnemy(state, "Brute", 5000, 50)
	local front = addEnemy(state, "Brute", 5000, 100) -- (22, 19): ~40 studs from the die
	local mid = addEnemy(state, "Brute", 5000, 56)
	runFor(state, 0.2)
	expect(front.hp < front.maxHp, "closest to the exit was hit despite distance")
	expectEq(back.hp, back.maxHp, "back untouched")
	expectEq(mid.hp, mid.maxHp, "middle untouched")
	local batch = Match.TakeOut(state)
	expect(#batch.F >= 1 and batch.F[1].Cell == 1 and batch.F[1].Id == front.id, "tracer record")
	expect(#batch.H >= 1 and batch.H[1].Id == front.id, "hp record")
end)

test("Needle: every 6th hit of that die adds 8 flat damage", function()
	local state = newState()
	openWave(state)
	place(state, 5, "C02", 1)
	local target = addEnemy(state, "Brute", 100000, 50)
	local deltas, last, t = {}, target.hp, state.lastNow
	for _ = 1, 80 do
		t += DT
		Match.Step(state, t)
		if target.hp ~= last then
			table.insert(deltas, last - target.hp)
			last = target.hp
		end
	end
	expect(#deltas >= 12, "enough hits: " .. #deltas)
	for i, d in deltas do
		expectEq(d, if i % 6 == 0 then 17 else 9, "hit " .. i)
	end
end)

test("Twinshot: two shots at x0.7; second goes to the next in First order, else the same target", function()
	local solo = newState()
	openWave(solo)
	place(solo, 5, "C04", 1)
	local only = addEnemy(solo, "Brute", 5000, 56)
	runFor(solo, 0.2)
	expectEq(only.maxHp - only.hp, 14, "both shots on the only target")

	local pair = newState()
	openWave(pair)
	place(pair, 5, "C04", 1)
	local front = addEnemy(pair, "Brute", 5000, 56)
	local back = addEnemy(pair, "Brute", 5000, 50)
	runFor(pair, 0.2)
	expectEq(front.maxHp - front.hp, 7, "first target takes one shot")
	expectEq(back.maxHp - back.hp, 7, "second shot goes to the next in order")
end)

test("cooldown does not bank while idle, and a die fires at most twice per tick", function()
	local state = newState()
	openWave(state)
	place(state, 5, "C02", 1)
	runFor(state, 5) -- idle for 5 s with nothing to shoot
	local target = addEnemy(state, "Brute", 100000, 56)
	local hp0 = target.hp
	Match.Step(state, state.lastNow + DT)
	expect(hp0 - target.hp <= 17, "idle time did not bank a burst")
end)

test("a summoned die lands exactly one hit in its first tick", function()
	local state = newState(100)
	openWave(state)
	state.lastNow = 100
	Match.Step(state, 100.1) -- long-running: clock well past 0
	expect(Match.TrySummon(state), "summon")
	local die
	for _, d in state.board do
		die = die or d or nil
	end
	addEnemy(state, "Brute", 100000, 50)
	Match.Step(state, state.lastNow + DT)
	expectEq(die.hits, 1, "one hit, no catch-up from cd = 0")
end)

test("stipend after each cleared wave; boss warning of at least 3 s; boss spawns first", function()
	local state = newState()
	for cell = 1, 15 do
		place(state, cell, if cell % 2 == 0 then "C03" else "C05", 7)
	end
	state.mp = 0
	local mpAfterWave1
	local bossAtSeen, bossSeenAt
	local bossFirst = nil
	local t = 0
	for _ = 1, 30000 do
		if state.phase ~= "Playing" then
			break
		end
		t += DT
		Match.Step(state, t)
		if state.bossAt ~= nil and bossAtSeen == nil then
			bossAtSeen, bossSeenAt = state.bossAt, t
		end
		local batch = Match.TakeOut(state)
		if state.wave == 10 and bossFirst == nil and #batch.S > 0 then
			bossFirst = batch.S[1].Kind
		end
		if state.wavesCompleted == 1 and mpAfterWave1 == nil then
			mpAfterWave1 = state.mp
		end
	end
	expectEq(state.phase, "Ended", "ended")
	expectEq(state.result, "Won", "scripted win")
	expectEq(state.wavesCompleted, 10, "ten waves cleared")
	expectEq(state.lives, 20, "no breaches")
	expect(bossAtSeen ~= nil, "boss warning was set")
	expect(bossAtSeen - bossSeenAt >= 3, "warning lead " .. tostring(bossAtSeen and bossAtSeen - bossSeenAt))
	expectEq(state.bossAt, nil, "warning cleared when the wave started")
	expectEq(bossFirst, "Boss", "boss spawns first in wave 10")
	expect(
		mpAfterWave1 ~= nil and mpAfterWave1 >= 30 + 8 * 15,
		"wave 1: 8 kills x15 + stipend 30: " .. tostring(mpAfterWave1)
	)
end)

test("max 90 alive: spawns wait and are never dropped", function()
	local state = newState()
	state.wave = 1
	state.waveState = "Active"
	state.queue = { "Grunt", "Grunt", "Grunt" }
	state.qi = 1
	state.nextSpawnAt = 0
	for _ = 1, Balance.MaxAlive do
		addEnemy(state, "Brute", 1e9, 0).spawnAt = state.lastNow
	end
	runFor(state, 2)
	expectEq(#state.enemies, 90, "capped")
	expectEq(state.qi, 1, "nothing consumed from the queue")
	state.enemies = {}
	runFor(state, 0.5)
	expect(state.qi > 1 and #state.enemies >= 1, "spawns resume")
	runFor(state, 10)
	expectEq(state.qi, 4, "every queued enemy eventually spawned")
end)

test("Finish ends once with a valid result; Ended match ignores intents", function()
	local state = newState()
	expect(not Match.Finish(state, "Nope"), "invalid result")
	expect(Match.Finish(state, "Aborted"), "abort")
	expectEq(state.result, "Aborted", "result")
	expect(not Match.Finish(state, "Won"), "only once")
	expectEq(state.result, "Aborted", "result kept")
	local ok, code = Match.TrySummon(state)
	expect(not ok and code == "WrongPhase", "no summon after end")
end)

test("summons and merges draw only from the passed deck, which Match copies", function()
	local deck = { "C03", "C03", "C03", "C03", "C03" }
	local state = Match.New(1, Random.new(4), 0, deck)
	expect(state.deck ~= deck, "own copy")
	deck[1] = "C01" -- caller mutation must not leak in
	state.mp = 100000
	for _ = 1, 6 do
		state.mp = 100000
		expect(Match.TrySummon(state), "summon")
	end
	for _, die in state.board do
		if die then
			expectEq(die.type, "C03", "only the deck type")
		end
	end
	local cells = {}
	for i, die in state.board do
		if die then
			table.insert(cells, i)
		end
	end
	expect(Match.TryMerge(state, cells[1], cells[2]), "merge")
	expectEq(state.board[cells[2]].type, "C03", "merge result from the deck")
end)

test("kills count only deaths by damage, never breaches", function()
	local state = newState()
	openWave(state)
	place(state, 5, "C03", 7)
	addEnemy(state, "Grunt", 1, 55)
	addEnemy(state, "Grunt", 80, Layout.PathLength - 0.1)
	expectEq(state.kills, 0, "starts at 0")
	runFor(state, 2)
	expectEq(state.kills, 1, "one kill, one breach")
	expectEq(state.lives, 19, "the breach still cost a life")
end)
