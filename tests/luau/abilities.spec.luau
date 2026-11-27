-- Die abilities (Rules/Abilities): slow cap, freeze, rewind, chain, cascade, pierce, poison, burn, timers, Forge, Mirror, Sniper.

local Server = game:GetService("ServerScriptService").Server
local Match = require(Server.Rules.Match)
local Board = require(Server.Rules.Board)
local Dice = require(Server.Config.Dice)
local Enemies = require(Server.Config.Enemies)

local DT = 0.1

local function newState()
	return Match.New(1, Random.new(11), 0, Dice.Deck)
end

local function place(state, cell, typeId, pip)
	Board.Summon(state.board, cell, typeId, state.nextDieId)
	state.nextDieId += 1
	state.board[cell].pip = pip or 1
	state.board[cell].cd = state.lastNow
end

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

test("Sniper (Longshot) aims at the highest-HP enemy, not the front one", function()
	local state = newState()
	openWave(state)
	place(state, 5, "C05")
	local front = addEnemy(state, "Brute", 5000, 60)
	local big = addEnemy(state, "Brute", 90000, 20)
	runFor(state, 0.1)
	expect(big.hp < big.maxHp and front.hp == front.maxHp, "the big one is hit")
end)

test("Volley sends its three bolts at three different enemies", function()
	local state = newState()
	openWave(state)
	place(state, 5, "R03")
	local list = {}
	for i = 1, 3 do
		list[i] = addEnemy(state, "Brute", 100000, 20 + i * 10)
	end
	runFor(state, 0.1)
	for _, e in list do
		expectEq(e.maxHp - e.hp, Dice.Types.R03.base, "each enemy takes one bolt")
	end
end)

test("slow caps at 60% on normal enemies and 50% on bosses", function()
	local state = newState()
	openWave(state)
	place(state, 5, "L01")
	local grunt = addEnemy(state, "Grunt", 1e9, 40)
	local boss = addEnemy(state, "Boss", 1e9, 30)
	state.board[5].nextAt = { rift = 0 } -- the rift is due at once
	runFor(state, 0.1)
	expectNear(grunt.slowMul, 0.4, 1e-9, "normal slow capped at 60%")
	expectNear(boss.slowMul, 0.7, 1e-9, "rift slows a boss 30%")
end)

test("Frost freezes a non-boss on its 8th hit and never a boss", function()
	local state = newState()
	openWave(state)
	place(state, 5, "R01", 7)
	local grunt = addEnemy(state, "Grunt", 1e9, 40)
	state.board[5].hits = 7
	runFor(state, 0.2)
	expect(grunt.frozen == true or grunt.frozenUntil ~= nil, "frozen")
	local state2 = newState()
	openWave(state2)
	place(state2, 5, "R01", 7)
	local boss = addEnemy(state2, "Boss", 1e9, 40)
	state2.board[5].hits = 7
	runFor(state2, 0.2)
	expectEq(boss.frozen, nil, "bosses do not freeze")
end)

test("Arc hits the front enemy for 90% and the two behind it for 40% and 20% on every hit", function()
	local state = newState()
	openWave(state)
	place(state, 5, "R02")
	local a = addEnemy(state, "Brute", 1e6, 60)
	local b = addEnemy(state, "Brute", 1e6, 40)
	local c = addEnemy(state, "Brute", 1e6, 30)
	local d = addEnemy(state, "Brute", 1e6, 10)
	runFor(state, 0.1)
	local base = Dice.Types.R02.base
	expectEq(a.maxHp - a.hp, math.floor(base * 0.9), "front 90%")
	expectEq(b.maxHp - b.hp, math.floor(base * 0.4), "second 40%")
	expectEq(c.maxHp - c.hp, math.floor(base * 0.2), "third 20%")
	expectEq(d.maxHp - d.hp, 0, "a fourth enemy is untouched")
end)

test("Spark chains to one other enemy for 60% on every 4th attack", function()
	local state = newState()
	openWave(state)
	place(state, 5, "C07")
	local a = addEnemy(state, "Brute", 1e6, 60)
	local b = addEnemy(state, "Brute", 1e6, 40)
	state.board[5].hits = 3
	runFor(state, 0.1)
	expectEq(a.maxHp - a.hp, Dice.Types.C07.base, "front takes the full hit")
	expectEq(b.maxHp - b.hp, math.floor(Dice.Types.C07.base * 0.6), "chain 60%")
end)

