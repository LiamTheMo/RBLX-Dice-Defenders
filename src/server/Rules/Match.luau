-- Pure match simulation (docs/MVP.md "Tick"). No Roblox services: the caller passes
-- the clock (`now`) and a Random. Intents (TrySummon/TryMerge) validate fully before
-- mutating. All Energy changes go through Economy.
--
-- Outbox: state.out = { S, H, R, F, dirty }. Match.TakeOut drains it for the
-- Enemies push; `dirty` flags that the State snapshot changed.
--
-- Time: Step simulates at most Balance.MaxStep seconds per call, so state.lastNow is
-- a virtual clock that trails `now` after a hitch (never jumps).
local Balance = require(script.Parent.Parent.Config.Balance)
local Dice = require(script.Parent.Parent.Config.Dice)
local Enemies = require(script.Parent.Parent.Config.Enemies)
local Board = require(script.Parent.Board)
local Economy = require(script.Parent.Economy)
local Formulas = require(script.Parent.Formulas)
local Layout = require(game:GetService("ReplicatedStorage").Shared.Layout)

local Match = {}

local RESULTS = { Won = true, Lost = true, Aborted = true, Error = true }

local function newOut()
	return { S = {}, H = {}, R = {}, F = {}, Hidx = {}, dirty = false }
end

function Match.New(runId: number, rng: any, now: number)
	return {
		runId = runId,
		rng = rng,
		phase = "Playing",
		result = nil,
		energy = Balance.StartEnergy,
		summons = 0,
		lives = Balance.StartLives,
		wave = 0,
		wavesCompleted = 0,
		waveState = "Prep",
		nextWaveAt = now + Balance.FirstWaveDelay,
		bossAt = nil,
		queue = {},
		qi = 1,
		nextSpawnAt = 0,
		enemies = {},
		nextEnemyId = 1,
		board = Board.New(),
		nextDieId = 1,
		lastNow = now,
		rewardGranted = false,
		out = newOut(),
	}
end

function Match.SummonCost(state): number
	return Formulas.SummonCost(state.summons)
end

-- Ends the match once. `result` is Won, Lost, Aborted or Error.
function Match.Finish(state, result: string): boolean
	if state.phase ~= "Playing" or not RESULTS[result] then
		return false
	end
	state.phase = "Ended"
	state.result = result
	state.out.dirty = true
	return true
end

function Match.TakeOut(state)
	local out = state.out
	local batch = { S = out.S, H = out.H, R = out.R, F = out.F }
	local dirty = out.dirty
	state.out = newOut()
	return batch, dirty
end

-- Intents ---------------------------------------------------------------------

