-- Result card view model: Summary (solo/coop), Victory, Defeat; hidden-when-missing; thousands separators.

local ResultsLogic =
	require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Results.ResultsLogic)

test("commas", function()
	expectEq(ResultsLogic.commas(1285), "1,285", "four digits")
	expectEq(ResultsLogic.commas(1234567), "1,234,567", "millions")
	expectEq(ResultsLogic.commas(100), "100", "no leading comma")
	expectEq(ResultsLogic.commas(123456), "123,456", "exact groups")
	expectEq(ResultsLogic.commas(nil), "0", "nil")
	expectEq(ResultsLogic.commas(-1500), "-1,500", "negative")
end)

test("not ended gives nil", function()
	expectEq(ResultsLogic.view({ Phase = "Playing" }), nil, "playing")
	expectEq(ResultsLogic.view(nil), nil, "nil")
end)

test("summary: solo full data", function()
	local v = ResultsLogic.view({
		Phase = "Ended",
		Mode = "Solo",
		Result = "Lost",
		Wave = 12,
		DurationSec = 1458,
		Kills = 1285,
		RewardGold = 1450,
		RewardGems = 75,
		RewardXp = 600,
	}, { Level = 12, XpInto = 5070, XpNeed = 6000 })
	expectEq(v.Kind, "Summary", "kind")
	expectEq(v.ModeText, "SOLO", "pill")
	expectEq(v.RunTime, "24:18", "run time")
	expectEq(v.Kills, "1,285", "kills")
	expectEq(v.Tiles[1].Text, "+1,450", "coins")
	expectEq(v.Tiles[2].Text, "+75", "gems")
	expectEq(v.Tiles[3].Kind, "Xp", "xp last")
	expectEq(v.Level.Text, "5,070 / 6,000 XP", "xp text")
	expectEq(v.OutcomeLine, nil, "lost has no line")
	expectEq(v.Duel, nil, "no duel block")
end)

