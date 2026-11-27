-- Die abilities beyond plain damage (docs/DICE_REBALANCE_PROPOSAL.md): status effects on enemies, per-die timers and the
-- merge/summon hooks. Data lives in Config/Dice; Match owns the clock, the enemy list and speed bookkeeping, and hands
-- the few helpers this module needs in through `env`: { damage, refreshSpeed, updateEnemy, pathLength }.
-- Guardrails: slows cap at 60% (bosses 50%), bosses never freeze or rewind, one enemy rewinds at most `maxRewinds`
-- times, and a proc never triggers another proc (chains and pierce only deal damage).
local Board = require(script.Parent.Board)
local Dice = require(script.Parent.Parent.Config.Dice)

local Abilities = {}

local SLOW_CAP, BOSS_SLOW_CAP = 0.60, 0.50
local RARITY_RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5, Secret = 6 }
-- Perk keys a Mirror can borrow (aura, forge and singularity are positional or global, so never copied).
local COPYABLE = {
	"slow",
	"slowDuration",
	"slowChance",
	"freezeEvery",
	"freezeFor",
	"chainEvery",
	"chainCount",
	"chainMul",
	"poison",
	"burn",
	"detonate",
	"pull",
	"rift",
	"pierce",
	"wyrmfire",
}

-- The ability view of a die at `now`: its own config, or the Mirror view while a copy is active.
function Abilities.Of(die, now: number)
	local m = die.mirror
	if m and now < m.endsAt then
		return m.view
	end
	return Dice.Types[die.type]
end

-- Mirror: copy the perk set of the highest-rarity adjacent die (not another Mirror, not Astral) for mirror.duration.
function Abilities.Copy(board, cell: number, now: number)
	local die = board[cell]
	local own = die and Dice.Types[die.type]
	if not (own and own.mirror) then
		return
	end
	local best, bestRank
	for _, n in Board.Neighbours(cell) do
		local other = board[n]
		local cfg = other and Dice.Types[other.type]
		if cfg and not cfg.mirror and not cfg.singularity then
			local rank = RARITY_RANK[cfg.rarity]
			for _, key in COPYABLE do
				if cfg[key] ~= nil and (bestRank == nil or rank > bestRank) then
					best, bestRank = cfg, rank
					break
				end
			end
		end
	end
	if not best then
		die.mirror = nil
		return
	end
	local view = table.clone(own)
	for _, key in COPYABLE do
		view[key] = best[key]
	end
	die.mirror = { endsAt = now + own.mirror.duration, view = view }
end

-- Enemy status helpers ------------------------------------------------------------

-- shortcut: the strongest slow wins and lasts until the latest end; a weaker slow still running is not restored.
function Abilities.Slow(env, state, enemy, fraction: number, duration: number, now: number)
	local cap = if enemy.kind == "Boss" then BOSS_SLOW_CAP else SLOW_CAP
	local mul = 1 - math.min(fraction, cap)
	if enemy.slowMul == nil or mul < enemy.slowMul then
		enemy.slowMul = mul
		env.refreshSpeed(state, enemy, now)
	end
	enemy.slowUntil = math.max(enemy.slowUntil or 0, now + duration)
end

function Abilities.Freeze(env, state, enemy, duration: number, now: number)
	if enemy.kind == "Boss" then
		return
	end
	enemy.frozen = true
	enemy.frozenUntil = math.max(enemy.frozenUntil or 0, now + duration)
	env.refreshSpeed(state, enemy, now)
end

-- Pushes an enemy back along the lane by `fraction` of its length (the client re-derives dist from SpawnAt).
function Abilities.Rewind(env, state, enemy, fraction: number, now: number)
	local dist = math.max(0, enemy.speed * (now - enemy.spawnAt) - fraction * env.pathLength(state))
	enemy.spawnAt = now - dist / enemy.speed
	enemy.dist = dist
	env.updateEnemy(state, enemy)
end

local function addDot(enemy, key: string, dps: number, endsAt: number)
	enemy.dots = enemy.dots or {}
	enemy.dots[key] = { dps = dps, endsAt = endsAt }
end

-- Per-hit effects --------------------------------------------------------------------

-- Called after a shot damaged `target`. Returns true when a slow was applied (for the shot record).
function Abilities.OnHit(env, state, die, ab, target, now: number): boolean
	if target.hp <= 0 then
		return false
	end
	local slowed = false
	if ab.slow and (ab.slowChance == nil or state.rng:NextNumber() < ab.slowChance) then
		Abilities.Slow(env, state, target, ab.slow, ab.slowDuration, now)
		slowed = true
	end
	if ab.freezeEvery and die.hits % ab.freezeEvery == 0 then
		Abilities.Freeze(env, state, target, ab.freezeFor, now)
	end
	if ab.poison then
		local key = "p" .. die.id
		local dot = target.dots and target.dots[key]
		local stacks = math.min(ab.poison.maxStacks, (if dot then dot.stacks else 0) + 1)
		addDot(target, key, ab.poison.dps * stacks, now + ab.poison.duration)
		target.dots[key].stacks = stacks
		target.dots[key].poison = true
	end
	if ab.burn then
		addDot(target, "burn", ab.burn.dps, now + ab.burn.duration)
		target.dots.burn.burn = true
	end
	return slowed
end

