-- Random Dice enemy HP model (community data-mining, as the owner pasted it). Units are Roblox HP.
-- A wave's regular monsters have Base HP = b + d x n: b is the wave's start (InitialHp on wave 1, then the last regular
-- monster's Base HP of the wave before), d the flat step for the wave, n the spawn slot 1..10. Actual HP is the Base HP
-- times the kind's multiplier: Fast (Runner) x0.5, Mini-Boss (Brute) x(5 + 1.5 (k-1)), Boss x(10 + 1.5 (k-1)), where k is
-- how many of that kind have appeared up to and including this wave.
local CoopWaves = {}

CoopWaves.InitialHp = 100
local SLOTS = 10 -- regular monsters per wave

-- Flat HP added per slot (owner's exact Random Dice formula): d(1) = 10 and d(w) = d(w-1) + Delta(w) with
-- Delta(w) = 10 x ceil(w / 10) for 2 <= w <= 50 (d(10) = 100, d(11) = 120, d(20) = 300, d(50) = 1500) and
-- 50 x ceil(w / 10) from wave 51 (d(51) = 1800, d(60) = 4500, d(111) = 27600), unbounded. All integers, exact in a double
-- (wave 1500: b ~ 2.8e10, far below 2^53).
local FIRST_STEP, LAST_LINEAR_WAVE = 10, 50

-- Schedule (owner's spec): a boss every 5th wave up to 35, then on odd waves (a boss wave is one enemy, never doubled). A
-- mini-boss (brute) on waves ending in 4 or 9 up to 35, then on waves ending in 3 or 8; a boss wave wins a clash (43, 53, 63 ...).
-- Past wave 50 the mini-boss cadence is unspecified: the 36-50 rule simply continues.
function CoopWaves.IsBoss(wave: number): boolean
	return if wave <= 35 then wave % 5 == 0 else wave % 2 == 1
end

function CoopWaves.HasBrute(wave: number): boolean
	return if wave <= 35 then wave % 5 == 4 else wave % 5 == 3 and not CoopWaves.IsBoss(wave)
end

function CoopWaves.Step(wave: number): number
	local d = FIRST_STEP
	for w = 2, wave do
		d += (if w <= LAST_LINEAR_WAVE then 10 else 50) * math.ceil(w / 10)
	end
	return d
end

local function countUpTo(pred: (number) -> boolean, wave: number): number
	local n = 0
	for v = 1, wave do
		if pred(v) then
			n += 1
		end
	end
	return n
end

-- `base` is this wave's b. Returns the wave's queue and the next wave's b (this wave's last regular monster's Base HP).
-- `plain` (1v1 Duel): ten mobs every wave, no Co-op boss or brute; the Duel boss is added by Match at wave end
-- (docs/_archive/DUEL_SCALING.md). Runners grow with the wave instead.
function CoopWaves.Next(wave: number, base: number, plain: boolean?)
	local d = CoopWaves.Step(wave)
	local boss, brute = CoopWaves.IsBoss(wave), CoopWaves.HasBrute(wave)
	if plain then
		boss, brute = false, false
	end
	local count = if boss then 1 else SLOTS
	local runnerCount = if plain then math.min(5, wave // 3) else 0
	if brute then
		runnerCount = if wave <= 60
			then math.ceil(wave / 10)
			elseif wave >= 85 then 9
			elseif wave >= 75 then 8
			elseif wave >= 67 then 7
			else 6
	end
	local queue = table.create(count)
	for slot = 1, count do
		local hp = base + d * slot
		local kind = "Grunt"
		if boss then
			kind = "Boss"
			hp *= 10 + 1.5 * (countUpTo(CoopWaves.IsBoss, wave) - 1)
		elseif brute and slot == 1 then
			kind = "Brute"
			hp *= 5 + 1.5 * (countUpTo(CoopWaves.HasBrute, wave) - 1)
		elseif slot > SLOTS - runnerCount then
			kind = "Runner"
			hp /= 2
		end
		queue[slot] = { kind = kind, hp = math.max(1, math.floor(hp + 0.5)) }
	end
	return queue, base + d * SLOTS
end

return table.freeze(CoopWaves)