test("summary: hidden when missing; coop pill; aborted line", function()
	local v = ResultsLogic.view({ Phase = "Ended", Mode = "Coop", Result = "Aborted", Wave = 3 })
	expectEq(v.ModeText, "COOP", "coop")
	expectEq(v.RunTime, nil, "no run time")
	expectEq(v.Kills, nil, "no kills")
	expectEq(#v.Tiles, 0, "no tiles")
	expectEq(v.Level, nil, "no level")
	expectEq(v.OutcomeLine, "Run aborted", "line")
	local zero = ResultsLogic.view({ Phase = "Ended" }, { Level = 1, XpInto = 0, XpNeed = 0 })
	expectEq(zero.Level, nil, "zero need hides bar")
end)

local function duel(outcome)
	return {
		Phase = "Ended",
		Mode = "Duel",
		InDuelServer = true,
		Kills = 40,
		DurationSec = 95,
		Opponent = { Name = "BlockMaster", DR = 1220, Rank = "Silver", IsBot = false },
		OpponentUserId = 77,
		DuelResult = {
			Outcome = outcome,
			DRDelta = if outcome == "Win" then 28 else -14,
			DRAfter = 1248,
			Gold = 850,
			RankBefore = "Bronze",
			RankAfter = if outcome == "Win" then "Silver" else "Bronze",
			StreakBonus = 4,
			Streak = 3,
		},
	}
end

test("duel victory", function()
	local v = ResultsLogic.view(duel("Win"), nil, { Name = "Me", UserId = 5 })
	expectEq(v.Kind, "Victory", "kind")
	expectEq(v.Self.Winner, true, "self winner")
	expectEq(v.Opponent.Winner, false, "opp not winner")
	expectEq(v.Opponent.Silhouette, false, "has avatar")
	expectEq(v.Opponent.DRText, "1,220 DR", "opp DR")
	expectEq(v.Tiles[1].Text, "+850", "coins")
	expectEq(#v.Tiles, 1, "coins only when no gems or xp")
	expectEq(v.Duel.DeltaText, "+28 DR", "delta")
	expectEq(v.Duel.DeltaKind, "Gain", "gain")
	expectEq(v.Duel.DRText, "1,248 DR", "total")
	expectEq(v.Duel.InfoLine, "RANK UP: BRONZE > SILVER", "info")
	expectEq(v.RunTime, "1:35", "run time")
end)

test("duel defeat vs bot, NoDR, loss kind", function()
	local snap = duel("Loss")
	snap.OpponentUserId = nil
	snap.Opponent.IsBot = true
	snap.DuelResult.Why = "EarlyForfeit"
	snap.DuelResult.DRDelta = 0
	snap.DuelResult.StreakBonus = 0
	local v = ResultsLogic.view(snap)
	expectEq(v.Kind, "Defeat", "kind")
	expectEq(v.Self.Winner, false, "self loser")
	expectEq(v.Opponent.Winner, true, "opp winner")
	expectEq(v.Opponent.Silhouette, true, "bot silhouette")
	expectEq(v.Duel.DeltaKind, "Zero", "zero")
	expectEq(v.Duel.NoDR, true, "noDR")
	expectEq(v.Duel.InfoLine, "Quit too early: no DR was awarded", "info")
	local loss = ResultsLogic.view(duel("Loss"))
	expectEq(loss.Duel.DeltaKind, "Loss", "loss kind")
	expectEq(loss.Duel.DeltaText, "-14 DR", "loss text")
	expectEq(loss.Duel.InfoLine, "Streak bonus +4 DR", "bonus line")
end)

test("duel draw: nobody is the winner", function()
	local v = ResultsLogic.view(duel("Draw"))
	expectEq(v.Draw, true, "draw")
	expectEq(v.Self.Winner, false, "self")
	expectEq(v.Opponent.Winner, false, "opp")
	expectEq(ResultsLogic.view(duel("Win")).Draw, false, "win is no draw")
end)

test("delta text has thousands separators; loss makes the opponent the winner", function()
	local big = duel("Win")
	big.DuelResult.DRDelta = 9999
	expectEq(ResultsLogic.view(big).Duel.DeltaText, "+9,999 DR", "gain")
	big.DuelResult.DRDelta = -12345
	expectEq(ResultsLogic.view(big).Duel.DeltaText, "-12,345 DR", "loss")
	local loss = ResultsLogic.view(duel("Loss"))
	expectEq(loss.Opponent.Winner, true, "opp wins a loss")
	expectEq(loss.Draw, false, "no draw")
	local draw = ResultsLogic.view(duel("Draw"))
	expectEq(draw.Self.Winner or draw.Opponent.Winner, false, "draw: nobody")
end)

test("tiles: order, duel gems and xp, drops, zero hidden", function()
	local snap = duel("Win")
	snap.RewardXp, snap.RewardGems = 420, 35
	snap.Drops = { { Id = "L05", Name = "Ice Dice", Rarity = "Rare" }, "junk", { Rarity = "Epic" }, { Id = "L09" } }
	local t = ResultsLogic.view(snap).Tiles
	local kinds = {}
	for _, x in t do
		table.insert(kinds, x.Kind)
	end
	expectEq(table.concat(kinds, ","), "Coins,Gems,Xp,Drop,Drop", "order, bad drops skipped")
	expectEq(t[2].Text, "+35", "gems")
	expectEq(t[3].Text, "+420", "xp")
	expectEq(t[4].Name, "Ice Dice", "drop name")
	expectEq(t[4].Rarity, "Rare", "rarity")
	expectEq(t[4].ArtKey, "L05", "art key falls back to id")
	expectEq(t[5].Text, "L09", "id as name")
	snap.RewardGems, snap.Drops = 0, {}
	expectEq(#ResultsLogic.view(snap).Tiles, 3, "a real zero gems shows, empty drops none")
	snap.RewardGems = nil
	expectEq(#ResultsLogic.view(snap).Tiles, 2, "absent gems hidden")
	snap.RewardGems = 0
	snap.Drops = nil
	expectEq(#ResultsLogic.view(snap).Tiles, 3, "nil drops")
end)

test("count data: totals", function()
	local d = ResultsLogic.view(duel("Win")).Duel
	expectEq(d.TotalTo, 1248, "to")
	expectEq(d.TotalFrom, 1220, "derived from = to - delta")
	local snap = duel("Win")
	snap.RatingBefore = 1200
	expectEq(ResultsLogic.view(snap).Duel.TotalFrom, 1200, "explicit wins")
	local low = duel("Loss")
	low.DuelResult.DRAfter = 5
	expectEq(ResultsLogic.view(low).Duel.TotalFrom, 19, "loss: from above to")
	low.DuelResult.DRDelta = 30
	expectEq(ResultsLogic.view(low).Duel.TotalFrom, 0, "floors at 0")
end)

test("count data: level bar", function()
	local meta = { Level = 12, XpInto = 5070, XpNeed = 6000 }
	local v = ResultsLogic.view({ Phase = "Ended", RewardXp = 600 }, meta).Level
	expectEq(v.To.Level, 12, "to level")
	expectEq(v.From.Level, 12, "same level")
	expectEq(v.From.Frac, 0.745, "derived from")
	expectEq(v.LevelUps, 0, "no level up")
	local up = ResultsLogic.view({ Phase = "Ended", RewardXp = 6000 }, meta).Level
	expectEq(up.From, nil, "gain past this level: no animation")
	expectEq(up.LevelUps, 0, "nil from means 0 ups")
	local explicit = { Phase = "Ended", RewardXp = 6000, LevelFrom = 11, XpFrom = 3000, XpNeedFrom = 5000 }
	local ex = ResultsLogic.view(explicit, meta).Level
	expectEq(ex.From.Level, 11, "explicit level")
	expectEq(ex.From.Frac, 0.6, "explicit frac")
	expectEq(ex.LevelUps, 1, "one level up")
	expectEq(ResultsLogic.view({ Phase = "Ended", RewardXp = 0 }, meta).Level.From.Frac, 0.845, "0 xp: from = to")
	expectEq(ResultsLogic.view({ Phase = "Ended" }, meta).Level.From, nil, "unknown xp: no animation")
end)

test("summary: zero kills, zero rewards, a 0-second run still show", function()
	local v = ResultsLogic.view({
		Phase = "Ended",
		Result = "Lost",
		Wave = 1,
		Kills = 0,
		DurationSec = 5,
		RewardGold = 0,
		RewardGems = 0,
		RewardXp = 0,
	})
	expectEq(v.Kills, "0", "zero kills")
	expectEq(v.RunTime, "0:05", "run time")
	expectEq(#v.Tiles, 3, "coins, gems, xp at 0")
	expectEq(v.Tiles[1].Text, "+0", "zero coins")
	expectEq(ResultsLogic.view({ Phase = "Ended", Result = "Lost", Wave = 1, DurationSec = 0 }).RunTime, "0:00", "0 s")
end)

test("summary: aborted run keeps its stats and line", function()
	local v = ResultsLogic.view({
		Phase = "Ended",
		Mode = "Coop",
		Result = "Aborted",
		Wave = 4,
		Kills = 0,
		DurationSec = 61,
		RewardGold = 0,
		RewardGems = 0,
		RewardXp = 0,
	})
	expectEq(v.OutcomeLine, "Run aborted", "line")
	expectEq(v.Kills, "0", "kills")
	expectEq(v.RunTime, "1:01", "time")
	expectEq(#v.Tiles, 3, "zero tiles shown")
end)
