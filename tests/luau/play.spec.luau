-- Play tab logic: best text, start gating, world and milestone rows, live-safe sample.

local Play = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Play
local PlayLogic = require(Play.PlayLogic)
local SampleData = require(Play.SampleData)
local Balance = require(game:GetService("ServerScriptService").Server.Config.Balance)

test("WORLD mirrors server Balance.Waves", function()
	expectEq(PlayLogic.WORLD.Waves, Balance.Waves, "waves")
end)

test("bestText", function()
	expectEq(PlayLogic.bestText(nil), "--", "nil")
	expectEq(PlayLogic.bestText(0), "--", "0")
	expectEq(PlayLogic.bestText(7), "7", "7")
	expectEq(PlayLogic.bestText(7.9), "7", "7.9")
	expectEq(PlayLogic.bestText("x" :: any), "--", "x")
end)

test("reached", function()
	expectEq(PlayLogic.reached(10, 10), true, "equal")
	expectEq(PlayLogic.reached(9, 10), false, "below")
	expectEq(PlayLogic.reached(nil, 10), false, "nil")
	expectEq(PlayLogic.reached("x" :: any, 10), false, "garbage")
end)

test("startState", function()
	for phase, want in
		{
			Lobby = "Ready",
			Ended = "Ready",
			Loading = "Disabled",
			Failed = "Disabled",
			NotOwner = "Disabled",
			Playing = "Disabled",
		}
	do
		expectEq(PlayLogic.startState({ Phase = phase }, false), want, phase)
		expectEq(PlayLogic.startState({ Phase = phase }, true), "Busy", phase .. " busy")
	end
	expectEq(PlayLogic.startState(nil, false), "Disabled", "nil snap")
	expectEq(PlayLogic.startState(nil, true), "Busy", "nil busy")
end)

test("worlds: real first, samples locked, no mutation", function()
	local sample = SampleData.full
	local before = #sample.Worlds
	local list = PlayLogic.worlds({ BestWave = 4 }, sample)
	expectEq(#list, before + 1, "count")
	expectEq(list[1].Id, "DiceKingdom", "first")
	expectEq(list[1].Locked, false, "real unlocked")
	expectEq(list[1].Best, "4", "best")
	expectEq(list[2].Locked, true, "sample locked")
	expectEq(list[2].Best, "--", "sample best")
	expectEq(#sample.Worlds, before, "sample size")
	expectEq(sample.Worlds[1].Best, nil, "sample untouched")
end)

test("milestones Reached flags", function()
	local sample = SampleData.full
	for best, want in { [0] = { 0, 0 }, [9] = { 0, 0 }, [10] = { 1, 0 } } do
		local rows = PlayLogic.milestones({ BestWave = best }, sample)
		expectEq(rows[1].Reached, want[1] == 1, "w10 best " .. best)
		expectEq(rows[2].Reached, false, "w20 best " .. best)
	end
	expectEq(sample.Milestones[1].Reached, nil, "sample untouched")
end)

test("worldClear", function()
	expectEq(PlayLogic.worldClear({ TrialCleared = true }), true, "true")
	expectEq(PlayLogic.worldClear({}), false, "unset")
	expectEq(PlayLogic.worldClear(nil), false, "nil")
end)

test("live sample has no amounts or odds", function()
	expectEq(SampleData.get(true), SampleData.full, "studio")
	local live = SampleData.get(false)
	local function check(s)
		expectEq(s:find("+", 1, true), nil, "plus in " .. s)
		expectEq(s:find("%", 1, true), nil, "percent in " .. s)
	end
	for _, m in live.Milestones do
		for _, l in m.Lines do
			check(l)
		end
	end
	for _, line in live.Odds do
		for _, l in line do
			check(l)
		end
	end
	expectEq(#live.Odds, 1, "single odds line")
	expectEq(live.Odds[1][1], "COMING SOON", "odds text")
end)
