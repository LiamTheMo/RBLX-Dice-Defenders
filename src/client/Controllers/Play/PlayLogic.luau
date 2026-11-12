--!strict
-- Play tab logic: pure, no Instances. The view draws what these return.

local PlayLogic = {}

-- The one real, playable world is the server's trial. Waves mirrors server Balance.Waves; play.spec guards it.
PlayLogic.WORLD = { Id = "DiceKingdom", Name = "DICE KINGDOM", Art = "WorldDice", Waves = 10 }

function PlayLogic.bestText(best: number?): string
	if type(best) ~= "number" or best ~= best or best < 1 then
		return "--"
	end
	return tostring(math.floor(best))
end

function PlayLogic.reached(best: number?, wave: number): boolean
	return type(best) == "number" and best >= wave
end

function PlayLogic.startState(snap: any, busy: boolean): "Ready" | "Busy" | "Disabled"
	if busy then
		return "Busy"
	end
	if snap and (snap.Phase == "Lobby" or snap.Phase == "Ended") then
		return "Ready"
	end
	return "Disabled"
end

function PlayLogic.worlds(snap: any, sample: any)
	local W = PlayLogic.WORLD
	local out = {
		{
			Id = W.Id,
			Name = W.Name,
			Art = W.Art,
			Best = PlayLogic.bestText(snap and snap.BestWave),
			Waves = W.Waves,
			Locked = false,
		},
	}
	for _, w in sample.Worlds do
		table.insert(out, { Id = w.Id, Name = w.Name, Art = w.Art, Best = "--", Waves = w.Waves, Locked = true })
	end
	return out
end

function PlayLogic.milestones(snap: any, sample: any)
	local best = snap and snap.BestWave
	local out = {}
	for i, row in sample.Milestones do
		out[i] = { Wave = row.Wave, Icon = row.Icon, Lines = row.Lines, Reached = PlayLogic.reached(best, row.Wave) }
	end
	return out
end

function PlayLogic.worldClear(snap: any): boolean
	return snap ~= nil and snap.TrialCleared == true
end

return PlayLogic
