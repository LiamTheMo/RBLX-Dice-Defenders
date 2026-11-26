-- 1v1 Duel rules (docs/DICE_RATING.md section 4): same waves per lane, own lives/MP/targets, the end, forfeit.

local Server = game:GetService("ServerScriptService").Server
local Match = require(Server.Rules.Match)
local Board = require(Server.Rules.Board)
local Formulas = require(Server.Rules.Formulas)
local Balance = require(Server.Config.Balance)
local Dice = require(Server.Config.Dice)
local Enemies = require(Server.Config.Enemies)

local DT = 0.1

local function newDuel(seed)
	return Match.NewDuel(1, Random.new(seed or 5), 0, Dice.Deck, Dice.Deck)
end

local function place(seat, cell, typeId)
	Board.Summon(seat.board, cell, typeId, seat.nextDieId)
	seat.nextDieId += 1
end

-- An Active wave that never spawns or clears on its own, so a spec controls the enemies by hand.
local function openWave(state)
	state.wave = 1
	state.waveState = "Active"
	state.queue = { { kind = "Grunt", hp = 20 } }
	state.qi = 1
	state.nextSpawnAt = math.huge
end

local function addEnemy(state, seat, kind, hp, dist)
	local speed = Enemies.Kinds[kind].speed
	local enemy = {
		id = state.nextEnemyId,
		kind = kind,
		hp = hp,
		maxHp = hp,
		speed = speed,
		spawnAt = state.lastNow - dist / speed,
		dist = dist,
		seat = seat,
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

test("NewDuel makes two seats with own lives and no crit bonus", function()
	local state = Match.NewDuel(7, Random.new(1), 0, Dice.Deck, Dice.Deck)
	expectEq(state.mode, "Duel", "mode")
	expectEq(state.playerCount, 2, "two seats")
	expectEq(state.lives, Balance.StartLives, "seat one lives")
	expectEq(state.partner.lives, Balance.StartLives, "seat two lives")
	expectEq(state.critBonus, 0, "seat one crit")
	expectEq(state.partner.critBonus, 0, "seat two crit")
	expectEq(Match.Seat(state, 2), state.partner, "Seat(2)")
	expectEq(Balance.Duel.MaxWaves, nil, "no wave cap")
end)

test("a Duel ignores crit bonuses even if a caller passes them to Match.New", function()
	local state = newDuel()
	expectEq(state.critBonus + state.partner.critBonus, 0, "normalized")
	local solo = Match.New(1, Random.new(1), 0, Dice.Deck, nil, 40)
	expectEq(solo.critBonus, 40, "Solo keeps the player's crit bonus")
	expectEq(solo.mode, "Solo", "solo mode")
	local coop = Match.New(1, Random.new(1), 0, Dice.Deck, Dice.Deck, 10, 20)
	expectEq(coop.mode, "Coop", "coop mode")
	expectEq(coop.partner.critBonus, 20, "Coop keeps the partner's crit bonus")
end)

test("a seeded Duel is deterministic", function()
	local function play()
		local state = newDuel(21)
		for _ = 1, 4 do
			Match.TrySummon(state, 1)
			Match.TrySummon(state, 2)
		end
		runFor(state, 40)
		local snapshot =
			{ state.lives, state.partner.lives, state.mp, state.partner.mp, state.kills, state.partner.kills }
		for _, enemy in state.enemies do
			table.insert(snapshot, enemy.id .. ":" .. math.floor(enemy.hp))
		end
		return table.concat(snapshot, ",") .. "|" .. tostring(state.phase)
	end
	expectEq(play(), play(), "same seed, same match")
end)

test("both lanes get the same waves", function()
	local state = newDuel(3)
	local spawned = {}
	for _ = 1, 400 do
		Match.Step(state, state.lastNow + DT)
		for _, record in Match.TakeOut(state).S do
			table.insert(spawned, record)
			expectEq(record.Arena, "Duel", "arena on S")
			expectEq(record.PlayerCount, 2, "player count on S")
		end
	end
	expect(#spawned >= 8, "a wave spawned")
	expectEq(#spawned % 2, 0, "pairs")
	for i = 1, #spawned, 2 do
		local a, b = spawned[i], spawned[i + 1]
		expectEq(a.Seat, 1, "lane one")
		expectEq(b.Seat, 2, "lane two")
		expectEq(a.Kind, b.Kind, "same kind")
		expectEq(a.MaxHp, b.MaxHp, "same hp")
		expectEq(a.SpawnAt, b.SpawnAt, "same spawn time")
		expectEq(a.Speed, b.Speed, "same speed")
	end
end)

test("a breach costs only the lane owner's lives", function()
	local state = newDuel()
	openWave(state)
	addEnemy(state, 2, "Brute", 100, 200)
	Match.Step(state, DT)
	expectEq(state.lives, Balance.StartLives, "seat one untouched")
	expectEq(state.partner.lives, Balance.StartLives - Enemies.Kinds.Brute.lives, "seat two paid")
	expectEq(state.phase, "Playing", "still playing")
	local out = Match.TakeOut(state)
	expectEq(out.R[1].Why, "Breach", "breach record")
	expectEq(out.R[1].Arena, "Duel", "arena on R")
end)

test("dice only shoot their own lane and kill MP goes to the lane owner", function()
	local state = newDuel()
	openWave(state)
	place(state, 1, "C01")
	local far = addEnemy(state, 2, "Grunt", 50, 10)
	local near = addEnemy(state, 1, "Grunt", 1, 5)
	local mp1, mp2 = state.mp, state.partner.mp
	runFor(state, 1)
	expectEq(far.hp, 50, "seat two enemy is out of reach")
	expect(near.hp <= 0, "own-lane enemy killed")
	expectEq(state.mp, mp1 + Formulas.KillMp("Grunt", 1), "owner paid")
	expectEq(state.partner.mp, mp2, "other seat unpaid")
	expectEq(state.kills, 1, "seat one kills")
	expectEq(state.partner.kills, 0, "seat two kills")
	local fired = false
	for _, record in Match.TakeOut(state).F do
		fired = true
		expectEq(record.Arena, "Duel", "arena on F")
		expectEq(record.Seat, 1, "seat on F")
		expectEq(record.Id, near.id, "target is own lane")
	end
	expect(fired, "shots were fired")
	-- Seat two's own die kills on its own lane only.
	place(state.partner, 1, "C01")
	far.hp = 1
	runFor(state, 1)
	expectEq(state.partner.kills, 1, "seat two kill counted")
	expectEq(state.partner.mp, mp2 + Formulas.KillMp("Grunt", 1), "seat two paid")
end)

test("losing all lives loses the Duel", function()
	local state = newDuel()
	openWave(state)
	state.partner.lives = 1
	state.kills, state.partner.kills = 4, 2
	addEnemy(state, 2, "Grunt", 100, 200)
	Match.Step(state, DT)
	expectEq(state.phase, "Ended", "ended")
	expectEq(state.result, "Duel", "result")
	expectEq(state.duel.Winner, 1, "seat one wins")
	expectEq(state.duel.Why, "Lives", "why")
	expectEq(state.duel.Lives[1], Balance.StartLives, "lives a")
	expectEq(state.duel.Lives[2], 0, "lives b")
	expectEq(state.duel.Kills[1], 4, "kills a")
	expectEq(state.duel.Kills[2], 2, "kills b")
	local before = state.lastNow
	Match.Step(state, 5)
	expectEq(state.lastNow, before, "no further steps")
end)

-- Both seats breach to zero in one Step, with the given kills.
local function bothZero(seed, ka, kb)
	local state = newDuel(seed)
	openWave(state)
	state.lives, state.partner.lives = 1, 1
	state.kills, state.partner.kills = ka, kb
	addEnemy(state, 1, "Grunt", 100, 200)
	addEnemy(state, 2, "Grunt", 100, 200)
	Match.Step(state, DT)
	return state
end

test("both seats at zero in the same step: more kills wins", function()
	local state = bothZero(5, 2, 7)
	expectEq(state.result, "Duel", "result")
	expectEq(state.duel.Winner, 2, "more kills wins")
	expectEq(state.duel.Why, "Lives", "why")
	expectEq(state.duel.Lives[1], 0, "zero")
	expectEq(state.duel.Lives[2], 0, "zero")
	expectEq(bothZero(5, 9, 1).duel.Winner, 1, "seat one more kills")
end)

test("both seats at zero with equal kills is a seeded coin flip, never a draw", function()
	local seen = {}
	for seed = 1, 40 do
		local a, b = bothZero(seed, 3, 3), bothZero(seed, 3, 3)
		expectEq(a.duel.Why, "Tiebreak", "why")
		expect(a.duel.Winner == 1 or a.duel.Winner == 2, "winner never nil")
		expectEq(a.duel.Winner, b.duel.Winner, "same seed, same flip")
		seen[a.duel.Winner] = true
	end
	expect(seen[1] and seen[2], "both outcomes reachable across seeds")
end)

test("there is no wave cap: a Duel keeps playing past wave 30", function()
	local state = newDuel()
	state.wave = 40
	state.waveState = "Active"
	state.queue = {}
	state.qi = 1
	state.bossSpawned = true -- the wave's boss is already dead
	Match.Step(state, DT)
	expectEq(state.phase, "Playing", "still playing")
	expectEq(state.wavesCompleted, 40, "wave cleared")
end)

local Balance = require(Server.Config.Balance)

-- Runs the Duel until `wave`'s bosses have spawned; returns the state and the Boss enemies by seat.
local function toBoss(wave: number)
	local state = newDuel()
	local now = 0
	for _ = 1, 4000 do
		now += 0.25
		Match.Step(state, now)
		Match.TakeOut(state)
		if state.bossSpawned and state.wave == wave then
			break
		end
		if state.wave > wave or state.phase ~= "Playing" then
			break
		end
		-- keep both seats alive: the test only looks at the boss rule
		state.lives, state.partner.lives = 99, 99
	end
	local bosses = {}
	for _, enemy in state.enemies do
		if enemy.kind == "Boss" then
			bosses[enemy.seat] = enemy
		end
	end
	return state, bosses
end

test("every Duel wave ends in one boss per lane, HP = BossPerRound x wave + half the absorbed mobs", function()
	local state, bosses = toBoss(1)
	expect(state.bossSpawned, "boss spawned")
	expect(bosses[1] and bosses[2], "a boss on each lane")
	local base = Balance.Duel.BossPerRound * 1
	for seat = 1, 2 do
		expect(bosses[seat].maxHp >= base, "boss HP is at least the per-round base")
		expect(bosses[seat].maxHp <= base + Balance.Duel.AbsorbShare * 2000, "absorbed share stays modest in wave 1")
	end
	for _, enemy in state.enemies do
		expect(enemy.kind == "Boss", "all remaining mobs were absorbed")
	end
end)

test("the boss comes early when both lanes are clear, otherwise after the round timer", function()
	local state = newDuel()
	state.wave, state.waveState, state.qi, state.queue = 3, "Active", 1, {}
	state.waveStartAt = 0
	state.bossSpawned = false
	Match.Step(state, DT)
	expect(state.bossSpawned, "clear lanes: boss at once")
	local slow = newDuel()
	slow.wave, slow.waveState, slow.qi, slow.queue = 3, "Active", 1, {}
	slow.waveStartAt = 0
	slow.bossSpawned = false
	table.insert(
		slow.enemies,
		{ id = 900, kind = "Grunt", hp = 50, maxHp = 50, speed = 0, spawnAt = 0, dist = 0, seat = 1 }
	)
	slow.nextEnemyId = 901
	local now = 0
	while now < 5 do
		now += 0.25
		Match.Step(slow, now)
	end
	expect(not slow.bossSpawned, "a mob alive and the round timer not up: no boss yet")
	while now < Match.RoundTime(3) + 1 do
		now += 0.25
		Match.Step(slow, now)
	end
	expect(slow.bossSpawned, "boss after the round timer")
	local seat1
	for _, enemy in slow.enemies do
		if enemy.kind == "Boss" and enemy.seat == 1 then
			seat1 = enemy
		end
	end
	expectEq(seat1.maxHp, math.floor(Balance.Duel.BossPerRound * 3 + 0.5 * 50 + 0.5), "absorbs the mob's HP")
end)

test("Duel kill MP is 10 x wave (+10 per boss killed), fixed at 110 from berserk, boss x2", function()
	local function killMp(kind: string, wave: number): number
		local state = newDuel()
		state.wave, state.waveState, state.qi, state.queue, state.bossSpawned = wave, "Active", 1, {}, true
		state.mp = 0
		table.insert(
			state.enemies,
			{ id = 1, kind = kind, hp = 0, maxHp = 10, speed = 0, spawnAt = 0, dist = 0, seat = 1 }
		)
		state.nextEnemyId = 2
		Match.Step(state, DT)
		return state.mp
	end
	for wave, expected in { [1] = 10, [4] = 40, [10] = 100, [11] = 110, [25] = 110 } do
		expectEq(killMp("Grunt", wave), expected, "kill MP at wave " .. wave)
	end
	expectEq(killMp("Boss", 3), 60, "a boss pays 2x the wave SP")
	expectEq(killMp("Boss", 12), 220, "boss SP caps at 220")
end)

test("a forfeit gives the win to the other seat", function()
	local state = newDuel()
	state.kills, state.partner.kills = 1, 2
	expect(Match.Forfeit(state, 1), "forfeit accepted")
	expectEq(state.phase, "Ended", "ended")
	expectEq(state.result, "Duel", "result")
	expectEq(state.duel.Winner, 2, "opponent wins")
	expectEq(state.duel.Why, "Forfeit", "why")
	expectEq(state.duel.Kills[2], 2, "kills recorded")
	expect(not Match.Forfeit(state, 2), "only once")
	expectEq(state.duel.Winner, 2, "unchanged")
	local second = newDuel()
	expect(Match.Forfeit(second, 2) and second.duel.Winner == 1, "seat two forfeits")
	expect(not Match.Forfeit(newDuel(), 3), "bad seat")
	expect(not Match.Forfeit(Match.New(1, Random.new(1), 0, Dice.Deck, Dice.Deck), 1), "not in Co-op")
	expect(not Match.Forfeit(Match.New(1, Random.new(1), 0, Dice.Deck), 1), "not in Solo")
end)

test("surrender gives the win to the other seat and never leaves a nil winner", function()
	local state = newDuel()
	expect(Match.Surrender(state, 2), "surrender accepted")
	expectEq(state.phase, "Ended", "ended")
	expectEq(state.result, "Duel", "result")
	expectEq(state.duel.Winner, 1, "opponent wins")
	expectEq(state.duel.Why, "Surrender", "why")
	expect(not Match.Surrender(state, 1), "not after the end")
	expect(not Match.Forfeit(state, 1), "forfeit not after the end either")
	expectEq(state.duel.Winner, 1, "unchanged")
	expect(not Match.Surrender(newDuel(), 0), "bad seat")
	expect(not Match.Surrender(Match.New(1, Random.new(1), 0, Dice.Deck, Dice.Deck), 1), "not in Co-op")
	expect(not Match.Surrender(Match.New(1, Random.new(1), 0, Dice.Deck), 1), "not in Solo")
	local forfeited = newDuel()
	Match.Forfeit(forfeited, 1)
	expect(forfeited.duel.Winner ~= nil, "forfeit winner not nil")
end)

test("Aborted and Error still end a Duel; Duel cannot be forced from outside", function()
	local state = newDuel()
	expect(not Match.Finish(state, "Duel"), "no Duel result without a verdict")
	expect(Match.Finish(state, "Aborted"), "abort")
	expectEq(state.result, "Aborted", "aborted")
	expectEq(state.duel, nil, "no verdict")
	local solo = Match.New(1, Random.new(1), 0, Dice.Deck)
	expect(not Match.Finish(solo, "Duel"), "Solo cannot end as Duel")
end)

test("Solo and Co-op are unchanged", function()
	local solo = Match.New(1, Random.new(2), 0, Dice.Deck)
	openWave(solo)
	addEnemy(solo, 1, "Brute", 100, 200)
	Match.Step(solo, DT)
	expectEq(solo.lives, Balance.StartLives - Enemies.Kinds.Brute.lives, "solo breach")
	for _, record in Match.TakeOut(solo).R do
		expectEq(record.Arena, "Solo", "solo arena")
	end
	local coop = Match.New(1, Random.new(2), 0, Dice.Deck, Dice.Deck)
	openWave(coop)
	addEnemy(coop, 2, "Grunt", 100, 200)
	Match.Step(coop, DT)
	expectEq(coop.lives, Balance.StartLives - 1, "Co-op shares lives")
	expectEq(coop.phase, "Playing", "still playing")
	coop.lives = 1
	addEnemy(coop, 1, "Grunt", 100, 200)
	Match.Step(coop, 0.2)
	expectEq(coop.result, "Lost", "Co-op loss")
	expectEq(coop.duel, nil, "no duel verdict")
end)

test("round timer: 90 s, 10 s shorter each wave, floor 40 s", function()
	local want = { 90, 80, 70, 60, 50, 40, 40 }
	for wave, seconds in want do
		expectEq(Match.RoundTime(wave), seconds, "wave " .. wave)
	end
end)
