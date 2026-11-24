local Server = game:GetService("ServerScriptService").Server
local CoopWaves = require(Server.Config.CoopWaves)
local Dice = require(Server.Config.Dice)
local Match = require(Server.Rules.Match)
local ProfileSchema = require(Server.Rules.ProfileSchema)
local Tutorial = require(Server.Rules.Tutorial)
local Layout = require(game:GetService("ReplicatedStorage").Shared.Layout)

test("Solo and Co-op share the measured lane HP and seat two owns its board", function()
	local hp, step = CoopWaves.InitialHp, 0
	for wave = 1, 10 do
		local queue
		queue, hp, step = CoopWaves.Next(wave, hp, step)
		if wave == 10 then
			expectEq(queue[1].rawHp, 47000, "historical boss anchor")
			expectEq(queue[1].hp, 8460, "local HP conversion")
		end
	end
	expectEq(Layout.CoopPathLength, Layout.PathLength, "same time to travel either lane")
	local solo = Match.New(1, Random.new(12), 0, Dice.Deck)
	local duo = Match.New(2, Random.new(12), 0, Dice.Deck, Dice.Deck)
	expect(Match.TrySummon(duo, 2), "seat two can summon")
	expectEq(duo.mp, solo.mp, "seat one MP untouched")
	expectEq(Match.Seat(duo, 2).mp, solo.mp - Match.SummonCost(solo), "seat two pays")
	for _, state in { solo, duo } do
		state.lastNow = state.nextWaveAt - 0.1
		Match.Step(state, state.nextWaveAt)
	end
	expectEq(solo.queue[1].hp, duo.queue[1].hp, "shared recipe")
end)

test("tutorial rolls unlock five distinct dice and award the checkpoint gift once", function()
	local profile = ProfileSchema.Migrate(nil)
	local rng = Random.new(8)
	expectEq(Tutorial.View(profile).Gems, 500, "free starter reserve")
	expect(not Tutorial.CanStart(profile), "roll before playing")
	local seen = {}
	for _ = 1, 5 do
		local ok, _, result = Tutorial.Roll(profile, rng)
		expect(ok, "roll succeeds")
		local id = result.Results[1].Id
		expect(not seen[id], "no starter duplicates")
		seen[id] = true
	end
	expectEq(#profile.Deck, 5, "auto-equipped five")
	expect(not Tutorial.ReachWave(profile, 9), "wave nine does not qualify")
	expect(Tutorial.ReachWave(profile, 10) and Tutorial.Finish(profile), "checkpoint reached")
	local granted, id = Tutorial.Claim(profile, rng)
	expect(granted and Dice.Types[id].rarity == "Epic", "one Epic")
	expectEq(profile.Gems, 500, "tutorial gift gems")
	expectEq(profile.Materials.DieShard, 5, "tutorial gift shards")
	expect(not Tutorial.Claim(profile, rng), "gift cannot be replayed")
	local die = profile.Deck[1]
	expect(Tutorial.Convert(profile, die), "shard converted to an owned die")
	expectEq(profile.Dice[die].Copies, 1, "one spare copy")
end)
