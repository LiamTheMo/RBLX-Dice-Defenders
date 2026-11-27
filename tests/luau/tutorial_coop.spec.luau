-- Solo / Co-op lane HP and seats, and the tutorial roll unlock + checkpoint gift.

local Server = game:GetService("ServerScriptService").Server
local CoopWaves = require(Server.Config.CoopWaves)
local Dice = require(Server.Config.Dice)
local Match = require(Server.Rules.Match)
local ProfileSchema = require(Server.Rules.ProfileSchema)
local Claims = require(Server.Rules.Claims)
local Tutorial = require(Server.Rules.Tutorial)
local Layout = require(game:GetService("ReplicatedStorage").Shared.Layout)

test("Solo and Co-op share the lane HP and seat two owns its board", function()
	local hp = CoopWaves.InitialHp
	for wave = 1, 10 do
		local queue
		queue, hp = CoopWaves.Next(wave, hp)
		if wave == 10 then
			expectEq(queue[1].hp, 54050, "wave 10 boss: (4600 + 100) x 11.5")
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
	expectEq(profile.Tutorial.Stage, "Gift", "gift stage")
	profile.BestWave = 10
	expect(Claims.Claim(profile, "P10", 1000000), "wave 10 milestone claims")
	expect(Tutorial.Claimed(profile, "P10"), "claiming it ends the tutorial")
	expectEq(profile.Tutorial.Stage, "Done", "tutorial done")
	expect(profile.Dice.R01 ~= nil, "one Rare")
	expectEq(profile.Gems, 500, "tutorial gift gems")
	expectEq(profile.Materials.DieShard, 5, "tutorial gift shards")
	expect(not Tutorial.Claimed(profile, "P10"), "gift cannot be replayed")
	local die = profile.Deck[1]
	expect(Tutorial.Convert(profile, die), "shard converted to an owned die")
	expectEq(profile.Dice[die].Copies, 1, "one spare copy")
end)