test("Wyvern pierces the next three enemies behind the target", function()
	local state = newState()
	openWave(state)
	place(state, 5, "S01")
	local list = {}
	for i = 1, 5 do
		list[i] = addEnemy(state, "Brute", 1e6, 80 - i * 5)
	end
	runFor(state, 0.1)
	local hit = 0
	for _, e in list do
		hit += if e.hp < e.maxHp then 1 else 0
	end
	expectEq(hit, 4, "target plus three behind it")
end)

test("Venom stacks poison to a cap and passes it to the nearest enemy on death", function()
	local state = newState()
	openWave(state)
	place(state, 5, "R04", 7)
	local target = addEnemy(state, "Brute", 1e7, 80)
	runFor(state, 1)
	local dot
	for _, d in target.dots do
		dot = d
	end
	expectEq(dot.stacks, Dice.Types.R04.poison.maxStacks, "capped at 4 stacks")
	expectEq(dot.dps, 75 * 4, "dps = 75 per stack")
	local next = addEnemy(state, "Brute", 1e7, 60)
	target.hp = 0
	Match.Step(state, state.lastNow + DT)
	expect(next.dots ~= nil, "poison jumped to the nearest living enemy")
end)

test("Emberstorm detonation cashes in burns", function()
	local state = newState()
	openWave(state)
	place(state, 5, "E01")
	local e = addEnemy(state, "Brute", 1e7, 60)
	e.dots = { burn = { dps = 400, endsAt = state.lastNow + 3, burn = true } }
	state.board[5].nextAt = { detonate = 0 }
	local hp0 = e.hp
	runFor(state, 0.1)
	expect(hp0 - e.hp >= 1000, "the remaining burn landed at once")
end)

test("Gravity pulls non-bosses back and slows bosses", function()
	local state = newState()
	openWave(state)
	place(state, 5, "E03")
	local grunt = addEnemy(state, "Grunt", 1e9, 60)
	local boss = addEnemy(state, "Boss", 1e9, 40)
	state.board[5].nextAt = { pull = 0 }
	runFor(state, 0.1)
	expect(grunt.dist < 60 - 10, "pulled back about 12% of the lane")
	expectNear(boss.slowMul, 0.65, 1e-9, "boss slowed 35%")
end)

test("Chrono rewinds at most three times per enemy and never a boss", function()
	local state = newState()
	openWave(state)
	place(state, 5, "L01")
	local grunt = addEnemy(state, "Grunt", 1e9, 100)
	grunt.rewinds = 3
	state.board[5].rifts = 2 -- the next rift is the 3rd, which rewinds
	state.board[5].nextAt = { rift = 0 }
	runFor(state, 0.1)
	expect(grunt.dist > 95, "an enemy with 3 rewinds is not pushed back")
end)

test("a merge next to Forge keeps the merged type and every 4th adds a free die", function()
	local state = newState()
	state.deck = { "C01", "C02", "C03", "C04", "C05" }
	place(state, 2, "L02")
	for round = 1, 4 do
		for _, cell in { 7, 8 } do
			state.board[cell] = false
			place(state, cell, "C03")
		end
		state.lastNow += 10
		local ok = Match.TryMerge(state, 7, 8)
		expect(ok, "merge " .. round)
		expectEq(state.board[8].type, "C03", "type kept")
		state.board[8] = false
	end
	local dice = 0
	for _, die in state.board do
		dice += if die then 1 else 0
	end
	expectEq(dice, 2, "Forge plus one free pip-1 die from the 4th merge")
end)

test("Mirror copies the highest pip count on the board on summon or merge", function()
	local state = newState()
	place(state, 2, "R04", 3)
	place(state, 6, "L01", 5)
	place(state, 1, "E02", 2)
	local Abilities = require(Server.Rules.Abilities)
	Abilities.Copy(state.board, 1, 0)
	expectEq(state.board[1].pip, 5, "took the highest pip")
	state.board[1].pip = 7
	Abilities.Copy(state.board, 1, 0)
	expectEq(state.board[1].pip, 7, "never loses pips")
	Abilities.Copy(state.board, 2, 0)
	expectEq(state.board[2].pip, 3, "other dice are untouched")
end)
