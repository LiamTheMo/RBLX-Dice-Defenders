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
local CoopWaves = require(script.Parent.Parent.Config.CoopWaves)
local Enemies = require(script.Parent.Parent.Config.Enemies)
local Board = require(script.Parent.Board)
local Economy = require(script.Parent.Economy)
local Formulas = require(script.Parent.Formulas)
local Layout = require(game:GetService("ReplicatedStorage").Shared.Layout)

local Match = {}

local RESULTS = { Lost = true, Aborted = true, Error = true, Duel = true }
local FEATURED_VFX = {
	R01 = true,
	R02 = true,
	R03 = true,
	R04 = true,
	R05 = true,
	E01 = true,
	E02 = true,
	E03 = true,
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

local function newSeat(deck: { string }, critBonus: number?)
	return {
		deck = table.clone(deck),
		critBonus = critBonus or 0, -- crit damage percent from this player's die levels
		tiers = tiersFor(deck),
		mp = Balance.StartMP,
		kills = 0, -- enemies killed on this seat's lane (state.kills is seat one's, and the lane total in Co-op)
		summons = 0,
		board = Board.New(),
		nextDieId = 1,
	}
end

function Match.New(
	runId: number,
	rng: any,
	now: number,
	deck: { string },
	partnerDeck: { string }?,
	critBonus: number?,
	partnerCritBonus: number?
)
	-- Keep the primary seat on the original state for solo callers.
	local state = {
		kills = 0,
		mode = if partnerDeck then "Coop" else "Solo",
		runId = runId,
		rng = rng,
		phase = "Playing",
		result = nil,
		lives = Balance.StartLives,
		playerCount = if partnerDeck then 2 else 1,
		partner = if partnerDeck then newSeat(partnerDeck, partnerCritBonus) else nil,
		wave = 0,
		wavesCompleted = 0,
		waveState = "Prep",
		nextWaveAt = now + Balance.FirstWaveDelay,
		bossAt = nil,
		queue = {},
		carriedHp = CoopWaves.InitialHp,
		hpStep = 0,
		qi = 1,
		nextSpawnAt = 0,
		enemies = {},
		nextEnemyId = 1,
		lastNow = now,
		rewardGranted = false,
		out = newOut(),
	}
	for key, value in newSeat(deck, critBonus) do
		state[key] = value
	end
	return state
end

-- 1v1 Duel (docs/DICE_RATING.md section 4): two seats, the same waves on both lanes, own lives, own MP, no crit bonus.
-- Seat two lives on state.partner like Co-op; each seat carries its own `lives`.
function Match.NewDuel(runId: number, rng: any, now: number, deckA: { string }, deckB: { string })
	local state = Match.New(runId, rng, now, deckA, deckB, 0, 0)
	state.mode = "Duel"
	state.partner.lives = Balance.StartLives
	return state
end

function Match.Seat(state, index: number?)
	return if index == 2 then state.partner else state
end

function Match.SummonCost(state): number
	return Formulas.SummonCost(state.summons)
end

-- Ends the match once. `result` is Lost, Aborted or Error (a run is endless); "Duel" only via endDuel/Forfeit.
function Match.Finish(state, result: string): boolean
	if state.phase ~= "Playing" or not RESULTS[result] or (result == "Duel") ~= (state.duel ~= nil) then
		return false
	end
	state.phase = "Ended"
	state.result = result
	state.out.dirty = true
	return true
end

local function endDuel(state, winner: number, why: string)
	state.duel = {
		Winner = winner,
		Why = why,
		Lives = { state.lives, state.partner.lives },
		Kills = { state.kills, state.partner.kills },
	}
	Match.Finish(state, "Duel")
end

local function concede(state, seatIndex: number, why: string): boolean
	if state.mode ~= "Duel" or state.phase ~= "Playing" or (seatIndex ~= 1 and seatIndex ~= 2) then
		return false
	end
	endDuel(state, if seatIndex == 1 then 2 else 1, why)
	return true
end

-- A seat leaves: it loses, the opponent wins. No effect outside a Duel in progress.
function Match.Forfeit(state, seatIndex: number): boolean
	return concede(state, seatIndex, "Forfeit")
end

