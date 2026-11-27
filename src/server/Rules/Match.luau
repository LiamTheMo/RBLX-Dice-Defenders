-- Pure match simulation (docs/_archive/MVP.md "Tick"). No Roblox services: the caller passes
-- the clock (`now`) and a Random. Intents (TrySummon/TryMerge) validate fully before
-- mutating. All MP changes go through Economy.
--
-- Outbox: state.out = { S, H, R, F, A, dirty }. Match.TakeOut drains it for the
-- Enemies push; `dirty` flags that the State snapshot changed.
--
-- Power Up: state.tiers[typeId] = 1..Balance.PowerUp.Max for each type of the deck; it lives only in the match.
--
-- Time: Step simulates at most Balance.MaxStep seconds per call, so state.lastNow is
-- a virtual clock that trails `now` after a hitch (never jumps).
local Balance = require(script.Parent.Parent.Config.Balance)
local Dice = require(script.Parent.Parent.Config.Dice)
local DiceClasses = require(script.Parent.Parent.Config.DiceClasses)
local Progression = require(script.Parent.Parent.Config.Progression)
local CoopWaves = require(script.Parent.Parent.Config.CoopWaves)
local Enemies = require(script.Parent.Parent.Config.Enemies)
local Board = require(script.Parent.Board)
local Economy = require(script.Parent.Economy)
local Formulas = require(script.Parent.Formulas)
local Layout = require(game:GetService("ReplicatedStorage").Shared.Layout)
local ProjectileFlight = require(game:GetService("ReplicatedStorage").Shared.ProjectileFlight)
local Bosses = require(game:GetService("ReplicatedStorage").Shared.Bosses)
local BossAbilities = require(script.Parent.BossAbilities)
local Abilities = require(script.Parent.Abilities)

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
	return { S = {}, H = {}, R = {}, F = {}, A = {}, Hidx = {}, dirty = false }
end

local function tiersFor(deck: { string })
	local tiers = {}
	for _, id in deck do
		tiers[id] = 1
	end
	return tiers
end

local function newSeat(deck: { string }, critBonus: number?, levels: { [string]: number }?)
	return {
		deck = table.clone(deck),
		critBonus = critBonus or 0, -- crit damage percent from this player's die levels
		levels = levels or {}, -- this player's die levels by type id (a missing die plays at level 1)
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
	partnerCritBonus: number?,
	levels: { [string]: number }?,
	partnerLevels: { [string]: number }?
)
	-- Keep the primary seat on the original state for solo callers.
	local state = {
		kills = 0,
		mode = if partnerDeck then "Coop" else "Solo",
		runId = runId,
		rng = rng,
		-- Crits roll on their own stream so they never shift the main one (spawns, targets); critChance is the account-wide
		-- percent every die uses (Balance.Crit.Chance; a spec may zero it for exact damage).
		critRng = Random.new(runId),
		critChance = Balance.Crit.Chance,
		phase = "Playing",
		result = nil,
		lives = Balance.StartLives,
		playerCount = if partnerDeck then 2 else 1,
		partner = if partnerDeck then newSeat(partnerDeck, partnerCritBonus, partnerLevels) else nil,
		wave = 0,
		wavesCompleted = 0,
		waveState = "Prep",
		nextWaveAt = now + Balance.FirstWaveDelay,
		bossAt = nil,
		bossCount = 0, -- bosses spawned so far
		nextBossVariant = Bosses.Roll(runId, 1, nil), -- the upcoming boss, fixed until it spawns (shown in advance)
		queue = {},
		carriedHp = CoopWaves.InitialHp,
		qi = 1,
		nextSpawnAt = 0,
		enemies = {},
		pending = {}, -- Goblin King portal spawns not yet due: { at, dist, kind, seat }
		nextEnemyId = 1,
		lastNow = now,
		startedAt = now, -- read-only: the Ended snapshot reports lastNow - startedAt as the run time
		rewardGranted = false,
		out = newOut(),
	}
	for key, value in newSeat(deck, critBonus, levels) do
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

