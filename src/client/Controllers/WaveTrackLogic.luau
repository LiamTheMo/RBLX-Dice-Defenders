-- Wave track pure logic (display only): which waves the HUD strip under the top bar shows and how each is drawn.
-- No Roblox APIs (unit-tested headless). The server owns the real schedule (CoopWaves.IsBoss); this mirrors it for display
-- and tests/luau/wavetrack.spec.luau cross-checks the two.

local WaveTrackLogic = {}

WaveTrackLogic.BOSS_EVERY, WaveTrackLogic.BOSS_UNTIL = 5, 35 -- shortcut: mirrors CoopWaves; update with it (the spec fails if they drift)

function WaveTrackLogic.isBoss(wave: number): boolean
	return if wave <= WaveTrackLogic.BOSS_UNTIL then wave % WaveTrackLogic.BOSS_EVERY == 0 else wave % 2 == 1
end

-- The segment up to the next boss: the waves after the last boss wave before the current one, then the boss wave itself
-- (the smallest boss wave >= current, so the boss frame stays the current item during its own wave).
-- Items: { Wave, Boss (bool; only the last item), Current, Past, Variant (boss item: BossPlan entry for that wave, else nil) }.
-- Nil / non-positive wave counts as 1. plan is the snapshot BossPlan {Wave, Variant}[].
function WaveTrackLogic.window(wave: number?, plan: any?)
	local cur = if type(wave) == "number" and wave == wave and wave >= 1 then math.floor(math.min(wave, 1e9)) else 1
	local last = cur
	while not WaveTrackLogic.isBoss(last) do
		last += 1
	end
	local first = cur - 1 -- largest boss wave before the current one, plus 1
	while first >= 1 and not WaveTrackLogic.isBoss(first) do
		first -= 1
	end
	first += 1
	local variant
	for _, e in if type(plan) == "table" then plan else {} do
		if type(e) == "table" and e.Wave == last and type(e.Variant) == "string" then
			variant = e.Variant
		end
	end
	local items = {}
	for w = first, last do
		local boss = w == last
		table.insert(items, {
			Wave = w,
			Boss = boss,
			Current = w == cur,
			Past = w < cur,
			Variant = if boss then variant else nil,
		})
	end
	return items
end

return WaveTrackLogic