-- Called once per attack after its shots: chain lightning and piercing damage.
function Abilities.OnAttack(env, state, die, ab, first, amount: number, reach)
	local enemies = state.enemies
	if ab.chainEvery and die.hits % ab.chainEvery == 0 then
		local pool = {}
		for _, e in enemies do
			if e ~= first and reach(e) then
				table.insert(pool, e)
			end
		end
		for _ = 1, math.min(ab.chainCount, #pool) do
			local at = state.rng:NextInteger(1, #pool)
			env.damage(state, pool[at], math.max(1, math.floor(amount * ab.chainMul)))
			pool[at] = pool[#pool]
			pool[#pool] = nil
		end
	end
	if ab.pierce then
		local behind = {}
		for _, e in enemies do
			if e ~= first and reach(e) and e.dist <= first.dist then
				table.insert(behind, e)
			end
		end
		table.sort(behind, function(a, b)
			return a.dist > b.dist
		end)
		for i = 1, math.min(ab.pierce, #behind) do
			env.damage(state, behind[i], amount)
		end
	end
end

-- Timers -------------------------------------------------------------------------------

local function due(die, key: string, every: number, now: number): boolean
	die.nextAt = die.nextAt or {}
	local at = die.nextAt[key]
	if at == nil then
		die.nextAt[key] = now + every
		return false
	end
	if now >= at then
		die.nextAt[key] = math.max(at + every, now + 0.001)
		return true
	end
	return false
end

local function lane(state, reach)
	local list = {}
	for _, e in state.enemies do
		if reach(e) then
			table.insert(list, e)
		end
	end
	return list
end

function Abilities.Timers(env, state, die, ab, now: number, reach)
	if ab.detonate and due(die, "detonate", ab.detonate.every, now) then
		local blasted = {}
		for _, e in lane(state, reach) do
			local burn = e.dots and e.dots.burn
			if burn then
				env.damage(state, e, math.floor(burn.dps * math.max(0, burn.endsAt - now)))
				e.dots.burn = nil
				table.insert(blasted, e.dist)
			end
		end
		local burn = ab.burn or Dice.Types.E01.burn
		for _, e in lane(state, reach) do
			for _, at in blasted do
				if math.abs(e.dist - at) <= ab.detonate.radius then
					addDot(e, "burn", burn.dps, now + burn.duration)
					e.dots.burn.burn = true
					break
				end
			end
		end
	end
	if ab.pull and due(die, "pull", ab.pull.every, now) then
		local normal = {}
		for _, e in lane(state, reach) do
			if e.kind == "Boss" then
				Abilities.Slow(env, state, e, ab.pull.bossSlow, ab.pull.bossSlowFor, now)
			else
				table.insert(normal, e)
			end
		end
		table.sort(normal, function(a, b)
			return a.dist > b.dist
		end)
		for i = 1, math.min(ab.pull.count, #normal) do
			Abilities.Rewind(env, state, normal[i], ab.pull.back, now)
		end
	end
	if ab.rift and due(die, "rift", ab.rift.every, now) then
		local list = lane(state, reach)
		local lead
		for _, e in list do
			if e.kind ~= "Boss" and (lead == nil or e.dist > lead.dist) then
				lead = e
			end
		end
		lead = lead or list[1]
		if lead then
			die.rifts = (die.rifts or 0) + 1
			local rewind = die.rifts % ab.rift.rewindEvery == 0
			for _, e in list do
				if math.abs(e.dist - lead.dist) <= ab.rift.radius then
					Abilities.Slow(
						env,
						state,
						e,
						if e.kind == "Boss" then ab.rift.bossSlow else ab.rift.slow,
						ab.rift.duration,
						now
					)
					if rewind and e.kind ~= "Boss" and (e.rewinds or 0) < ab.rift.maxRewinds then
						e.rewinds = (e.rewinds or 0) + 1
						Abilities.Rewind(env, state, e, ab.rift.rewind, now)
					end
				end
			end
		end
	end
	if ab.wyrmfire and due(die, "wyrmfire", ab.wyrmfire.every, now) then
		for _, e in lane(state, reach) do
			local pct = if e.kind == "Boss" then ab.wyrmfire.bossPct else ab.wyrmfire.pct
			addDot(e, "w" .. die.id, pct * e.maxHp, now + ab.wyrmfire.duration)
		end
	end
end

-- Damage over time -----------------------------------------------------------------------

-- Applies every DoT for `dt` seconds (whole HP only; the fraction is carried) and drops the ended ones.
function Abilities.Tick(env, state, now: number, dt: number)
	for _, e in state.enemies do
		local dots = e.dots
		if dots and e.hp > 0 then
			local total = 0
			for key, dot in dots do
				total += dot.dps * dt
				if now >= dot.endsAt then
					dots[key] = nil
				end
			end
			total += e.dotCarry or 0
			local whole = math.floor(total)
			e.dotCarry = total - whole
			if whole > 0 then
				env.damage(state, e, whole)
			end
			if next(dots) == nil then
				e.dots = nil
			end
		end
	end
end

-- A poisoned enemy died: its poison stacks jump to the nearest living enemy on the same lane.
function Abilities.SpreadPoison(dead, alive: { any }, now: number)
	local best, gap
	for _, e in alive do
		if e.hp > 0 and e.seat == dead.seat then
			local d = math.abs(e.dist - dead.dist)
			if gap == nil or d < gap then
				best, gap = e, d
			end
		end
	end
	if best then
		for key, dot in dead.dots do
			if dot.poison and now < dot.endsAt then
				best.dots = best.dots or {}
				best.dots[key] = { dps = dot.dps, endsAt = dot.endsAt, stacks = dot.stacks, poison = true }
			end
		end
	end
end

return Abilities
