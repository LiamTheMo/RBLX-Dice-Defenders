-- Pure per-boss ability state machine (tuning: Shared/Bosses.Ability). No Roblox services, no clock of its own:
-- the caller passes the match clock. Timeline of one cast (castAt is when the effect lands):
--   idle --(castAt - CastAt)-----------> windup (boss stands still)
--   windup --(castAt)------------------> cast event (effect), recover
--   recover --(windup start + ClipSeconds)--> resume (boss walks again), next cast = castAt + Interval
-- Tick returns the events due since the last call, in order; each is { Phase, At, CastAt, Target }; state.casts counts casts.
-- At is the exact time of that phase (not `now`), so the caller can apply it on the right instant after a hitch.
local Bosses = require(game:GetService("ReplicatedStorage").Shared.Bosses)

local BossAbilities = {}

export type Event = { Phase: string, At: number, CastAt: number, Target: any? }

function BossAbilities.New(variant: string, spawnAt: number)
	local cfg = Bosses.Ability[variant]
	if cfg == nil then
		return nil
	end
	return { variant = variant, cfg = cfg, phase = "idle", castAt = spawnAt + cfg.First, casts = 0 }
end

-- True from the windup start to the resume: the boss must not move.
function BossAbilities.Holding(state): boolean
	return state.phase ~= "idle"
end

function BossAbilities.Tick(state, now: number): { Event }
	local cfg = state.cfg
	local events = {}
	while true do
		local castAt = state.castAt
		local startAt = castAt - cfg.CastAt
		if state.phase == "idle" then
			if now >= startAt then
				state.phase = "windup"
				table.insert(events, { Phase = "windup", At = startAt, CastAt = castAt })
			else
				break
			end
		elseif state.phase == "windup" then
			if now < castAt then
				break
			end
			state.phase = "recover"
			state.casts += 1
			table.insert(events, { Phase = "cast", At = castAt, CastAt = castAt })
		else
			local endAt = startAt + cfg.ClipSeconds
			if now < endAt then
				break
			end
			state.phase = "idle"
			state.castAt = castAt + cfg.Interval
			table.insert(events, { Phase = "resume", At = endAt, CastAt = castAt })
		end
	end
	return events
end

return BossAbilities