-- A die type's config for this seat: the plain entry at the player's class (Config/DiceClasses), and its level's
-- hit-damage multiplier (Progression.DamageMul).
function Match.DieCfg(seat, typeId: string)
	local rarity = Dice.Types[typeId].rarity
	return DiceClasses.View(typeId, Progression.Class(rarity, seat.levels[typeId] or 1))
end

function Match.ClassMul(seat, typeId: string): number
	return Progression.DamageMul(Dice.Types[typeId].rarity, seat.levels[typeId] or 1)
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
	local batch = { S = out.S, H = out.H, R = out.R, F = out.F, A = out.A }
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
	Abilities.Copy(seat.board, cell, state.lastNow)
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
	return Formulas.Aura(die.type, die.pip, state.tiers[die.type] or 1, Match.DieCfg(state, die.type))
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
	local board = seat.board
	-- Forge: a merge next to one keeps the merged type (no re-roll) and every `every`th also pays out a free pip-1 die.
	local forge
	for _, cell in { to, from } do
		for _, n in Board.Neighbours(cell) do
			local near = board[n]
			if n ~= to and n ~= from and near and Dice.Types[near.type].forge then
				forge = near
			end
		end
	end
	local typeId = if forge then board[from].type else seat.deck[state.rng:NextInteger(1, #seat.deck)]
	local ok, mergeCode = Board.Merge(board, from, to, typeId)
	if not ok then
		return false, mergeCode
	end
	local now = state.lastNow
	Abilities.Copy(board, to, now)
	if forge then
		local cfg = Match.DieCfg(seat, forge.type).forge
		forge.merges = (forge.merges or 0) + 1
		local empty = Board.EmptyCells(board)
		if forge.merges % cfg.every == 0 and #empty > 0 and now >= (forge.freeAt or -math.huge) + cfg.gap then
			forge.freeAt = now
			local cell = empty[state.rng:NextInteger(1, #empty)]
			Board.Summon(board, cell, typeId, seat.nextDieId)
			board[cell].cd = now
			seat.nextDieId += 1
			Abilities.Copy(board, cell, now)
		end
	end
	state.out.dirty = true
	return true, nil
end

-- Step ------------------------------------------------------------------------

local function startWave(state)
	local wave = state.wave + 1
	state.wave = wave
	local duel = state.mode == "Duel"
	state.queue, state.carriedHp = CoopWaves.Next(wave, state.carriedHp, duel)
	if duel then
		local mul = 1 + Balance.Duel.DeathHpPerWave * math.max(0, wave - Balance.Duel.DeathWave + 1)
		for _, entry in state.queue do
			entry.hp = math.max(1, math.floor(entry.hp * mul + 0.5))
		end
	end
	state.qi = 1
	state.nextSpawnAt = state.nextWaveAt
	state.waveStartAt = state.nextWaveAt
	state.bossSpawned = false
	state.waveState = "Active"
	state.bossAt = if not duel and CoopWaves.IsBoss(wave) then state.nextSpawnAt else nil
	state.out.dirty = true
end

-- Takes the upcoming boss variant for a spawn and rolls the next one (never the same twice in a row).
local function takeBossVariant(state): string
	local variant = state.nextBossVariant
	state.bossCount += 1
	state.nextBossVariant = Bosses.Roll(state.runId, state.bossCount + 1, variant)
	return variant
end

-- Wave number of the boss still to come (nil when none is near): this wave while its boss has not spawned, else a later one.
function Match.NextBossWave(state): number?
	local start = state.wave + 1
	if state.waveState == "Active" then
		local spawned = if state.mode == "Duel" then state.bossSpawned else state.qi > #state.queue
		if not spawned then
			start = state.wave
		end
	end
	if state.mode == "Duel" then
		return start
	end
	for wave = start, start + 40 do
		if CoopWaves.IsBoss(wave) then
			return wave
		end
	end
	return nil
end

-- The next `count` (co-op) boss waves as { Wave, Variant }, from the same Roll chain takeBossVariant walks; entry 1 is NextBossWave/nextBossVariant.
function Match.BossPlan(state, count: number): { { Wave: number, Variant: string } }
	local plan = {}
	local wave = Match.NextBossWave(state)
	if state.mode == "Duel" or wave == nil then
		return plan
	end
	local variant = state.nextBossVariant
	for i = 1, count do
		table.insert(plan, { Wave = wave, Variant = variant })
		repeat
			wave += 1
		until CoopWaves.IsBoss(wave)
		variant = Bosses.Roll(state.runId, state.bossCount + 1 + i, variant)
	end
	return plan
end

-- Seconds a Duel wave lasts before its boss: 90, 80, 70, 60, 50, 40 ...
function Match.RoundTime(wave: number): number
	local cfg = Balance.Duel
	return math.max(cfg.RoundMin, cfg.RoundStart - cfg.RoundStep * (wave - 1))
end

-- Duel speed: the death wave and later mobs run faster.
local function duelSpeedMul(wave: number): number
	return 1 + Balance.Duel.DeathSpeedPerWave * math.max(0, wave - Balance.Duel.DeathWave + 1)
end

-- Duel boss (Random Dice PvP): once a wave's mobs have spawned and the round timer has run out, or both lanes are clear, each
-- lane's remaining mobs are absorbed into one boss: HP = BossPerRound x wave + AbsorbShare x their HP.
local function spawnDuelBosses(state, now: number)
	local cfg = Balance.Duel
	local speedMul = Formulas.SpeedMul(state.wave) * duelSpeedMul(state.wave)
	if state.wave >= cfg.BerserkWave then
		speedMul *= cfg.BerserkBossSpeed
	end
	local keep = {}
	local absorbed = { 0, 0 }
	for _, enemy in state.enemies do
		if enemy.hp > 0 then
			absorbed[enemy.seat] += enemy.hp
			table.insert(state.out.R, { Id = enemy.id, Why = "Absorb", Arena = state.mode, Seat = enemy.seat })
		else
			table.insert(keep, enemy)
		end
	end
	state.enemies = keep
	local variant = takeBossVariant(state) -- both lanes face the same boss
	for index = 1, 2 do
		local hp = math.max(1, math.floor(cfg.BossPerRound * state.wave + cfg.AbsorbShare * absorbed[index] + 0.5))
		local enemy = {
			id = state.nextEnemyId,
			kind = "Boss",
			hp = hp,
			maxHp = hp,
			speed = Enemies.Kinds.Boss.speed * speedMul,
			spawnAt = now,
			bornAt = now,
			dist = 0,
			seat = index,
			ability = BossAbilities.New(variant, now),
		}
		state.nextEnemyId += 1
		table.insert(state.enemies, enemy)
		table.insert(state.out.S, {
			Id = enemy.id,
			Kind = "Boss",
			Variant = variant,
			SpawnAt = now,
			Speed = enemy.speed,
			MaxHp = hp,
			Hp = hp,
			Seat = index,
			PlayerCount = state.playerCount,
			Arena = state.mode,
		})
	end
	state.bossSpawned = true
	state.out.dirty = true
end

local function spawn(state, now: number)
	local interval = Formulas.SpawnInterval(state.wave)
	local speedMul = Formulas.SpeedMul(state.wave)
	if state.mode == "Duel" then
		speedMul *= duelSpeedMul(state.wave)
	end
	while state.qi <= #state.queue and state.nextSpawnAt <= now do
		if #state.enemies + state.playerCount > Balance.MaxAlive then
			state.nextSpawnAt = math.max(state.nextSpawnAt, now) -- wait, never drop
			return
		end
		local entry = state.queue[state.qi]
		local variant = if entry.kind == "Boss" then takeBossVariant(state) else nil
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
				bornAt = state.nextSpawnAt,
				dist = 0,
				seat = index,
				ability = if variant then BossAbilities.New(variant, state.nextSpawnAt) else nil,
			}
			state.nextEnemyId += 1
			table.insert(state.enemies, enemy)
			table.insert(state.out.S, {
				Id = enemy.id,
				Kind = enemy.kind,
				Variant = variant,
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
	-- Over: how far the shots counted so far overshoot 0 hp, so the client can tell which landing is the lethal one.
	local record = {
		Id = enemy.id,
		Hp = math.max(0, enemy.hp),
		Over = if enemy.hp < 0 then -enemy.hp else nil,
		Speed = enemy.speed,
		SpawnAt = enemy.spawnAt,
	}
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
	now = math.max(now, enemy.speedAt or now) -- changes of one enemy within a step never run backwards in time
	enemy.speedAt = now
	enemy.dist = math.max(0, enemy.speed * (now - enemy.spawnAt))
	enemy.speed = speed
	enemy.spawnAt = now - enemy.dist / speed
	updateEnemy(state, enemy)
end

-- Speed of a held boss: ~0 (the client reproduces dist = speed x (now - spawnAt), so a true 0 would lose the position).
local HOLD_SPEED = 1e-4

-- One speed from every modifier: base x slow, or HOLD_SPEED while a boss ability keeps it still.
-- baseSpeed exists only while a modifier is active, so a hand-set enemy.speed is never shadowed.
local function refreshSpeed(state, enemy, now: number)
	if enemy.slowMul or enemy.held or enemy.frozen then
		local base = enemy.baseSpeed or enemy.speed
		enemy.baseSpeed = base
		setSpeed(state, enemy, if enemy.held or enemy.frozen then HOLD_SPEED else base * (enemy.slowMul or 1), now)
	else
		setSpeed(state, enemy, enemy.baseSpeed or enemy.speed, now)
		enemy.baseSpeed = nil
	end
end

local function pathLengthOf(state): number
	return if state.playerCount == 2 then Layout.CoopPathLength else Layout.PathLength
end

local function distAt(enemy, t: number): number
	return math.max(0, enemy.speed * (t - enemy.spawnAt))
end

-- Own random stream of one cast (never the gameplay rng): a pure function of the run, the boss and the cast number.
local function castRng(state, boss)
	return Random.new(state.runId * 131071 + boss.id * 8191 + boss.ability.casts)
end

-- Up to `n` distinct entries of `list`, in the stream's order (partial Fisher-Yates on a copy).
local function pickDistinct(rng, list: { number }, n: number): { number }
	local pool, picked = table.clone(list), {}
	for _ = 1, math.min(n, #pool) do
		local at = rng:NextInteger(1, #pool)
		table.insert(picked, pool[at])
		pool[at] = pool[#pool]
		pool[#pool] = nil
	end
	return picked
end

-- Hit points of a Goblin King summon: the wave's last regular slot (state.carriedHp) like the queue, Duel scaling included.
local function summonHp(state, kind: string): number
	local hp = state.carriedHp * Enemies.Kinds[kind].hpMul
	if state.mode == "Duel" then
		hp *= 1 + Balance.Duel.DeathHpPerWave * math.max(0, state.wave - Balance.Duel.DeathWave + 1)
	end
	return math.max(1, math.floor(hp + 0.5))
end

-- Portal Summon: queues the 4 spawns at a portal just ahead of the boss, one every regular spawn interval (none when it
-- is dead or too near the end). Returns that distance and the seconds until the last one is out, or nil when nothing
-- was queued.
local function portalSummon(state, boss, at: number): (number?, number?)
	local cfg = boss.ability.cfg
	local limit = cfg.MaxRouteFraction * pathLengthOf(state)
	local bossDist = distAt(boss, at)
	if boss.hp <= 0 or bossDist > limit then
		return nil, nil
	end
	local dist = math.min(bossDist + cfg.PortalAhead, limit) -- in front of the boss, in its walking direction
	local n = cfg.SummonGrunts + cfg.SummonFast
	local gap = Formulas.SpawnInterval(state.wave)
	for i = 1, n do
		table.insert(state.pending, {
			at = at + gap * (i - 1),
			dist = dist,
			kind = if i == (n + 1) // 2 then "Runner" else "Grunt", -- the fast one in the middle
			seat = boss.seat,
		})
	end
	return dist, gap * (n - 1)
end

-- Creates the portal spawns that are due. SpawnAt is back-dated so dist = speed x (now - spawnAt) is the portal point
-- at its spawn time. They are ordinary enemies but not part of the wave queue, so they never count toward its quota.
local function spawnPending(state, now: number)
	local pending = state.pending
	if #pending == 0 then
		return
	end
	local kept = {}
	for _, p in pending do
		if p.at > now then
			table.insert(kept, p)
			continue
		end
		local speed = Enemies.Kinds[p.kind].speed * Formulas.SpeedMul(state.wave)
		if state.mode == "Duel" then
			speed *= duelSpeedMul(state.wave)
		end
		local hp = summonHp(state, p.kind)
		local enemy = {
			id = state.nextEnemyId,
			kind = p.kind,
			hp = hp,
			maxHp = hp,
			speed = speed,
			spawnAt = p.at - p.dist / speed,
			bornAt = p.at,
			dist = p.dist,
			seat = p.seat,
		}
		state.nextEnemyId += 1
		table.insert(state.enemies, enemy)
		table.insert(state.out.S, {
			Id = enemy.id,
			Kind = enemy.kind,
			SpawnAt = enemy.spawnAt,
			Speed = speed,
			MaxHp = hp,
			Hp = hp,
			Seat = p.seat,
			PlayerCount = state.playerCount,
			Arena = state.mode,
		})
		state.out.dirty = true
	end
	state.pending = kept
end

-- Hammer Lock: locks up to LockCount unlocked dice of the boss's board, never more than MaxLocked held by this boss.
local function hammerLock(state, boss, rng): { number }
	local cfg = boss.ability.cfg
	local board = Match.Seat(state, boss.seat).board
	local free, mine = {}, 0
	for cell = 1, Balance.BoardCells do
		local die = board[cell]
		if die and die.lockedBy == boss.id then
			mine += 1
		elseif die and not die.lockedBy then
			table.insert(free, cell)
		end
	end
	local cells = pickDistinct(rng, free, math.min(cfg.LockCount, cfg.MaxLocked - mine))
	for _, cell in cells do
		board[cell].lockedBy = boss.id
	end
	return cells
end

-- Dice Shuffle: Dice random dice of the boss's board get a random pip 1 to MAX_PIP (type and cell stay).
local function diceShuffle(state, boss, rng): ({ number }, { number })
	local board = Match.Seat(state, boss.seat).board
	local occupied = {}
	for cell = 1, Balance.BoardCells do
		if board[cell] then
			table.insert(occupied, cell)
		end
	end
	local cells, pips = pickDistinct(rng, occupied, boss.ability.cfg.Dice), {}
	for i, cell in cells do
		pips[i] = rng:NextInteger(1, Board.MAX_PIP)
		board[cell].pip = pips[i]
	end
	return cells, pips
end

-- A lock ends the moment the boss that set it is dead or gone.
local function releaseLocks(state)
	local alive
	for _, seat in { state, state.partner } do
		for cell = 1, Balance.BoardCells do
			local die = seat.board[cell]
			if die and die.lockedBy then
				if alive == nil then
					alive = {}
					for _, enemy in state.enemies do
						if enemy.hp > 0 then
							alive[enemy.id] = true
						end
					end
				end
				if not alive[die.lockedBy] then
					die.lockedBy = nil
					state.out.dirty = true
				end
			end
		end
	end
end

-- Applies one boss ability event on the match clock. Replication: windup and cast go out as A records.
local function bossEvent(state, boss, event)
	local out = state.out
	local cfg = boss.ability.cfg
	local phase = event.Phase
	if phase == "windup" then
		boss.held = true
		refreshSpeed(state, boss, event.At)
	elseif phase == "resume" then
		boss.held = nil
		refreshSpeed(state, boss, event.At)
	elseif phase == "cast" then
		local at = event.At
		local variant = boss.ability.variant
		if variant == "GoblinKing" then
			local dist, span = portalSummon(state, boss, at)
			event.Target = dist
			event.Info = if dist then { Distance = dist, Lane = boss.seat, Seconds = span } else nil
		elseif variant == "CursedKing" then
			local cells = hammerLock(state, boss, castRng(state, boss))
			event.Target = if #cells > 0 then cells else nil
			event.Info = { Cells = cells, Seat = boss.seat }
			state.out.dirty = true
		elseif variant == "CourtJester" then
			local cells, pips = diceShuffle(state, boss, castRng(state, boss))
			event.Target = if #cells > 0 then cells else nil
			event.Info = { Cells = cells, Pips = pips, Seat = boss.seat }
			state.out.dirty = true
		end
	end
	if phase ~= "resume" then
		table.insert(out.A, {
			Id = boss.id,
			Ability = cfg.Id,
			Phase = phase,
			At = event.CastAt,
			Target = event.Target,
			Info = event.Info,
		})
	end
end

local abilityEnv = {
	damage = damage,
	refreshSpeed = refreshSpeed,
	updateEnemy = updateEnemy,
	pathLength = pathLengthOf,
}

local function attack(state, seat, index: number, now: number)
	local enemies = state.enemies
	local auras = Match.Auras(seat)
	local singularity = Formulas.HasSingularity(seat.board)
	local restrictLane = state.partner ~= nil
	local duel = state.mode == "Duel"
	-- A Duel die only sees its own lane; Co-op also shares the stretch past the junction.
	-- A new enemy is out of reach for Balance.SpawnGrace seconds (bornAt is nil only for enemies a spec builds by hand).
	local function reachable(enemy): boolean
		return enemy.hp > 0
			and (enemy.bornAt == nil or now - enemy.bornAt >= Balance.SpawnGrace)
			and (not restrictLane or enemy.seat == index or (not duel and enemy.dist >= Layout.CoopJunction))
	end
	for cell = 1, Balance.BoardCells do
		local die = seat.board[cell]
		if die and die.lockedBy then
			die.cd = math.max(die.cd, now) -- a locked die neither fires nor banks shots
		elseif die then
			local cfg = Match.DieCfg(seat, die.type)
			local classMul = Match.ClassMul(seat, die.type)
			local ab = cfg
			Abilities.Timers(abilityEnv, state, die, ab, now, reachable)
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
						if
							first == nil
							or (if cfg.targeting == "Strongest" then enemy.hp > first.hp else enemy.dist > first.dist)
						then
							first = enemy
						end
					end
				end
				if first == nil then
					die.cd = now -- idle cooldown does not bank
					break
				end
				-- Every target is chosen before any shot deals damage.
				local shots = cfg.shots or 1
				local targets = { first }
				if shots > 1 and alive > 1 then
					local pool = {}
					for _, enemy in enemies do
						if reachable(enemy) and (not cfg.spread or enemy ~= first) then
							table.insert(pool, enemy)
						end
					end
					for shot = 2, shots do
						if cfg.spread then
							if #pool > 0 then
								local at = state.rng:NextInteger(1, #pool)
								targets[shot] = pool[at]
								pool[at] = pool[#pool]
								pool[#pool] = nil
							else
								targets[shot] = first
							end
						elseif cfg.diffChance then
							-- Twinshot: the extra shot picks another enemy with diffChance, else it joins the first
							local others = {}
							for _, enemy in pool do
								if enemy ~= first then
									table.insert(others, enemy)
								end
							end
							targets[shot] = if #others > 0 and state.rng:NextNumber() < cfg.diffChance
								then others[state.rng:NextInteger(1, #others)]
								else first
						else
							targets[shot] = pool[state.rng:NextInteger(1, #pool)] -- may repeat the first
						end
					end
				end
				die.hits += 1
				local flat = if cfg.procEvery and die.hits % cfg.procEvery == 0
					then math.floor(cfg.procFlat * classMul + 1e-9)
					else 0
				local supportCells = if die.type == "R05" then Match.SupportCells(seat, die.type, cell) else nil
				local lastAmount = 0
				for shot = 1, shots do
					local target = targets[shot] or first
					local critical = Formulas.SingularityCrit(die.type, singularity, state.critRng, state.critChance)
					local amount = Formulas.HitDamage(
						die.type,
						target.kind,
						if shot == 1 then flat else 0,
						tier,
						singularity,
						critical,
						seat.critBonus,
						cfg,
						classMul
					)
					lastAmount = amount -- the cascade and pierce hits scale from the full hit
					if ab.cascade then
						amount = math.max(1, math.floor(amount * ab.cascade[1]))
					end
					damage(state, target, amount)
					local slowed = Abilities.OnHit(abilityEnv, state, die, ab, target, now)
					table.insert(state.out.F, {
						Cell = cell,
						Seat = index,
						PlayerCount = state.playerCount,
						Arena = state.mode,
						Id = target.id,
						Type = die.type,
						Distance = if showProjectile then target.dist else nil,
						-- Seconds the shot is in the air; the client lands the hit (HP bar, damage number) on this clock.
						Flight = if showProjectile
							then ProjectileFlight.Seconds(
								die.type,
								cell,
								index,
								target.seat,
								target.dist,
								state.mode or state.playerCount
							)
							else nil,
						Boosted = if showProjectile and flat > 0 then true else nil,
						Critical = if critical then true else nil,
						Damage = amount, -- floating damage number (display only)
						Slowed = if showProjectile and slowed then true else nil,
						SlowUntil = if slowed then target.slowUntil else nil,
						PoisonUntil = if ab.poison and target.hp > 0 then now + ab.poison.duration else nil,
						SupportCells = supportCells,
						Lane = if twinshot then (if shot == 1 then 1 else -1) else nil,
						SharedTarget = if twinshot and first == (targets[2] or first) then true else nil,
					})
				end
				Abilities.OnAttack(abilityEnv, state, die, ab, first, lastAmount, reachable)
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
		if state.mode == "Duel" and not state.bossSpawned and state.qi > #state.queue then
			local clear = true
			for _, enemy in state.enemies do
				if enemy.hp > 0 then
					clear = false
					break
				end
			end
			if clear or now >= state.waveStartAt + Match.RoundTime(state.wave) then
				spawnDuelBosses(state, now)
			end
		end
	end

	-- Move + breach. dist is a pure function of time so clients can reproduce it.
	spawnPending(state, now)
	local survivors = {}
	local duel = state.mode == "Duel"
	for _, enemy in state.enemies do
		if enemy.ability then
			for _, event in BossAbilities.Tick(enemy.ability, now) do
				bossEvent(state, enemy, event)
			end
		end
		if enemy.slowUntil and now >= enemy.slowUntil then
			local at = enemy.slowUntil
			enemy.slowUntil, enemy.slowMul = nil, nil
			refreshSpeed(state, enemy, at)
		end
		if enemy.frozenUntil and now >= enemy.frozenUntil then
			local at = enemy.frozenUntil
			enemy.frozenUntil, enemy.frozen = nil, nil
			refreshSpeed(state, enemy, at)
		end
		enemy.dist = math.max(0, enemy.speed * (now - enemy.spawnAt))
		-- Duel lanes are the same 124-stud balance length as Co-op (docs/DICE_RATING.md section 5).
		local pathLength = pathLengthOf(state)
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
	releaseLocks(state)
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

	Abilities.Tick(abilityEnv, state, now, dt)

	-- Deaths + kill MP.
	local alive = {}
	local poisoned = {}
	for _, enemy in survivors do
		if enemy.hp <= 0 then
			local gain = Formulas.KillMp(enemy.kind, state.wave)
			if duel then
				-- Owner spec: regular kill = min(110, 10 x wave) SP, a boss 2x that (max 220).
				gain = math.min(Balance.Duel.BerserkMp, Balance.Duel.KillMpPerWave * state.wave)
					* (if enemy.kind == "Boss" then Balance.Duel.BossKillMul else 1)
			end
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
			if enemy.dots then
				table.insert(poisoned, enemy)
			end
		else
			table.insert(alive, enemy)
		end
	end
	for _, dead in poisoned do
		Abilities.SpreadPoison(dead, alive, now)
	end
	state.enemies = alive
	releaseLocks(state)

	-- Wave clear.
	if
		state.waveState == "Active"
		and state.qi > #state.queue
		and #alive == 0
		and #state.pending == 0
		and (state.mode ~= "Duel" or state.bossSpawned)
	then
		state.wavesCompleted = state.wave
		state.out.dirty = true
		state.waveState = "Prep"
		state.nextWaveAt = now + Balance.WaveGap
		state.bossAt = if state.mode ~= "Duel" and CoopWaves.IsBoss(state.wave + 1) then state.nextWaveAt else nil
	end
end

return Match
