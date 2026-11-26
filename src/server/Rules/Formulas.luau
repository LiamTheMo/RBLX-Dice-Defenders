-- Formulas from docs/MVP.md. Random rolls use a caller-supplied server RNG.
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

-- Gems for clearing wave `w` (Balance.WaveGems). Gem waves follow the Random Dice card table, not the enemy schedule:
-- up to 35 boss = every 5th, mini-boss = w % 5 == 3; from 36 odd waves are boss waves, even waves mini-boss waves.
function Formulas.WaveGems(w: number): number
	local boss = if w <= 35 then w % 5 == 0 else w % 2 == 1
	local mini = if w <= 35 then w % 5 == 3 else w % 2 == 0
	for _, b in Balance.WaveGems do
		if w <= b.maxWave then
			return if boss then b.boss elseif mini then b.brute else b.wave
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

-- Duel XP and Gems for `waves` cleared (Balance.DuelReward): winner full, loser reduced, bot match scaled; floored.
function Formulas.DuelReward(waves: number, won: boolean, vsBot: boolean): (number, number)
	local cfg = Balance.DuelReward
	local w = math.min(waves, cfg.MaxWaves)
	local scale = if vsBot then cfg.BotFactor else 1
	local xp = math.floor(Formulas.RewardXp(w) * (if won then 1 else cfg.LossXpFactor) * scale)
	local gems = math.floor(Formulas.RewardGems(w) * (if won then 1 else cfg.LossGemFactor) * scale)
	return xp, gems
end

-- Seconds between attacks: each pip is its own shooter (rate x PipRate[pip]); `aura` is the attack-speed
-- bonus (a fraction) the die receives from adjacent aura dice.
function Formulas.Period(typeId: string, pip: number, aura: number?): number
	return 1 / (Dice.Types[typeId].rate * Balance.PipRate[pip] * (1 + (aura or 0)))
end

-- Damage multiplier of Power Up tier 1..Balance.PowerUp.Max.
function Formulas.TierMul(tier: number): number
	return 1 + Balance.PowerUp.DamagePerTier * (tier - 1)
end

-- MP to buy tier + 1 from `tier`; nil at the maximum tier.
function Formulas.PowerUpCost(tier: number): number?
	return Balance.PowerUp.Costs[tier]
end

-- Attack-speed bonus (a fraction) a die gives each orthogonal neighbour; 0 for a die without an aura.
function Formulas.Aura(typeId: string, pip: number, tier: number): number
	local aura = Dice.Types[typeId].aura
	if aura == nil then
		return 0
	end
	return aura.base + aura.perPip * (pip - 1) + aura.perTier * (tier - 1)
end

function Formulas.HasSingularity(board): boolean
	local found = false
	for _, die in board do
		if die and die.type == "M01" then
			if found then
				return false
			end
			found = true
		end
	end
	return found
end

function Formulas.SingularityCrit(typeId: string, active: boolean, rng: any): boolean
	local ability = Dice.Types[typeId].singularity
	return active and ability ~= nil and rng:NextInteger(1, 100) <= ability.critChance
end

-- Damage of one shot: base x perks x Power Up x active ability, rounded down.
-- `procFlat` is the flat bonus already earned by the caller (Needle's every-6th-hit), added afterwards.
function Formulas.HitDamage(
	typeId: string,
	kind: string,
	procFlat: number?,
	tier: number?,
	singularity: boolean?,
	critical: boolean?,
	critBonus: number? -- account crit damage percent from die levels (Upgrade.CritBonus), added to the crit multiplier
): number
	local cfg = Dice.Types[typeId]
	local enemy = Enemies.Kinds[kind]
	local perk = 1
	if cfg.vsKind and cfg.vsKind[kind] then
		perk *= cfg.vsKind[kind]
	end
	if cfg.vsArmored and enemy.armored then
		perk *= cfg.vsArmored
	end
	if singularity and cfg.singularity then
		perk *= cfg.singularity.damage * (if critical then cfg.singularity.critDamage + (critBonus or 0) / 100 else 1)
	end
	-- 1e-9 keeps an exact product such as 10 x 1.3 from flooring one short on float noise.
	return math.max(1, math.floor(cfg.base * perk * Formulas.TierMul(tier or 1) + 1e-9)) + (procFlat or 0)
end

return Formulas
