-- Pure match simulation (docs/MVP.md "Tick"). No Roblox services: the caller passes
-- the clock (`now`) and a Random. Intents (TrySummon/TryMerge) validate fully before
-- mutating. All MP changes go through Economy.
--
-- Outbox: state.out = { S, H, R, F, dirty }. Match.TakeOut drains it for the
-- Enemies push; `dirty` flags that the State snapshot changed.
--
-- Power Up: state.tiers[typeId] = 1..Balance.PowerUp.Max for each type of the deck; it lives only in the match.
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

local RESULTS = { Lost = true, Aborted = true, Error = true }
local FEATURED_VFX = {
	R01 = true,
	R02 = true,
	R03 = true,
	R04 = true,
	R05 = true,
	E01 = true,
	E03 = true,
	E05 = true,
	L01 = true,
	L02 = true,
	M01 = true,
}

local function newOut()
	return { S = {}, H = {}, R = {}, F = {}, Hidx = {}, dirty = false }
end

local function tiersFor(deck: { string })
	local tiers = {}
	for _, id in deck do
		tiers[id] = 1
	end
	return tiers
end

function Match.New(runId: number, rng: any, now: number, deck: { string })
	return {
		deck = table.clone(deck),
		tiers = tiersFor(deck),
		kills = 0,
		runId = runId,
		rng = rng,
		phase = "Playing",
		result = nil,
		mp = Balance.StartMP,
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

-- Ends the match once. `result` is Lost, Aborted or Error (a run is endless).
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

-- Codes: WrongPhase, NoMP, BoardFull.
function Match.TrySummon(state): (boolean, string?)
	if state.phase ~= "Playing" then
		return false, "WrongPhase"
	end
	local cost = Formulas.SummonCost(state.summons)
	if state.mp < cost then
		return false, "NoMP"
	end
	local empty = Board.EmptyCells(state.board)
	if #empty == 0 then
		return false, "BoardFull"
	end
	local cell = empty[state.rng:NextInteger(1, #empty)]
	local typeId = state.deck[state.rng:NextInteger(1, #state.deck)]
	local ok, code = Economy.TryChange(state, "mp", -cost)
	if not ok then
		return false, if code == "Insufficient" then "NoMP" else code
	end
	Board.Summon(state.board, cell, typeId, state.nextDieId)
	state.board[cell].cd = state.lastNow -- ready now, no catch-up hits from time 0
	state.nextDieId += 1
	state.summons += 1
	state.out.dirty = true
	return true, nil
end

-- Buys the next Power Up tier of one deck die type for MP. Codes: WrongPhase, NotInDeck, MaxTier, NoMP.
function Match.TryPowerUp(state, typeId: any): (boolean, string?)
	if state.phase ~= "Playing" then
		return false, "WrongPhase"
	end
	local tier = if type(typeId) == "string" then state.tiers[typeId] else nil
	if tier == nil then
		return false, "NotInDeck"
	end
	local cost = Formulas.PowerUpCost(tier)
	if cost == nil then
		return false, "MaxTier"
	end
	local ok, code = Economy.TryChange(state, "mp", -cost)
	if not ok then
		return false, if code == "Insufficient" then "NoMP" else code
	end
	state.tiers[typeId] = tier + 1
	state.out.dirty = true
	return true, nil
end

-- State snapshot rows {Id, Tier, Cost} in deck order; Cost is nil at the maximum tier.
function Match.TiersView(state): { any }
	local rows, seen = {}, {}
	for _, id in state.deck do
		if not seen[id] then
			seen[id] = true
			local tier = state.tiers[id]
			table.insert(rows, { Id = id, Tier = tier, Cost = Formulas.PowerUpCost(tier) })
		end
	end
	return rows
end

-- Aura attack-speed bonus (fraction) per occupied cell, recomputed from the board: every aura die adds its
-- bonus to each orthogonal neighbour; a die's total is capped at Balance.AuraCap.
local function auraFrom(state, die): number
	return Formulas.Aura(die.type, die.pip, state.tiers[die.type] or 1)
end

function Match.Auras(state): { [number]: number }
	local bonus = {}
	for cell = 1, Balance.BoardCells do
		local die = state.board[cell]
		if die then
			local give = auraFrom(state, die)
			if give > 0 then
				for _, n in Board.Neighbours(cell) do
					bonus[n] = math.min(Balance.AuraCap, (bonus[n] or 0) + give)
				end
			end
		end
	end
	return bonus
end

function Match.SupportCells(state, typeId: string, sourceCell: number?): { number }?
	local cells
	local seen = {}
	for cell = sourceCell or 1, sourceCell or Balance.BoardCells do
		local die = state.board[cell]
		if die and die.type == typeId and auraFrom(state, die) > 0 then
			for _, neighbor in Board.Neighbours(cell) do
				if state.board[neighbor] and not seen[neighbor] then
					seen[neighbor] = true
					cells = cells or {}
					table.insert(cells, neighbor)
				end
			end
		end
	end
	return cells
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
	local typeId = state.deck[state.rng:NextInteger(1, #state.deck)]
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
	for i = 1, Formulas.WaveCount(wave) do
		table.insert(queue, Formulas.KindAt(wave, i))
	end
	if Formulas.HasBrute(wave) then
		table.insert(queue, "Brute")
	end
	if Formulas.IsBoss(wave) then
		table.insert(queue, "Boss")
	end
	state.queue = queue
	state.qi = 1
	state.nextSpawnAt = state.nextWaveAt
	state.waveState = "Active"
	-- The warning runs on until the Boss, queued last, actually walks in.
	state.bossAt = if Formulas.IsBoss(wave)
		then state.nextSpawnAt + (#queue - 1) * Formulas.SpawnInterval(wave)
		else nil
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

local function updateEnemy(state, enemy)
	local out = state.out
	local record = { Id = enemy.id, Hp = math.max(0, enemy.hp), Speed = enemy.speed, SpawnAt = enemy.spawnAt }
	local index = out.Hidx[enemy.id]
	if index then
		out.H[index] = record
	else
		table.insert(out.H, record)
		out.Hidx[enemy.id] = #out.H
	end
end

local function damage(state, enemy, amount: number)
	enemy.hp -= amount
	updateEnemy(state, enemy)
end

local function setSpeed(state, enemy, speed, now)
	enemy.dist = math.max(0, enemy.speed * (now - enemy.spawnAt))
	enemy.speed = speed
	enemy.spawnAt = now - enemy.dist / speed
	updateEnemy(state, enemy)
end

local function attack(state, now: number)
	local enemies = state.enemies
	local auras = Match.Auras(state)
	for cell = 1, Balance.BoardCells do
		local die = state.board[cell]
		if die then
			local cfg = Dice.Types[die.type]
			local tier = state.tiers[die.type] or 1 -- a die off the deck (only a spec places one) is tier 1
			local period = Formulas.Period(die.type, die.pip, auras[cell])
			local twinshot = die.type == "C04"
			local showProjectile = cfg.rarity == "Common" or FEATURED_VFX[die.type]
			local attacks = 0
			while die.cd <= now and attacks < Balance.MaxAttacksPerTick do
				local first
				local alive = 0
				for _, enemy in enemies do
					if enemy.hp > 0 then
						alive += 1
						if first == nil or enemy.dist > first.dist then
							first = enemy
						end
					end
				end
				if first == nil then
					die.cd = now -- idle cooldown does not bank
					break
				end
				-- Both targets are chosen before either shot deals damage.
				local second = first
				if twinshot and alive > 1 then
					local index = state.rng:NextInteger(1, alive)
					for _, enemy in enemies do
						if enemy.hp > 0 then
							index -= 1
							if index == 0 then
								second = enemy
								break
							end
						end
					end
				end
				die.hits += 1
				local flat = if cfg.procEvery and die.hits % cfg.procEvery == 0 then cfg.procFlat else 0
				local supportCells = if die.type == "R05" then Match.SupportCells(state, die.type, cell) else nil
				for shot = 1, cfg.shots or 1 do
					local target = if shot == 1 then first else second
					damage(
						state,
						target,
						Formulas.HitDamage(die.type, target.kind, if shot == 1 then flat else 0, tier)
					)
					if cfg.slow and target.hp > 0 then
						if not target.slowUntil then
							target.baseSpeed = target.speed
							setSpeed(state, target, target.speed * (1 - cfg.slow), now)
						end
						target.slowUntil = now + cfg.slowDuration
					end
					table.insert(state.out.F, {
						Cell = cell,
						Id = target.id,
						Type = die.type,
						Distance = if showProjectile then target.dist else nil,
						Boosted = if showProjectile and flat > 0 then true else nil,
						Slowed = if showProjectile and cfg.slow and target.hp > 0 then true else nil,
						SlowUntil = if cfg.slow and target.hp > 0 then target.slowUntil else nil,
						SupportCells = supportCells,
						Lane = if twinshot then (if shot == 1 then 1 else -1) else nil,
						SharedTarget = if twinshot and first == second then true else nil,
					})
				end
				attacks += 1
				die.cd += period
			end
			die.cd = math.max(die.cd, now - period)
		end
	end
end

-- Advances the match to `now`. Order: wave advance, spawn, move + breach, dice
-- attacks, deaths + kill MP, wave clear.
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
		if enemy.slowUntil and now >= enemy.slowUntil then
			setSpeed(state, enemy, enemy.baseSpeed, enemy.slowUntil)
			enemy.slowUntil = nil
		end
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

	-- Deaths + kill MP.
	local alive = {}
	for _, enemy in survivors do
		if enemy.hp <= 0 then
			Economy.TryChange(state, "mp", Formulas.KillMp(enemy.kind, state.wave))
			state.kills += 1
			table.insert(state.out.R, { Id = enemy.id, Why = "Kill" })
			state.out.dirty = true
		else
			table.insert(alive, enemy)
		end
	end
	state.enemies = alive

	-- Wave clear.
	if state.waveState == "Active" and state.qi > #state.queue and #alive == 0 then
		state.wavesCompleted = state.wave
		state.out.dirty = true
		state.waveState = "Prep"
		state.nextWaveAt = now + Balance.WaveGap
		state.bossAt = if Formulas.IsBoss(state.wave + 1) then state.nextWaveAt else nil
	end
end

return Match
