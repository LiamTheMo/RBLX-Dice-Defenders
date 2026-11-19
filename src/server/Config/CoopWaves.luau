-- Reconstructed v5.2.4 co-op HP progression. One Roblox HP represents 1/0.18 of the reference HP.
-- Source measurements and version limits are recorded in docs/COOP_SCALING.md.
local CoopWaves = {}

CoopWaves.InitialHp = 100
CoopWaves.HpScale = 0.18

function CoopWaves.IsBoss(wave: number): boolean
	return if wave <= 60 then wave % 10 == 0 else wave % 2 == 0
end

function CoopWaves.HasBrute(wave: number): boolean
	return if wave <= 60 then wave % 10 == 5 else wave % 2 == 1
end

function CoopWaves.Next(wave: number, carriedHp: number, hpStep: number)
	local change = if wave == 189
		then 2800
		elseif wave >= 60 then 80 * math.ceil(wave / 10)
		else 10 * math.ceil(wave / 10)
	hpStep += change
	local boss, brute = CoopWaves.IsBoss(wave), CoopWaves.HasBrute(wave)
	local count = if boss then 1 else 10
	local runnerCount = 0
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
			local ordinal = if wave <= 60 then wave / 10 else 6 + (wave - 60) / 2
			kind, rawHp = "Boss", rawHp * (10 + 1.5 * (ordinal - 1))
		elseif brute and slot == 1 then
			local ordinal = if wave <= 60 then math.ceil(wave / 10) else 6 + (wave - 59) / 2
			kind, rawHp = "Brute", rawHp * (5 + 1.5 * (ordinal - 1))
		elseif slot > 10 - runnerCount then
			kind, rawHp = "Runner", rawHp / 2
		end
		queue[slot] = { kind = kind, hp = math.max(1, math.floor(rawHp * CoopWaves.HpScale + 0.5)), rawHp = rawHp }
	end
	return queue, carriedHp + hpStep * count, hpStep
end

return table.freeze(CoopWaves)
