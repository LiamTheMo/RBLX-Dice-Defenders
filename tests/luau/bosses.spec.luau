-- Boss variants: the pure roll (never the same twice running), the variant fixed until its boss spawns, both Co-op /
-- Duel lanes sharing it, S records carrying it, and the lookup tables (Display, Sprites) staying in step.

local Server = game:GetService("ServerScriptService").Server
local Shared = game:GetService("ReplicatedStorage").Shared
local Match = require(Server.Rules.Match)
local Dice = require(Server.Config.Dice)
local CoopWaves = require(Server.Config.CoopWaves)
local Bosses = require(Shared.Bosses)
local Display = require(Shared.Display)
local Sprites = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.Sprites)
local BossWalk = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.BossWalk)

local DT = 0.1

-- Steps until `count` Boss S records exist (a lap of waves is skipped to the next boss wave), returns them in order.
local function bossRecords(state, count: number, firstWaveBefore: number)
	local found = {}
	local t = state.lastNow
	state.lives = 1e9
	if state.partner then
		state.partner.lives = 1e9
	end
	state.wave = firstWaveBefore
	state.waveState = "Prep"
	state.nextWaveAt = t
	for _ = 1, 20000 do
		t += DT
		Match.Step(state, t)
		for _, record in Match.TakeOut(state).S do
			if record.Kind == "Boss" then
				table.insert(found, record)
			end
		end
		if #found >= count then
			break
		end
	end
	return found
end

test("Roll is pure, never repeats the previous variant and reaches all three", function()
	local seen = {}
	for runId = 1, 300 do
		local previous
		for n = 1, 12 do
			local variant = Bosses.Roll(runId, n, previous)
			expect(Bosses.IsVariant(variant), "valid variant")
			expect(variant ~= previous, "no repeat: run " .. runId .. " boss " .. n)
			expectEq(Bosses.Roll(runId, n, previous), variant, "same inputs, same variant")
			seen[variant] = true
			previous = variant
		end
	end
	for _, id in Bosses.List do
		expect(seen[id], "rolled at least once: " .. id)
	end
end)

test("Co-op / Solo: the upcoming variant is fixed until the boss spawns, then the next one differs", function()
	local state = Match.New(77, Random.new(3), 0, Dice.Deck)
	local first = state.nextBossVariant
	expectEq(first, Bosses.Roll(77, 1, nil), "rolled at match start")
	state.wave = 4
	state.waveState = "Prep"
	state.nextWaveAt = 100
	for t = 1, 50 do
		Match.Step(state, t)
		expectEq(state.nextBossVariant, first, "fixed while the boss wave is scheduled")
	end
	expect(CoopWaves.IsBoss(5), "wave 5 is a boss wave")
	local state2 = Match.New(77, Random.new(3), 0, Dice.Deck)
	local records = bossRecords(state2, 1, 4)
	expectEq(records[1].Variant, first, "the spawn record carries the announced variant")
	expect(state2.nextBossVariant ~= first, "the next boss is a different variant")
	state2.enemies = {}
	state2.queue, state2.qi = {}, 1
	local more = bossRecords(state2, 1, 9)
	expectEq(more[1].Variant, Bosses.Roll(77, 2, first), "second boss follows the roll")
	expect(more[1].Variant ~= first, "never twice in a row")
end)

test("Co-op: both seats' bosses share one variant", function()
	local state = Match.New(5, Random.new(9), 0, Dice.Deck, Dice.Deck, 0, 0)
	local records = bossRecords(state, 2, 4)
	expectEq(#records, 2, "one boss per seat")
	expectEq(records[1].Variant, records[2].Variant, "same variant on both lanes")
	expect(Bosses.IsVariant(records[1].Variant), "valid")
end)

test("Duel: both lanes get the same variant each wave and it changes every wave", function()
	local state = Match.NewDuel(21, Random.new(5), 0, Dice.Deck, Dice.Deck)
	local announced = state.nextBossVariant
	local previous
	for wave = 1, 3 do
		state.queue, state.qi = {}, 1
		local records = bossRecords(state, 2, wave - 1)
		expectEq(records[1].Variant, records[2].Variant, "lanes share wave " .. wave)
		if wave == 1 then
			expectEq(records[1].Variant, announced, "wave 1 boss is the announced one")
		end
		expect(records[1].Variant ~= previous, "differs from the previous wave")
		previous = records[1].Variant
		state.enemies = {}
		state.bossSpawned = false
	end
end)

test("NextBossWave: solo skips to the next boss wave, Duel is every wave", function()
	local state = Match.New(1, Random.new(1), 0, Dice.Deck)
	expectEq(Match.NextBossWave(state), 5, "fresh match")
	state.wave, state.waveState = 5, "Prep"
	expectEq(Match.NextBossWave(state), 10, "after wave 5 is cleared")
	local duel = Match.NewDuel(1, Random.new(1), 0, Dice.Deck, Dice.Deck)
	expectEq(Match.NextBossWave(duel), 1, "duel wave 1")
end)

test("every variant has Display, portrait slot, walk data and a stride per arena", function()
	local colors = {}
	for _, id in Bosses.List do
		local info = Bosses.Info[id]
		expect(info.Name ~= "" and Display.Enemies[id].Name == info.Name, "Display name " .. id)
		expectEq(Display.Enemies[id].Color, info.Color, "Display colour " .. id)
		expect(not colors[info.Color], "distinct colour " .. id)
		colors[info.Color] = true
		expectEq(type(Sprites.Boss[info.Portrait]), "string", "Sprites.Boss slot " .. id)
		expect(BossWalk.Has(id), "walk data " .. id)
		local data = BossWalk.Data[id]
		expect(next(data.Joints) ~= nil, "joints " .. id)
		for name, list in data.Joints do
			expectEq(#list, data.Frames * 7, "7 numbers per frame: " .. id .. "." .. name)
		end
		for arena, factor in { Solo = 1.4994, Coop = 2.259, Duel = 1.708 } do
			expect(math.abs(BossWalk.Stride(id, arena) - data.Stride * factor) < 1e-9, "stride " .. id .. arena)
		end
	end
	expectEq(BossWalk.Data.GoblinKing.Stride, 3.266, "natural stride")
	expectEq(BossWalk.Data.CursedKing.Stride, 3.3972, "natural stride")
	expectEq(BossWalk.Data.CourtJester.Stride, 5.6, "natural stride")
end)

test("ability ids and tuning: PortalSummon, HammerLock, DiceShuffle", function()
	expectEq(Bosses.Info.GoblinKing.Abilities[1], "PortalSummon", "name")
	expectEq(Bosses.Info.CursedKing.Abilities[1], "HammerLock", "name")
	expectEq(Bosses.Info.CourtJester.Abilities[1], "DiceShuffle", "name")
	for _, id in Bosses.List do
		expectEq(Bosses.Ability[id].Id, Bosses.Info[id].Abilities[1], "Ability.Id matches Info " .. id)
	end
	local gk = Bosses.Ability.GoblinKing
	expectEq(gk.SummonGrunts, 3, "grunts")
	expectEq(gk.SummonFast, 1, "fast")
	expectEq(Bosses.Ability.CursedKing.LockCount, 3, "locks per cast")
	expectEq(Bosses.Ability.CursedKing.MaxLocked, 6, "lock cap")
	expectEq(Bosses.Ability.CourtJester.Dice, 5, "shuffled dice")
end)
