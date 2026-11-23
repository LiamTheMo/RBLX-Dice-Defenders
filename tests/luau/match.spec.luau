-- Formulas, breach/loss, boss warning, kill MP, perk damage, First
-- targeting, layout geometry, and a scripted endless run.

local Server = game:GetService("ServerScriptService").Server
local Match = require(Server.Rules.Match)
local Board = require(Server.Rules.Board)
local Formulas = require(Server.Rules.Formulas)
local Balance = require(Server.Config.Balance)
local CoopWaves = require(Server.Config.CoopWaves)
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
	state.queue = { { kind = "Grunt", hp = 20 } }
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
	expectEq(Formulas.EnemyHp("Grunt", 1), 110, "grunt hp 1")
	expectEq(Formulas.EnemyHp("Grunt", 10), 506, "grunt hp 10")
	expectEq(Formulas.EnemyHp("Grunt", 11), 637, "grunt hp 11: the steep band starts")
	expectEq(Formulas.EnemyHp("Grunt", 15), 1606, "grunt hp 15")
	expectEq(Formulas.EnemyHp("Grunt", 16), 1718, "grunt hp 16: the gentle band")
	expectEq(Formulas.EnemyHp("Runner", 1), 55, "runner 0.5x")
	expectEq(Formulas.EnemyHp("Brute", 1), 220, "brute 2x")
	expectEq(Formulas.EnemyHp("Boss", 5), 3064, "boss hp 5: 8.5x")
	expectEq(Formulas.EnemyHp("Boss", 10), 4297, "boss hp 10")
	expectEq(Formulas.EnemyHp("Boss", 15), 13648, "boss hp 15")
	expectEq(Formulas.RewardGold(0), 0, "reward 0")
	expectEq(Formulas.RewardGold(10), 50, "reward 10: no win bonus")
	expectEq(Formulas.RewardXp(10), 100, "xp 10")
	expectEq(Formulas.RewardFragments(10), 10, "fragments 10")
	local gems = {}
	for w = 1, 10 do
		gems[w] = Formulas.WaveGems(w)
	end
	expectEq(table.concat(gems, ","), "1,1,2,1,3,1,1,2,1,3", "gems: Random Dice's 1,1,2,1,3 cycle (Brute 2, Boss 3)")
	expectEq(Formulas.RewardGems(0), 0, "gems 0")
	expectEq(Formulas.RewardGems(15), 24, "gems 15")
	expectEq(Formulas.WaveGems(45), 3, "gems 45: last of the first band")
	expectEq(Formulas.WaveGems(46), 6, "gems 46: Brute wave, second band")
	expectEq(Formulas.WaveGems(47), 2, "gems 47: plain wave, second band")
	expectEq(Formulas.WaveGems(50), 6, "gems 50: Boss wave, second band")
end)

test("composition: Runner from wave 3 every 3rd; Brute and Boss schedules", function()
	expectEq(Formulas.KindAt(1, 3), "Grunt", "w1 i3")
	expectEq(Formulas.KindAt(3, 3), "Runner", "w3 i3")
	expectEq(Formulas.KindAt(3, 5), "Grunt", "w3 i5")
	expectEq(Formulas.KindAt(5, 5), "Grunt", "no Brute in the spawn index")
	expectEq(Formulas.KindAt(5, 15), "Runner", "w5 i15")
	expectEq(Formulas.KindAt(5, 7), "Grunt", "w5 i7")
	for w = 1, 40 do
		expectEq(Formulas.IsBoss(w), w % 5 == 0, "boss " .. w)
	end
	local brutes = {}
	for w = 1, 40 do
		if Formulas.HasBrute(w) then
			table.insert(brutes, w)
		end
	end
	expectEq(table.concat(brutes, ","), "3,8,13,18,23,28,33,36,38,40", "brute waves")
end)

