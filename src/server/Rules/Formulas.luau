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
	return math.floor(80 * (1 + 0.018 * (w - 1)) * Enemies.Kinds[kind].hpMul + 0.5)
end

function Formulas.Stipend(w: number): number
	return 30 + 5 * math.floor(w / 10)
end

-- Enemy kind of the 1-based spawn index `i` in wave `w` (the boss is queued separately).
function Formulas.KindAt(w: number, i: number): string
	if w >= 5 and i % 5 == 0 then
		return "Brute"
	elseif w >= 3 and i % 3 == 0 then
		return "Runner"
	end
	return "Grunt"
end

function Formulas.RewardGold(wavesCompleted: number): number
	return Balance.Reward.gold + Balance.Reward.goldPerWave * wavesCompleted
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