-- A seat surrenders on purpose (same effect as Forfeit, Why = "Surrender"). Only while Playing in a Duel.
function Match.Surrender(state, seatIndex: number): boolean
	return concede(state, seatIndex, "Surrender")
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
function Match.TrySummon(state, index: number?): (boolean, string?)
	if state.phase ~= "Playing" then
		return false, "WrongPhase"
	end
	local seat = Match.Seat(state, index)
	if not seat then
		return false, "WrongPhase"
	end
	local cost = Formulas.SummonCost(seat.summons)
	if seat.mp < cost then
		return false, "NoMP"
	end
	local empty = Board.EmptyCells(seat.board)
	if #empty == 0 then
		return false, "BoardFull"
	end
	local cell = empty[state.rng:NextInteger(1, #empty)]
	local typeId = seat.deck[state.rng:NextInteger(1, #seat.deck)]
	local ok, code = Economy.TryChange(seat, "mp", -cost)
	if not ok then
		return false, if code == "Insufficient" then "NoMP" else code
	end
	Board.Summon(seat.board, cell, typeId, seat.nextDieId)
	seat.board[cell].cd = state.lastNow -- ready now, no catch-up hits from time 0
	seat.nextDieId += 1
	seat.summons += 1
	state.out.dirty = true
	return true, nil
end

-- Buys the next Power Up tier of one deck die type for MP. Codes: WrongPhase, NotInDeck, MaxTier, NoMP.
function Match.TryPowerUp(state, typeId: any, index: number?): (boolean, string?)
	if state.phase ~= "Playing" then
		return false, "WrongPhase"
	end
	local seat = Match.Seat(state, index)
	if not seat then
		return false, "WrongPhase"
	end
	local tier = if type(typeId) == "string" then seat.tiers[typeId] else nil
	if tier == nil then
		return false, "NotInDeck"
	end
	local cost = Formulas.PowerUpCost(tier)
	if cost == nil then
		return false, "MaxTier"
	end
	local ok, code = Economy.TryChange(seat, "mp", -cost)
	if not ok then
		return false, if code == "Insufficient" then "NoMP" else code
	end
	seat.tiers[typeId] = tier + 1
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
function Match.TryMerge(state, from: any, to: any, index: number?): (boolean, string?)
	if state.phase ~= "Playing" then
		return false, "WrongPhase"
	end
	local seat = Match.Seat(state, index)
	if not seat then
		return false, "WrongPhase"
	end
	local legal, code = Board.CheckMerge(seat.board, from, to)
	if not legal then
		return false, code
	end
	local typeId = seat.deck[state.rng:NextInteger(1, #seat.deck)]
	local ok, mergeCode = Board.Merge(seat.board, from, to, typeId)
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
	state.queue, state.carriedHp, state.hpStep = CoopWaves.Next(wave, state.carriedHp, state.hpStep)
	state.qi = 1
	state.nextSpawnAt = state.nextWaveAt
	state.waveState = "Active"
	state.bossAt = if CoopWaves.IsBoss(wave) then state.nextSpawnAt else nil
	state.out.dirty = true
end

local function spawn(state, now: number)
	local interval = Formulas.SpawnInterval(state.wave)
	local speedMul = Formulas.SpeedMul(state.wave)
	while state.qi <= #state.queue and state.nextSpawnAt <= now do
		if #state.enemies + state.playerCount > Balance.MaxAlive then
			state.nextSpawnAt = math.max(state.nextSpawnAt, now) -- wait, never drop
			return
		end
		local entry = state.queue[state.qi]
		for index = 1, state.playerCount do
			local enemy = {
				id = state.nextEnemyId,
				kind = entry.kind,
				hp = entry.hp,
				maxHp = entry.hp,
				speed = (if entry.kind == "Runner"
					then Enemies.Kinds.Grunt.speed * 1.5
					else Enemies.Kinds[entry.kind].speed) * speedMul,
				spawnAt = state.nextSpawnAt,
				dist = 0,
				seat = index,
			}
			state.nextEnemyId += 1
			table.insert(state.enemies, enemy)
			table.insert(state.out.S, {
				Id = enemy.id,
				Kind = enemy.kind,
				SpawnAt = enemy.spawnAt,
				Speed = enemy.speed,
				MaxHp = enemy.maxHp,
				Hp = enemy.hp,
				Seat = index,
				PlayerCount = state.playerCount,
				Arena = state.mode,
			})
		end
		state.qi += 1
		state.nextSpawnAt += interval
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

local function attack(state, seat, index: number, now: number)
	local enemies = state.enemies
	local auras = Match.Auras(seat)
	local singularity = Formulas.HasSingularity(seat.board)
	local restrictLane = state.partner ~= nil
	local duel = state.mode == "Duel"
	-- A Duel die only sees its own lane; Co-op also shares the stretch past the junction.
	local function reachable(enemy): boolean
		return enemy.hp > 0
			and (not restrictLane or enemy.seat == index or (not duel and enemy.dist >= Layout.CoopJunction))
	end
	for cell = 1, Balance.BoardCells do
		local die = seat.board[cell]
		if die then
			local cfg = Dice.Types[die.type]
			local tier = seat.tiers[die.type] or 1 -- a die off the deck (only a spec places one) is tier 1
			local period = Formulas.Period(die.type, die.pip, auras[cell])
			local twinshot = die.type == "C04"
			local showProjectile = cfg.rarity == "Common" or FEATURED_VFX[die.type]
			local attacks = 0
			while die.cd <= now and attacks < Balance.MaxAttacksPerTick do
				local first
				local alive = 0
				for _, enemy in enemies do
					if reachable(enemy) then
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
					local pick = state.rng:NextInteger(1, alive)
					for _, enemy in enemies do
						if reachable(enemy) then
							pick -= 1
							if pick == 0 then
								second = enemy
								break
							end
						end
					end
				end
				die.hits += 1
				local flat = if cfg.procEvery and die.hits % cfg.procEvery == 0 then cfg.procFlat else 0
				local supportCells = if die.type == "R05" then Match.SupportCells(seat, die.type, cell) else nil
				for shot = 1, cfg.shots or 1 do
					local target = if shot == 1 then first else second
					local critical = Formulas.SingularityCrit(die.type, singularity, state.rng)
					local amount = Formulas.HitDamage(
						die.type,
						target.kind,
						if shot == 1 then flat else 0,
						tier,
						singularity,
						critical,
						seat.critBonus
					)
					damage(state, target, amount)
					if cfg.slow and target.hp > 0 then
						if not target.slowUntil then
							target.baseSpeed = target.speed
							setSpeed(state, target, target.speed * (1 - cfg.slow), now)
						end
						target.slowUntil = now + cfg.slowDuration
					end
					table.insert(state.out.F, {
						Cell = cell,
						Seat = index,
						PlayerCount = state.playerCount,
						Arena = state.mode,
						Id = target.id,
						Type = die.type,
						Distance = if showProjectile then target.dist else nil,
						Boosted = if showProjectile and flat > 0 then true else nil,
						Critical = if critical then true else nil,
						Damage = amount, -- floating damage number (display only)
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
	local duel = state.mode == "Duel"
	for _, enemy in state.enemies do
		if enemy.slowUntil and now >= enemy.slowUntil then
			setSpeed(state, enemy, enemy.baseSpeed, enemy.slowUntil)
			enemy.slowUntil = nil
		end
		enemy.dist = math.max(0, enemy.speed * (now - enemy.spawnAt))
		-- Duel lanes are the same 124-stud balance length as Co-op (docs/DICE_RATING.md section 5).
		local pathLength = if state.playerCount == 2 then Layout.CoopPathLength else Layout.PathLength
		if enemy.dist >= pathLength then
			local owner = if duel then Match.Seat(state, enemy.seat) else state
			owner.lives -= Enemies.Kinds[enemy.kind].lives
			table.insert(state.out.R, { Id = enemy.id, Why = "Breach", Arena = state.mode, Seat = enemy.seat })
			state.out.dirty = true
		else
			table.insert(survivors, enemy)
		end
	end
	state.enemies = survivors
	if duel then
		local a, b = state.lives <= 0, state.partner.lives <= 0
		if a or b then
			state.lives, state.partner.lives = math.max(0, state.lives), math.max(0, state.partner.lives)
			if not (a and b) then
				endDuel(state, if a then 2 else 1, "Lives")
			elseif state.kills ~= state.partner.kills then
				endDuel(state, if state.kills > state.partner.kills then 1 else 2, "Lives")
			else
				endDuel(state, state.rng:NextInteger(1, 2), "Tiebreak") -- seeded coin flip: never a draw
			end
			return
		end
	elseif state.lives <= 0 then
		state.lives = 0
		Match.Finish(state, "Lost")
		return
	end

	-- Dice attacks.
	attack(state, state, 1, now)
	if state.partner then
		attack(state, state.partner, 2, now)
	end

	-- Deaths + kill MP.
	local alive = {}
	for _, enemy in survivors do
		if enemy.hp <= 0 then
			local gain = Formulas.KillMp(enemy.kind, state.wave)
			if duel then
				local owner = Match.Seat(state, enemy.seat)
				Economy.TryChange(owner, "mp", gain)
				owner.kills += 1
			else
				Economy.TryChange(state, "mp", gain)
				if state.partner then
					Economy.TryChange(state.partner, "mp", gain)
				end
				state.kills += 1
			end
			table.insert(state.out.R, { Id = enemy.id, Why = "Kill", Arena = state.mode, Seat = enemy.seat })
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
		state.bossAt = if CoopWaves.IsBoss(state.wave + 1) then state.nextWaveAt else nil
	end
end

return Match