-- Codes: WrongPhase, NoEnergy, BoardFull.
function Match.TrySummon(state): (boolean, string?)
	if state.phase ~= "Playing" then
		return false, "WrongPhase"
	end
	local cost = Formulas.SummonCost(state.summons)
	if state.energy < cost then
		return false, "NoEnergy"
	end
	local empty = Board.EmptyCells(state.board)
	if #empty == 0 then
		return false, "BoardFull"
	end
	local cell = empty[state.rng:NextInteger(1, #empty)]
	local typeId = Dice.Deck[state.rng:NextInteger(1, #Dice.Deck)]
	local ok, code = Economy.TryChange(state, "energy", -cost)
	if not ok then
		return false, if code == "Insufficient" then "NoEnergy" else code
	end
	Board.Summon(state.board, cell, typeId, state.nextDieId)
	state.nextDieId += 1
	state.summons += 1
	state.out.dirty = true
	return true, nil
end

-- Codes: WrongPhase, IllegalMerge.
function Match.TryMerge(state, from: any, to: any): (boolean, string?)
	if state.phase ~= "Playing" then
		return false, "WrongPhase"
	end
	local legal, code = Board.CheckMerge(state.board, from, to)
	if not legal then
		return false, code
	end
	local typeId = Dice.Deck[state.rng:NextInteger(1, #Dice.Deck)]
	local ok, mergeCode = Board.Merge(state.board, from, to, typeId)
	if not ok then
		return false, mergeCode
	end
	state.out.dirty = true
	return true, nil
end

-- Step ------------------------------------------------------------------------

local function startWave(state)
	local wave = state.wave + 1
	state.wave = wave
	local queue = {}
	if wave == Balance.BossWave then
		table.insert(queue, "Boss")
	end
	for i = 1, Formulas.WaveCount(wave) do
		table.insert(queue, Formulas.KindAt(wave, i))
	end
	state.queue = queue
	state.qi = 1
	state.nextSpawnAt = state.nextWaveAt
	state.waveState = "Active"
	state.bossAt = nil
	state.out.dirty = true
end

local function spawn(state, now: number)
	local interval = Formulas.SpawnInterval(state.wave)
	local speedMul = Formulas.SpeedMul(state.wave)
	while state.qi <= #state.queue and state.nextSpawnAt <= now do
		if #state.enemies >= Balance.MaxAlive then
			state.nextSpawnAt = math.max(state.nextSpawnAt, now) -- wait, never drop
			return
		end
		local kind = state.queue[state.qi]
		local hp = Formulas.EnemyHp(kind, state.wave)
		local enemy = {
			id = state.nextEnemyId,
			kind = kind,
			hp = hp,
			maxHp = hp,
			speed = Enemies.Kinds[kind].speed * speedMul,
			spawnAt = state.nextSpawnAt,
			dist = 0,
		}
		state.nextEnemyId += 1
		state.qi += 1
		state.nextSpawnAt += interval
		table.insert(state.enemies, enemy)
		table.insert(state.out.S, {
			Id = enemy.id,
			Kind = kind,
			SpawnAt = enemy.spawnAt,
			Speed = enemy.speed,
			MaxHp = hp,
			Hp = hp,
		})
	end
end

local function damage(state, enemy, amount: number)
	enemy.hp -= amount
	local out = state.out
	local record = { Id = enemy.id, Hp = math.max(0, enemy.hp) }
	local index = out.Hidx[enemy.id]
	if index then
		out.H[index] = record
	else
		table.insert(out.H, record)
		out.Hidx[enemy.id] = #out.H
	end
end

local function attack(state, now: number)
	local enemies = state.enemies
	for cell = 1, Balance.BoardCells do
		local die = state.board[cell]
		if die then
			local cfg = Dice.Types[die.type]
			local period = Formulas.Period(die.type)
			local attacks = 0
			while die.cd <= now and attacks < Balance.MaxAttacksPerTick do
				-- Global First: the alive enemies closest to the exit, anywhere on the path.
				local first, second
				for _, enemy in enemies do
					if enemy.hp > 0 then
						if first == nil or enemy.dist > first.dist then
							first, second = enemy, first
						elseif second == nil or enemy.dist > second.dist then
							second = enemy
						end
					end
				end
				if first == nil then
					die.cd = now -- idle cooldown does not bank
					break
				end
				die.hits += 1
				local flat = if cfg.procEvery and die.hits % cfg.procEvery == 0 then cfg.procFlat else 0
				for shot = 1, cfg.shots or 1 do
					local target = if shot == 1 then first else second or first
					damage(
						state,
						target,
						Formulas.HitDamage(die.type, die.pip, target.kind, if shot == 1 then flat else 0)
					)
					table.insert(state.out.F, { Cell = cell, Id = target.id })
				end
				attacks += 1
				die.cd += period
			end
			die.cd = math.max(die.cd, now - period)
		end
	end
end

-- Advances the match to `now`. Order: wave advance, spawn, move + breach, dice
-- attacks, deaths + kill Energy, wave clear / win.
function Match.Step(state, now: number)
	if state.phase ~= "Playing" then
		return
	end
	local dt = math.clamp(now - state.lastNow, 0, Balance.MaxStep)
	now = state.lastNow + dt
	state.lastNow = now

	if state.waveState == "Prep" and now >= state.nextWaveAt then
		startWave(state)
	end
	if state.waveState == "Active" then
		spawn(state, now)
	end

	-- Move + breach. dist is a pure function of time so clients can reproduce it.
	local survivors = {}
	for _, enemy in state.enemies do
		enemy.dist = math.max(0, enemy.speed * (now - enemy.spawnAt))
		if enemy.dist >= Layout.PathLength then
			state.lives -= Enemies.Kinds[enemy.kind].lives
			table.insert(state.out.R, { Id = enemy.id, Why = "Breach" })
			state.out.dirty = true
		else
			table.insert(survivors, enemy)
		end
	end
	state.enemies = survivors
	if state.lives <= 0 then
		state.lives = 0
		Match.Finish(state, "Lost")
		return
	end

	-- Dice attacks.
	attack(state, now)

	-- Deaths + kill Energy.
	local alive = {}
	for _, enemy in survivors do
		if enemy.hp <= 0 then
			Economy.TryChange(state, "energy", Enemies.Kinds[enemy.kind].energy)
			table.insert(state.out.R, { Id = enemy.id, Why = "Kill" })
			state.out.dirty = true
		else
			table.insert(alive, enemy)
		end
	end
	state.enemies = alive

	-- Wave clear / win.
	if state.waveState == "Active" and state.qi > #state.queue and #alive == 0 then
		state.wavesCompleted = state.wave
		state.out.dirty = true
		if state.wave >= Balance.Waves then
			Match.Finish(state, "Won")
			return
		end
		Economy.TryChange(state, "energy", Formulas.Stipend(state.wave))
		state.waveState = "Prep"
		state.nextWaveAt = now + Balance.WaveGap
		if state.wave + 1 == Balance.BossWave then
			state.bossAt = state.nextWaveAt
		end
	end
end

return Match
