-- Wave track segment: dots after the previous boss wave plus the boss frame at the end.

local WaveTrackLogic = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.WaveTrackLogic)
local CoopWaves = require(game:GetService("ServerScriptService").Server.Config.CoopWaves)

local function shape(items)
	local out = {}
	for _, it in items do
		table.insert(out, (if it.Boss then "B" else "d") .. it.Wave)
	end
	return table.concat(out, " ")
end

test("mirror matches the server schedule", function()
	for w = 1, 200 do
		expectEq(WaveTrackLogic.isBoss(w), CoopWaves.IsBoss(w), "wave " .. w)
	end
end)

test("run start: 4 dots and the first boss", function()
	local items = WaveTrackLogic.window(1)
	expectEq(shape(items), "d1 d2 d3 d4 B5", "wave 1")
	expectEq(items[1].Current, true, "wave 1 current")
	expectEq(shape(WaveTrackLogic.window(4)), "d1 d2 d3 d4 B5", "wave 4")
end)

test("mid segment: past dim, current marked", function()
	local items = WaveTrackLogic.window(8)
	expectEq(shape(items), "d6 d7 d8 d9 B10", "wave 8")
	expectEq(items[1].Past and items[2].Past, true, "past")
	expectEq(items[3].Current, true, "current")
	expectEq(items[4].Past or items[4].Current, false, "future")
end)

test("boss wave itself stays current; the next wave loads the new set", function()
	local items = WaveTrackLogic.window(5)
	expectEq(shape(items), "d1 d2 d3 d4 B5", "wave 5")
	expectEq(items[5].Current and items[5].Boss, true, "boss current")
	expectEq(shape(WaveTrackLogic.window(6)), "d6 d7 d8 d9 B10", "just cleared")
end)

test("after the threshold: one dot and a boss", function()
	expectEq(shape(WaveTrackLogic.window(35)), "d31 d32 d33 d34 B35", "35 is the last fifth")
	expectEq(shape(WaveTrackLogic.window(36)), "d36 B37", "wave 36")
	expectEq(shape(WaveTrackLogic.window(37)), "d36 B37", "wave 37 is the boss, current")
	expectEq(shape(WaveTrackLogic.window(38)), "d38 B39", "wave 38")
	expectEq(shape(WaveTrackLogic.window(116)), "d116 B117", "wave 116")
end)

test("BossPlan variant lands on the boss frame only", function()
	local plan = { { Wave = 5, Variant = "GoblinKing" }, { Wave = 10, Variant = "CursedKing" } }
	local items = WaveTrackLogic.window(1, plan)
	expectEq(items[5].Variant, "GoblinKing", "boss")
	expectEq(items[4].Variant, nil, "dot")
	expectEq(WaveTrackLogic.window(7, plan)[5].Variant, "CursedKing", "next segment")
	expectEq(WaveTrackLogic.window(1, {})[5].Variant, nil, "empty plan")
	expectEq(WaveTrackLogic.window(1, nil)[5].Variant, nil, "nil plan")
	expectEq(WaveTrackLogic.window(1, { "x", { Wave = "5" } })[5].Variant, nil, "junk")
end)

test("bad input", function()
	expectEq(WaveTrackLogic.window(nil)[1].Current, true, "nil wave is wave 1")
	expectEq(#WaveTrackLogic.window(0 / 0) <= 5, true, "NaN bounded")
	expectEq(#WaveTrackLogic.window(-3), 5, "negative")
end)