test("perk damage: hitDamage = max(1, floor(base * perk * tierMul)) plus flat, no pip term", function()
	expectEq(Formulas.HitDamage("C01", "Grunt"), 16, "pebble vs grunt (x1.05)")
	expectEq(Formulas.HitDamage("C01", "Runner"), 16, "pebble vs runner (no perk)")
	expectEq(Formulas.HitDamage("C03", "Brute"), 33, "hammer vs armored x1.12")
	expectEq(Formulas.HitDamage("C03", "Grunt"), 30, "hammer vs grunt")
	expectEq(Formulas.HitDamage("C03", "Boss"), 30, "boss is not armored")
	expectEq(Formulas.HitDamage("C05", "Boss"), 19, "longshot x0.9 vs boss")
	expectEq(Formulas.HitDamage("C05", "Grunt"), 22, "longshot vs grunt")
	expectEq(Formulas.HitDamage("C04", "Grunt"), 6, "Twinshot base damage per projectile")
	expectEq(Formulas.HitDamage("C02", "Grunt"), 9, "needle plain")
	expectEq(Formulas.HitDamage("C02", "Grunt", 8), 17, "needle with proc")
	expectEq(Formulas.HitDamage("C04", "Grunt") >= 1, true, "never below 1")
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
	local real = 0
	for i = 2, #Layout.Waypoints do
		real += (Layout.Waypoints[i] - Layout.Waypoints[i - 1]).Magnitude
	end
	expectNear(
		(b - a).Magnitude,
		real / Layout.PathLength,
		1e-6,
		"constant speed along a segment (real route onto balance studs)"
	)
	expectEq(
		Layout.PositionAt(Layout.CoopJunction, 1, 2),
		Layout.PositionAt(Layout.CoopJunction, 2, 2),
		"co-op lanes meet at the junction"
	)
	expect(Layout.PositionAt(0, 1, 2) ~= Layout.PositionAt(0, 2, 2), "co-op lanes start apart")
	expect(Layout.Camera.Position ~= nil and Layout.Camera.LookAt ~= nil, "camera")
	expectEq(Balance.BoardCells, Layout.COLS * Layout.ROWS, "board size matches layout")
	expect(Layout.CellPosition(1).X < Layout.CellPosition(5).X, "row-major columns")
	expect(Layout.CellPosition(1).Z < Layout.CellPosition(11).Z, "row-major rows")
	expectEq(Layout.CellPosition(8).X, Layout.ORIGIN.X, "centre cell on the arena origin")
	expectEq(Layout.CellPosition(8).Z, Layout.ORIGIN.Z, "centre cell on the arena origin")
	for _, point in Layout.Waypoints do
		expect(point.X >= 500, "arena clear of the lobby map")
	end
end)

