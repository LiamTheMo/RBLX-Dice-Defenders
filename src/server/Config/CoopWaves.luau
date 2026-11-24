-- Reconstructed v5.2.4 co-op HP progression. One Roblox HP represents 1/0.18 of the reference HP.
-- Source measurements and version limits are recorded in docs/COOP_SCALING.md.
local CoopWaves = {}

CoopWaves.InitialHp = 100
CoopWaves.HpScale = 0.18

-- Current-game schedule (randomdice.gg): a boss every 5th wave up to 35, then a boss on odd waves; a mini-boss (brute)
-- on waves 3, 8 ... 33, then on even waves from 36. (The measured v5.2.4 HP curve below predates it.)
function CoopWaves.IsBoss(wave: number): boolean
	return if wave <= 35 then wave % 5 == 0 else wave % 2 == 1
end

function CoopWaves.HasBrute(wave: number): boolean
	return if wave <= 35 then wave % 5 == 3 else wave % 2 == 0
end

-- Ordinal of the boss/brute coefficient: it grows 1.5 per decade to wave 60, then per two waves (the v5.2.4 measurement).
local function ordinal(wave: number): number
	return if wave <= 60 then math.ceil(wave / 10) else 6 + math.ceil((wave - 60) / 2)
end

-- `plain` (1v1 Duel): ten mobs every wave, no Co-op boss or brute; the Duel boss is added by Match at wave end
-- (docs/DUEL_SCALING.md). Runners grow with the wave instead.
function CoopWaves.Next(wave: number, carriedHp: number, hpStep: number, plain: boolean?)
	local change = if wave == 189
		then 2800
		elseif wave >= 60 then 80 * math.ceil(wave / 10)
		else 10 * math.ceil(wave / 10)
	hpStep += change
	local boss, brute = CoopWaves.IsBoss(wave), CoopWaves.HasBrute(wave)
	if plain then
		boss, brute = false, false
	end
	local count = if boss then 1 else 10
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
		local rawHp = carriedHp + hpStep * slot
		local kind = "Grunt"
		if boss then
			-- Waves 5, 15 ... were 5x minibosses in the measured curve: keep their HP, only the schedule changed.
			local base = if wave <= 60 and wave % 10 == 5 then 5 else 10
			kind, rawHp = "Boss", rawHp * (base + 1.5 * (ordinal(wave) - 1))
		elseif brute and slot == 1 then
			-- The new miniboss waves (3, 8, 13 ...) are softer than the old 5x: calibrated so starter decks keep ending near the
			-- same wave (tools/balance_sim.py).
			local base = if wave <= 35 then 2 else 5
			kind, rawHp = "Brute", rawHp * (base + 1.5 * (ordinal(wave) - 1))
		elseif slot > 10 - runnerCount then
			kind, rawHp = "Runner", rawHp / 2
		end
		queue[slot] = { kind = kind, hp = math.max(1, math.floor(rawHp * CoopWaves.HpScale + 0.5)), rawHp = rawHp }
	end
	-- A boss on a wave that used to be a 10-mob miniboss wave (5, 15 ...) still advances the carry by ten steps, so the
	-- measured HP of every later wave is unchanged.
	local carrySlots = if boss and wave <= 60 and wave % 10 == 5 then 10 else count
	return queue, carriedHp + hpStep * carrySlots, hpStep
end

return table.freeze(CoopWaves)
