-- Pure formulas from docs/MVP.md. No state, no randomness.
local Balance = require(script.Parent.Parent.Config.Balance)
local Dice = require(script.Parent.Parent.Config.Dice)
local Enemies = require(script.Parent.Parent.Config.Enemies)

local Formulas = {}

-- MP cost of the next summon after `summons` successful ones.
function Formulas.SummonCost(summons: number): number
	local c = Balance.SummonCost
	return c.base + c.step * summons
end

function Formulas.WaveCount(w: number): number
	return math.min(45, 8 + math.floor(0.35 * (w - 1)))
end

function Formulas.SpawnInterval(w: number): number
	return math.clamp(1.6 - 0.007 * w, 0.35, 1.6)
end

function Formulas.SpeedMul(w: number): number
	return math.min(1.6, 1 + 0.006 * (w - 1))
end

function Formulas.EnemyHp(kind: string, w: number): number
	local c = Balance.EnemyHp
	local growth, from = 1, 1
	for _, band in c.growth do
		local to = math.min(w, band.toWave)
		if to > from then
			growth *= (1 + band.rate) ^ (to - from)
			from = to
		end
	end
	local ease = math.min(1, c.easeFrom + (1 - c.easeFrom) * (w - 1) / c.easeWaves) -- the first waves face the 4 starting dice
	return math.floor(c.base * growth * ease * Enemies.Kinds[kind].hpMul + 0.5)
end

-- Enemy kind of the 1-based spawn index `i` in wave `w` (the Brute and Boss are queued separately).
function Formulas.KindAt(w: number, i: number): string
	if w >= 3 and i % 3 == 0 then
		return "Runner"
	end
	return "Grunt"
end

function Formulas.IsBoss(w: number): boolean
	return w % 5 == 0
end

function Formulas.HasBrute(w: number): boolean
	return (w >= 3 and w <= 33 and (w - 3) % 5 == 0) or (w >= 36 and w % 2 == 0)
end

-- MP for a kill in wave `w`.
function Formulas.KillMp(kind: string, w: number): number
	local band = 0
	for _, b in Balance.KillMp do
		if w <= b.maxWave then
			band = b.mp
			break
		end
	end
	if kind == "Brute" then
		return band * Balance.BruteMpMul
	elseif kind == "Boss" then
		return band * Balance.BossMpMul
	end
	return band
end

-- Run reward parts for `waves` cleared.
function Formulas.RewardGold(waves: number): number
	return Balance.Reward.goldPerWave * waves
end

function Formulas.RewardXp(waves: number): number
	return Balance.Reward.xpPerWave * waves
end

function Formulas.RewardFragments(waves: number): number
	return Balance.Reward.fragmentsPerWave * waves
end

-- Gems for clearing wave `w` (Balance.WaveGems).
function Formulas.WaveGems(w: number): number
	for _, b in Balance.WaveGems do
		if w <= b.maxWave then
			return if Formulas.IsBoss(w) then b.boss elseif Formulas.HasBrute(w) then b.brute else b.wave
		end
	end
	return 0
end

function Formulas.RewardGems(waves: number): number
	local sum = 0
	for w = 1, waves do
		sum += Formulas.WaveGems(w)
	end
	return sum
end

function Formulas.Period(typeId: string): number
	return 1 / Dice.Types[typeId].rate
end

-- Damage of one shot. `procFlat` is the flat bonus already earned by the caller
-- (Needle's every-6th-hit), added after the multiplicative part.
function Formulas.HitDamage(typeId: string, pip: number, kind: string, procFlat: number?): number
	local cfg = Dice.Types[typeId]
	local enemy = Enemies.Kinds[kind]
	local perk = cfg.shotMul or 1
	if cfg.vsKind and cfg.vsKind[kind] then
		perk *= cfg.vsKind[kind]
	end
	if cfg.vsArmored and enemy.armored then
		perk *= cfg.vsArmored
	end
	return math.max(1, math.floor(cfg.base * pip ^ 0.85 * perk)) + (procFlat or 0)
end

return Formulas