test("layout: duel arena (two boards, two U routes, 124-stud scaling, pads match the model)", function()
	local O = Layout.DUEL_ORIGIN
	expectEq(Layout.ArenaOf(1), "Solo", "legacy 1")
	expectEq(Layout.ArenaOf(2), "Coop", "legacy 2")
	expectEq(Layout.ArenaOf("Duel"), "Duel", "duel key")
	expect(Layout.PositionAt(0, 1, "Duel") ~= Layout.PositionAt(0, 2, "Duel"), "duel seats start apart")
	expect(
		Layout.PositionAt(Layout.PathLength, 1, "Duel") ~= Layout.PositionAt(Layout.PathLength, 2, "Duel"),
		"duel seats end apart"
	)
	for seat = 1, 2 do
		local points = Layout.Path(seat, "Duel")
		expectEq(Layout.PositionAt(-5, seat, "Duel"), points[1], "clamped below")
		expectEq(Layout.PositionAt(1e9, seat, "Duel"), points[#points], "clamped above")
		expectEq(Layout.PositionAt(Layout.PathLength, seat, "Duel"), points[#points], "end")
		for d = 0, Layout.PathLength, 3 do
			expectEq(Layout.PositionAt(d, seat, "Duel").Y, Layout.Y, "constant Y at " .. d)
		end
		local real = 0
		for i = 2, #points do
			real += (points[i] - points[i - 1]).Magnitude
		end
		local a, b = Layout.PositionAt(40, seat, "Duel"), Layout.PositionAt(41, seat, "Duel")
		expectNear((b - a).Magnitude, real / Layout.PathLength, 1e-6, "constant speed on the first leg")
	end
	-- Numbers measured from ReplicatedStorage.Maps.Duel (centre x 5400): route corners and pad centres.
	expectNear((Layout.Path(1, "Duel")[1] - O).X, -18.65, 1e-6, "seat 1 start x")
	expectNear((Layout.Path(1, "Duel")[1] - O).Z, -20.55, 1e-6, "seat 1 start z")
	expectNear((Layout.Path(1, "Duel")[2] - O).Z, -2.9, 1e-6, "seat 1 bottom z")
	expectNear((Layout.Path(2, "Duel")[4] - O).X, 18.65, 1e-6, "seat 2 end x")
	expectNear((Layout.Path(2, "Duel")[4] - O).Z, 20.55, 1e-6, "seat 2 end z")
	local padRows = { { -20.5, -14.5, -8.5 }, { 8.5, 14.5, 20.5 } }
	for seat = 1, 2 do
		for cell = 1, 15 do
			local c = Layout.CellPosition(cell, seat, "Duel") - O
			expectNear(c.X, (((cell - 1) % 5) - 2) * 6, 1e-6, "pad x seat " .. seat .. " cell " .. cell)
			expectNear(c.Z, padRows[seat][(cell - 1) // 5 + 1], 1e-6, "pad z seat " .. seat .. " cell " .. cell)
			expectEq(c.Y, Layout.Y, "pad Y")
		end
	end
	expectEq(Layout.CellPosition(1, 1, 2), Layout.CellPosition(1, 1, "Coop"), "numeric key = name")
	expect(Layout.DuelCamera(1).Position.Z < Layout.DuelCamera(1).LookAt.Z, "seat 1 camera on -z looks toward +z")
	expect(Layout.DuelCamera(2).Position.Z > Layout.DuelCamera(2).LookAt.Z, "seat 2 camera on +z looks toward -z")
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
	expectEq(#state.queue, 10, "10 spawns queued")
	expectEq(#state.enemies >= 1, true, "first enemy out")
	local batch = Match.TakeOut(state)
	expectEq(batch.S[1].Kind, "Grunt", "spawn record kind")
	expectEq(batch.S[1].Hp, 20, "spawn record hp")
	expectEq(batch.S[1].Speed, 6, "wave 1 speed")
	local again = Match.TakeOut(state)
	expectEq(#again.S, 0, "outbox drained")
end)

test("breach costs the kind's lives, loss at 0, no reward state change by Match", function()
	expectEq(Balance.StartLives, 3, "start lives")
	local state = newState()
	expectEq(state.lives, Balance.StartLives, "fresh match lives = snapshot MaxLives")
	openWave(state)
	addEnemy(state, "Grunt", 80, Layout.PathLength - 0.1)
	runFor(state, 0.3)
	expectEq(state.lives, 2, "grunt breach -1")
	expectEq(#state.enemies, 0, "removed")
	local batch = Match.TakeOut(state)
	expectEq(batch.R[1].Why, "Breach", "breach record")

	for kind, cost in { Brute = 2, Boss = 2 } do
		local s = newState()
		openWave(s)
		addEnemy(s, kind, 1000, Layout.PathLength - 0.1)
		runFor(s, 0.5)
		expectEq(s.lives, 3 - cost, kind .. " breach")
	end

	local dying = newState()
	dying.lives = 1
	openWave(dying)
	addEnemy(dying, "Grunt", 80, Layout.PathLength - 0.1)
	runFor(dying, 0.3)
	expectEq(dying.phase, "Ended", "ended")
	expectEq(dying.result, "Lost", "lost")
	expectEq(dying.lives, 0, "lives floor at 0")
	local brute = newState()
	brute.lives = 1
	openWave(brute)
	addEnemy(brute, "Brute", 1000, Layout.PathLength - 0.1)
	runFor(brute, 0.5)
	expect(brute.lives == 0 and brute.phase == "Ended" and brute.result == "Lost", "Brute breach at 1 life loses")
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
end)

test("kill MP bands and kind multipliers", function()
	local bands =
		{ [1] = 10, [5] = 10, [6] = 20, [10] = 20, [11] = 30, [15] = 30, [16] = 40, [20] = 40, [21] = 50, [99] = 50 }
	for w, band in bands do
		expectEq(Formulas.KillMp("Grunt", w), band, "grunt w" .. w)
		expectEq(Formulas.KillMp("Runner", w), band, "runner w" .. w)
		expectEq(Formulas.KillMp("Brute", w), band * 5, "brute w" .. w)
		expectEq(Formulas.KillMp("Boss", w), band * 10, "boss w" .. w)
	end
	for kind, expected in { Grunt = 10, Runner = 10, Brute = 50, Boss = 100 } do
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
		expectEq(batch.F[1].Type, "C03", "attack identifies the firing die")
		expectEq(batch.F[1].Distance, enemy.dist, "Hammer keeps the lethal impact position")
	end
end)

test("all Common dice report confirmed hits and the visual ability flags", function()
	for _, id in { "C01", "C02", "C03", "C04", "C05", "C06", "C07" } do
		local state = newState()
		openWave(state)
		place(state, 5, id, 1)
		local target = addEnemy(state, "Grunt", 1000, 1)
		local cfg = Dice.Types[id]
		state.board[5].hits = (cfg.procEvery or 1) - 1
		Match.Step(state, state.lastNow + DT)
		local batch = Match.TakeOut(state)
		expectEq(#batch.F, cfg.shots or 1, id .. " shot count")
		for _, shot in batch.F do
			expectEq(shot.Type, id, "effect identifier")
			expectEq(shot.Distance, target.dist, id .. " confirmed impact position")
			expectEq(shot.Boosted, if cfg.procEvery then true else nil, id .. " boosted impact")
			expectEq(shot.Slowed, if cfg.slow then true else nil, id .. " slow marker")
		end
	end
end)

test("Global First: the alive enemy closest to the exit is hit, wherever it is", function()
	local state = newState()
	openWave(state)
	place(state, 1, "C01", 1) -- cell 1 at (-12, -6), far from the enemies below
	local back = addEnemy(state, "Brute", 5000, 50)
	local front = addEnemy(state, "Brute", 5000, 100) -- (22, 19): ~40 studs from the die
	local mid = addEnemy(state, "Brute", 5000, 56)
	Match.Step(state, state.lastNow + DT)
	expect(front.hp < front.maxHp, "closest to the exit was hit despite distance")
	expectEq(back.hp, back.maxHp, "back untouched")
	expectEq(mid.hp, mid.maxHp, "middle untouched")
	local batch = Match.TakeOut(state)
	local shot = batch.F[1]
	expect(shot and shot.Cell == 1 and shot.Id == front.id and shot.Type == "C01", "Pebble attack record")
	expectEq(shot.Distance, front.dist, "confirmed impact distance")
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
		local batch = Match.TakeOut(state)
		if target.hp ~= last then
			table.insert(deltas, last - target.hp)
			expectEq(#batch.F, 1, "one visual event for the hit")
			local shot = batch.F[1]
			expectEq(shot.Type, "C02", "Needle attack record")
			expectEq(shot.Distance, target.dist, "confirmed impact distance")
			expectEq(shot.Boosted, if #deltas % 6 == 0 then true else nil, "only the sixth hit brightens")
			last = target.hp
		else
			expectEq(#batch.F, 0, "no attack effect without a hit")
		end
	end
	expect(#deltas >= 12, "enough hits: " .. #deltas)
	for i, d in deltas do
		expectEq(d, if i % 6 == 0 then 17 else 9, "hit " .. i)
	end
end)

test("Twinshot targets the front and uniformly samples the living enemies", function()
	local solo = newState()
	openWave(solo)
	place(solo, 5, "C04", 1)
	local only = addEnemy(solo, "Brute", 6, 56)
	Match.Step(solo, solo.lastNow + DT)
	local batch = Match.TakeOut(solo)
	expectEq(#batch.F, 2, "both shots emitted when the first one is lethal")
	expectEq(#batch.R, 1, "kill counted once")
	for i, shot in batch.F do
		expectEq(shot.Id, only.id, "same target")
		expectEq(shot.Distance, only.dist, "confirmed impact distance")
		expectEq(shot.Lane, if i == 1 then 1 else -1, "separate visual lanes")
		expectEq(shot.SharedTarget, true, "shared target uses two impact offsets")
	end

	for roll = 1, 3 do
		local state = newState()
		openWave(state)
		place(state, 5, "C04", 1)
		local rear = addEnemy(state, "Brute", 5000, 40)
		addEnemy(state, "Brute", 0, 62)
		local front = addEnemy(state, "Brute", 5000, 56)
		local middle = addEnemy(state, "Brute", 5000, 50)
		local candidates = { rear, front, middle }
		state.rng = {
			NextInteger = function(_, min, max)
				expectEq(min, 1, "first living index")
				expectEq(max, #candidates, "includes every living enemy, skips the dead")
				return roll
			end,
		}
		Match.Step(state, state.lastNow + DT)
		local fired = Match.TakeOut(state).F
		expectEq(#fired, 2, "two actual attack records")
		expectEq(fired[1].Id, front.id, "first shot always targets the front")
		expectEq(fired[2].Id, candidates[roll].id, "second shot can select any living enemy")
		expectEq(fired[2].Distance, candidates[roll].dist, "random target impact distance")
		expectEq(fired[2].SharedTarget, if roll == 2 then true else nil, "only shared targets offset their impacts")
		for i, enemy in candidates do
			expectEq(enemy.maxHp - enemy.hp, (if enemy == front then 6 else 0) + (if i == roll then 6 else 0), "damage")
		end
	end
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

test("endless run warns before the wave 10 boss; historical waves use the shared queue", function()
	local state = newState()
	for cell = 1, 15 do
		place(state, cell, if cell % 2 == 0 then "C03" else "C05", 7)
	end
	state.mp = 0
	local warned = {} -- wave -> lead seconds
	local lastWarn
	local bossAtWave, bossSpawn = {}, {}
	local queues = {}
	local t = 0
	for _ = 1, 40000 do
		if state.phase ~= "Playing" or state.wave > 10 then
			break
		end
		t += DT
		Match.Step(state, t)
		if state.waveState == "Prep" and state.bossAt ~= nil and lastWarn ~= state.bossAt then
			lastWarn = state.bossAt
			warned[state.wave + 1] = state.bossAt - t
		end
		if state.waveState == "Active" and CoopWaves.IsBoss(state.wave) and bossAtWave[state.wave] == nil then
			bossAtWave[state.wave] = state.bossAt
		end
		for _, enemy in state.enemies do
			if enemy.kind == "Boss" and bossSpawn[state.wave] == nil then
				bossSpawn[state.wave] = enemy.spawnAt
			end
		end
		if state.waveState == "Active" and queues[state.wave] == nil then
			queues[state.wave] = table.clone(state.queue)
		end
		Match.TakeOut(state)
	end
	expectEq(state.phase, "Playing", "no win: the run goes on past wave 10")
	expectEq(state.result, nil, "no result")
	expect(state.wavesCompleted >= 10, "ten waves cleared")
	expectEq(state.wave, 11, "wave 11 started")
	expectEq(state.lives, 3, "no breaches")
	expectEq(warned[5], nil, "miniboss is not a boss wave")
	expect(warned[10] ~= nil and warned[10] >= 3, "warning before wave 10: " .. tostring(warned[10]))
	expectEq(warned[6], nil, "no warning before wave 6")
	for _, w in { 10 } do
		expect(
			bossAtWave[w] ~= nil and bossSpawn[w] ~= nil and math.abs(bossAtWave[w] - bossSpawn[w]) <= DT,
			"wave "
				.. w
				.. " bossAt is the Boss spawn time: "
				.. tostring(bossAtWave[w])
				.. " vs "
				.. tostring(bossSpawn[w])
		)
	end
	expectEq(#queues[3], 10, "ordinary wave size")
	expectEq(queues[5][1].kind, "Brute", "wave 5 first-slot miniboss")
	expectEq(queues[5][10].kind, "Runner", "wave 5 last-slot runner")
	expectEq(#queues[10], 1, "boss replaces the wave")
	expectEq(queues[10][1].hp, 8460, "wave 10 shared scaling")
end)

test("max 90 alive: spawns wait and are never dropped", function()
	local state = newState()
	state.wave = 1
	state.waveState = "Active"
	state.queue = table.create(3, { kind = "Grunt", hp = 20 })
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
	expect(not Match.Finish(state, "Lost"), "only once")
	expect(not Match.Finish(state, "Won"), "Won is no result")
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

test("a Rare/Epic/Legendary deck summons, merges and deals damage", function()
	local deck = { "R03", "E01", "L02", "R04", "E03" }
	local state = Match.New(1, Random.new(7), 0, deck)
	openWave(state)
	for _ = 1, Balance.BoardCells do
		state.mp = 100000
		expect(Match.TrySummon(state), "summon")
	end
	local from, to
	for a = 1, Balance.BoardCells do
		for b = a + 1, Balance.BoardCells do
			if from == nil and state.board[a].type == state.board[b].type then
				from, to = a, b
			end
		end
	end
	expect(from ~= nil, "15 dice of 5 types hold a same-type pair")
	expect(Match.TryMerge(state, from, to), "merge")
	expectEq(state.board[to].pip, 2, "merged pip")
	expect(table.find(deck, state.board[to].type) ~= nil, "merge result from the deck")
	local target = addEnemy(state, "Brute", 1e9, 50)
	runFor(state, 3)
	expect(target.hp < target.maxHp, "the board dealt damage")
	expectEq(state.phase, "Playing", "still playing")
end)

test("stat-only dice: one pip-1 hit deals exactly base, with no perk", function()
	for id, cfg in Dice.Types do
		if cfg.rarity ~= "Common" and not cfg.singularity then
			local state = newState()
			openWave(state)
			place(state, 5, id, 1)
			local brute = addEnemy(state, "Brute", 5000, 56)
			runFor(state, 0.1)
			expectEq(brute.maxHp - brute.hp, cfg.base, id .. " first hit")
		end
	end
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
	expectEq(state.lives, 2, "the breach still cost a life")
end)

test("Chill slows without stacking, then restores speed and reports movement", function()
	local state = newState()
	openWave(state)
	place(state, 1, "C06")
	local enemy = addEnemy(state, "Grunt", 10000, 0)
	runFor(state, 0.1)
	expectNear(enemy.speed, 6 * 0.85, 1e-8, "slow applied")
	local batch = Match.TakeOut(state)
	expectNear(batch.H[1].Speed, enemy.speed, 1e-8, "slow speed sent")
	runFor(state, 1)
	expectNear(enemy.speed, 6 * 0.85, 1e-8, "refresh does not stack")
	state.board[1] = nil
	runFor(state, 1.6)
	expectNear(enemy.speed, 6, 1e-8, "speed restored")
	batch = Match.TakeOut(state)
	expectNear(batch.H[1].Speed, 6, 1e-8, "restoration sent")
end)
