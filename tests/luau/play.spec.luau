-- Play tab logic: best text, start gating, world rows, milestone rows from Catalog + Meta, claim target, repeat payout.

local Play = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Play
local PlayLogic = require(Play.PlayLogic)
local Catalog = require(game:GetService("ServerScriptService").Server.Rules.Catalog)

local CATALOG = Catalog.Build()

local function meta(rows)
	return { Milestones = rows }
end

test("BEST WAVE denominator is 100 on every world card", function()
	local rows = PlayLogic.worlds({ BestWave = 35 })
	table.move(PlayLogic.worlds(nil), 1, #rows, #rows + 1, rows)
	for _, w in rows do
		expectEq(PlayLogic.bestWaveText(w.Best, "full"), `BEST WAVE {w.Best} / 100`, "full " .. w.Id)
		expectEq(PlayLogic.bestWaveText(w.Best, "short"), `BEST {w.Best}/100`, "short " .. w.Id)
		expectEq(PlayLogic.bestWaveText(w.Best, "min"), `{w.Best}/100`, "min " .. w.Id)
	end
	expectEq(rows[1].Best, "35", "real best")
	expectEq(rows[#PlayLogic.LOCKED_WORLDS + 2].Best, "--", "real nil best")
	expectEq(PlayLogic.bestWaveText("35", "full", "<b>35</b>"), "BEST WAVE <b>35</b> / 100", "shown")
end)

test("bestText", function()
	expectEq(PlayLogic.bestText(nil), "--", "nil")
	expectEq(PlayLogic.bestText(0), "--", "0")
	expectEq(PlayLogic.bestText(7), "7", "7")
	expectEq(PlayLogic.bestText(7.9), "7", "7.9")
	expectEq(PlayLogic.bestText("x" :: any), "--", "x")
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

test("worlds: real first, the others locked", function()
	local list = PlayLogic.worlds({ BestWave = 4 })
	expectEq(#list, #PlayLogic.LOCKED_WORLDS + 1, "count")
	expectEq(list[1].Id, "DiceKingdom", "first")
	expectEq(list[1].Locked, false, "real unlocked")
	expectEq(list[1].Best, "4", "best")
	for i = 2, #list do
		expectEq(list[i].Locked, true, "locked " .. list[i].Id)
		expectEq(list[i].Best, "--", "locked best " .. list[i].Id)
	end
end)

test("rewardText: counters, Catalog names, dice, plurals, unknown ids", function()
	expectEq(PlayLogic.rewardText({ Kind = "Gold", Amount = 100 }, CATALOG), "+100 GOLD", "gold")
	expectEq(PlayLogic.rewardText({ Kind = "Gems", Amount = 50 }, CATALOG), "+50 GEMS", "gems")
	expectEq(PlayLogic.rewardText({ Kind = "Xp", Amount = 10 }, CATALOG), "+10 XP", "xp")
	expectEq(PlayLogic.rewardText({ Kind = "Item", Id = "XpTome", Amount = 1 }, CATALOG), "+1 XP TOME", "item")
	expectEq(PlayLogic.rewardText({ Kind = "Item", Id = "XpTome", Amount = 2 }, CATALOG), "+2 XP TOMES", "plural")
	expectEq(PlayLogic.rewardText({ Kind = "Die", Id = "R01", Amount = 1 }, CATALOG), "+1 FROST DIE", "die")
	expectEq(PlayLogic.rewardText({ Kind = "Die", Id = "R01", Amount = 1 }, CATALOG, "Icon"), "+1 FROST", "die icon")
	local frag = { Kind = "Material", Id = "Fragment", Amount = 5 }
	expectEq(PlayLogic.rewardText(frag, CATALOG), "+5 VERDANT FRAGMENTS", "material")
	expectEq(PlayLogic.rewardText(frag, CATALOG, "Short"), "+5 FRAGMENTS", "short")
	frag.Amount = 1
	expectEq(PlayLogic.rewardText(frag, CATALOG, "Short"), "+1 FRAGMENT", "short one")
	expectEq(PlayLogic.rewardText({ Kind = "Item", Id = "Nope", Amount = 1 }, nil), "+1 NOPE", "no catalog: the id")
end)

test("milestones: one row per Catalog milestone, states from Meta", function()
	local m = meta({
		{ Id = "P10", Claimed = false, Claimable = true },
		{ Id = "P20", Claimed = false, Claimable = false },
	})
	local rows = PlayLogic.milestones(CATALOG, m, {})
	expectEq(#rows, #CATALOG.Milestones, "count")
	local want = { "Claimable", "Locked", "Locked", "Locked", "Locked", "Locked" } -- endless: every milestone is reachable
	for i, row in rows do
		expectEq(row.Id, CATALOG.Milestones[i].Id, "order " .. i)
		expectEq(row.Wave, CATALOG.Milestones[i].Wave, "wave " .. i)
		expectEq(row.State, want[i], "state " .. row.Id)
		expectEq(#row.Lines, #CATALOG.Milestones[i].Rewards, "lines " .. row.Id)
		expectEq(#row.Full, #row.Lines, "full " .. row.Id)
		expectEq(row.Busy, false, "busy " .. row.Id)
	end
	expectEq(rows[1].Icon, "IconGalaxyDie", "P10 icon: the die beats Gems")
	expectEq(rows[2].Icon, "IconGalaxyDie", "P20 icon: the die")
	expectEq(rows[4].Icon, "Gem", "P40 icon: the HUD gem")
	expectEq(table.concat(rows[1].Full, "|"), "+50 GEMS|+1 FROST DIE", "P10 rewards: the tutorial's gems and Rare die")
	expectEq(table.concat(rows[2].Lines, "|"), "+100 GOLD|+1 FROST", "P20 beside the icon")
	expectEq(table.concat(rows[2].Full, "|"), "+100 GOLD|+1 FROST DIE", "P20 phones")

	expectEq(
		PlayLogic.milestones(CATALOG, meta({ { Id = "P10", Claimed = true, Claimable = false } }))[1].State,
		"Claimed",
		"claimed"
	)
	expectEq(PlayLogic.milestones(CATALOG, nil)[1].State, "Locked", "no Meta: reachable is Locked")
	local unreachable = table.clone(CATALOG)
	unreachable.Milestones = table.clone(CATALOG.Milestones)
	unreachable.Milestones[2] = table.clone(CATALOG.Milestones[2])
	unreachable.Milestones[2].Reachable = false
	expectEq(PlayLogic.milestones(unreachable, nil)[2].State, "Soon", "no Meta: an unreachable milestone is Soon")
	expectEq(PlayLogic.milestones(CATALOG, m, { P10 = true })[1].Busy, true, "busy")
	local claimable = PlayLogic.milestones(CATALOG, meta({ { Id = "P20", Claimable = true } }))[2]
	expectEq(table.concat(claimable.Lines, "|"), "+100 GOLD|+1 FROST DIE", "CLAIM replaces the icon: full texts")
end)

test("milestones: nil or malformed Catalog / Meta never errors", function()
	expectEq(#PlayLogic.milestones(nil, nil), 0, "nothing yet")
	expectEq(#PlayLogic.milestones(nil, meta({ { Id = "P10", Claimable = true } })), 0, "Meta before Catalog")
	expectEq(#PlayLogic.milestones({}, {}), 0, "empty")
	local rows = PlayLogic.milestones(CATALOG, meta({ { Claimable = true }, "x", { Id = "P10", Claimable = true } }))
	expectEq(rows[1].State, "Claimable", "bad Meta rows skipped")
	expectEq(#PlayLogic.repeatLines(nil), 0, "no payout before Catalog")
	local bad = {
		Milestones = {
			7,
			{ Id = "X" },
			{ Wave = 5 },
			{ Id = "P10", Wave = 10, Reachable = true, Rewards = { 1, { Kind = "Gold", Amount = 5 } } },
		},
		Repeat = { PerWave = { 2, { Kind = "Xp", Amount = 1 }, { Kind = "Gold", Amount = 3 } } },
	}
	local good = PlayLogic.milestones(bad, nil)
	expectEq(#good, 1, "malformed Catalog rows skipped")
	expectEq(table.concat(good[1].Lines, "|"), "+5 GOLD", "malformed rewards skipped")
	expectEq(#PlayLogic.repeatLines(bad), 2, "malformed payout parts skipped")
end)

test("claimTarget: only a claimable row with no claim in flight", function()
	local row = { Id = "P10", State = "Claimable" }
	expectEq(PlayLogic.claimTarget(row, {}), "P10", "claimable")
	expectEq(PlayLogic.claimTarget(row, { P10 = true }), nil, "in flight: a double tap sends once")
	for _, state in { "Claimed", "Locked", "Soon" } do
		expectEq(PlayLogic.claimTarget({ Id = "P10", State = state }, {}), nil, state)
	end
	expectEq(PlayLogic.claimTarget(nil, {}), nil, "nil row")
end)

test("repeatLines: the real per-run payout, no drop odds", function()
	local lines = PlayLogic.repeatLines(CATALOG)
	local text = {}
	for i, line in lines do
		text[i] = table.concat(line, " ")
	end
	expectEq(
		table.concat(text, "|"),
		"PER WAVE:|+5 GOLD +10 GEMS +10 XP|+1 FRAGMENT|BOSS WAVE: +30 GEMS",
		"payout from Balance.Reward and WaveGems"
	)
	for _, t in text do
		expectEq(t:find("%", 1, true), nil, "no odds in " .. t)
	end
end)

test("tiles: materials are real, the rest are Soon placeholders", function()
	expectEq(PlayLogic.TILES[1].Label, "MATERIALS", "first")
	expectEq(PlayLogic.TILES[1].Soon, nil, "materials drop")
	for i = 2, #PlayLogic.TILES do
		expectEq(PlayLogic.TILES[i].Soon, true, PlayLogic.TILES[i].Label)
	end
end)

test("worldClear", function()
	expectEq(PlayLogic.worldClear({ TrialCleared = true }), true, "true")
	expectEq(PlayLogic.worldClear({}), false, "unset")
	expectEq(PlayLogic.worldClear(nil), false, "nil")
end)

test("repeatTiles: the kinds Catalog.Repeat pays per wave, and the boss line", function()
	local tiles, boss = PlayLogic.repeatTiles(CATALOG)
	expectEq(#tiles, 4, "gold, gems, xp, materials")
	expectEq(tiles[1].Label, "GOLD", "first")
	expectEq(tiles[1].Text, "+" .. tostring(CATALOG.Repeat.PerWave[1].Amount), "amount")
	expectEq(boss ~= nil and string.sub(boss, 1, 11), "BOSS WAVE: ", "boss line")
	expectEq(#PlayLogic.repeatTiles(nil), 0, "no Catalog")
end)
