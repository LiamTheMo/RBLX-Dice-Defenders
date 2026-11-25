-- Random Dice enemy HP model (community data-mining, as the owner pasted it). Units are Roblox HP.
-- A wave's regular monsters have Base HP = b + d x n: b is the wave's start (InitialHp on wave 1, then the last regular
-- monster's Base HP of the wave before), d the flat step for the wave, n the spawn slot 1..10. Actual HP is the Base HP
-- times the kind's multiplier: Fast (Runner) x0.5, Mini-Boss (Brute) x(5 + 1.5 (k-1)), Boss x(10 + 1.5 (k-1)), where k is
-- how many of that kind have appeared up to and including this wave. The Step values below are placeholders to tune.
local CoopWaves = {}

CoopWaves.InitialHp = 100
local SLOTS = 10 -- regular monsters per wave

-- Flat HP added per slot: { from wave, d } ascending; from wave 25 it grows by StepGrowth every StepEvery waves.
local STEPS = { { 1, 30 }, { 5, 60 }, { 10, 90 }, { 15, 150 }, { 20, 300 }, { 25, 450 } }
local STEP_EVERY, STEP_GROWTH = 5, 150

-- Current-game schedule (randomdice.gg): a boss every 5th wave up to 35, then a boss on odd waves; a mini-boss (brute)
-- on waves 3, 8 ... 33, then on even waves from 36.
function CoopWaves.IsBoss(wave: number): boolean
	return if wave <= 35 then wave % 5 == 0 else wave % 2 == 1
end

function CoopWaves.HasBrute(wave: number): boolean
	return if wave <= 35 then wave % 5 == 3 else wave % 2 == 0
end

function CoopWaves.Step(wave: number): number
	if wave >= 25 then
		return 450 + STEP_GROWTH * ((wave - 25) // STEP_EVERY)
	end
	local d = STEPS[1][2]
	for _, s in STEPS do
		if wave >= s[1] then
			d = s[2]
		end
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
-- (docs/DUEL_SCALING.md). Runners grow with the wave instead.
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
