-- Duel bots (docs/DICE_RATING.md section 9 item 2): deck recipes per rank, deck validity, DR range, determinism,
-- the human tap-rate cap and headless bot-vs-bot Duels that finish.

local Server = game:GetService("ServerScriptService").Server
local Bot = require(Server.Rules.Bot)
local Bots = require(Server.Config.Bots)
local Deck = require(Server.Rules.Deck)
local Dice = require(Server.Config.Dice)
local Match = require(Server.Rules.Match)

local function counts(deck)
	local c = { Common = 0, Rare = 0, Epic = 0 }
	for _, id in deck do
		local r = Dice.Types[id].rarity
		c[r] = (c[r] or 0) + 1
	end
	return c
end

test("deck recipes and validity over many seeds", function()
	local seenRare, seenEpic = {}, {}
	for rank = 1, 3 do
		for seed = 1, 200 do
			local bot = Bot.Make(rank, Random.new(seed))
			expectEq(bot.RankIndex, rank, "rank")
			expect(Deck.Shape(bot.Deck) and #bot.Deck == Deck.SIZE, "shape rank " .. rank .. " seed " .. seed)
			local owned = {}
			for id in Dice.Types do
				owned[id] = {}
			end
			expect(Deck.Check(owned, bot.Deck), "valid deck")
			local c = counts(bot.Deck)
			if rank == 1 then
				expectEq(c.Common, 5, "bronze commons")
			elseif rank == 2 then
				expect(c.Rare == 3 or c.Rare == 4, "silver rares " .. c.Rare)
				expectEq(c.Common, 5 - c.Rare, "silver commons")
				seenRare[c.Rare] = true
			else
				expect(c.Epic == 1 or c.Epic == 2, "gold epics " .. c.Epic)
				expectEq(c.Rare, 5 - c.Epic, "gold rares")
				seenEpic[c.Epic] = true
			end
			expect(table.find(Bots.Names, bot.Name) ~= nil, "name from pool")
			local range = Bots.Ranks[rank].DR
			expect(bot.DR >= range.Min and bot.DR <= range.Max and bot.DR % 1 == 0, "DR in range " .. bot.DR)
		end
	end
	expect(seenRare[3] and seenRare[4], "silver varies 3 and 4 rares")
	expect(seenEpic[1] and seenEpic[2], "gold varies 1 and 2 epics")
	expectEq(#Bots.Names >= 20, true, "name pool")
end)

test("DR ranges match the rank bands", function()
	local Rating = require(Server.Rules.Rating)
	for rank = 1, 3 do
		for seed = 1, 50 do
			expectEq(Rating.RankOf(Bot.Make(rank, Random.new(seed)).DR).Index, rank, "DR maps to its rank")
		end
	end
end)

test("Make and a play-through are deterministic for a fixed seed", function()
	local a, b = Bot.Make(3, Random.new(9)), Bot.Make(3, Random.new(9))
	expectEq(a.Name, b.Name, "name")
	expectEq(a.DR, b.DR, "dr")
	expectEq(table.concat(a.Deck, ","), table.concat(b.Deck, ","), "deck")
	local function play()
		local state = Match.NewDuel(1, Random.new(4), 0, Dice.Deck, a.Deck)
		local bot = Bot.New(3, Random.new(77))
		local log = {}
		for i = 1, 600 do
			for _, intent in Bot.Step(bot, state, 2, i * 0.1) do
				table.insert(log, i .. intent.Kind .. tostring(intent.From) .. tostring(intent.TypeId))
			end
			Match.Step(state, i * 0.1)
		end
		return table.concat(log, ";")
	end
	local one, two = play(), play()
	expect(#one > 0, "bot acted")
	expectEq(one, two, "same log")
end)

test("the bot never exceeds its tap-rate cap and the first action waits for a reaction delay", function()
	for rank = 1, 3 do
		local s = Bots.Ranks[rank]
		local state = Match.NewDuel(1, Random.new(3), 0, Dice.Deck, Dice.Deck)
		state.partner.mp = 100000
		local bot = Bot.New(rank, Random.new(rank))
		local times, first = {}, nil
		for i = 1, 400 do
			local now = i * 0.05
			local done = Bot.Step(bot, state, 2, now)
			if #done > 0 and first == nil then
				first = now
			end
			for _ = 1, #done do
				table.insert(times, now)
			end
		end
		expect(first ~= nil and first >= s.ReactionMin - 1e-9, "first action after the delay, rank " .. rank)
		for i = 1, #times do
			local n = 0
			for j = 1, #times do
				if times[j] >= times[i] and times[j] < times[i] + 1 then
					n += 1
				end
			end
			expect(n <= s.MaxPerSecond, "rate cap rank " .. rank .. " got " .. n)
		end
	end
end)

local function duel(botA, botB, seed)
	local state = Match.NewDuel(seed, Random.new(seed), 0, botA.Deck, botB.Deck)
	local rngA, rngB = Random.new(seed * 2 + 1), Random.new(seed * 2 + 2)
	local a, b = Bot.New(botA.RankIndex, rngA), Bot.New(botB.RankIndex, rngB)
	local t, limit = 0, 4000
	while state.phase == "Playing" and t < limit do
		t += 0.1
		Bot.Step(a, state, 1, t)
		Bot.Step(b, state, 2, t)
		Match.Step(state, t)
	end
	return state, t
end

test("bot vs bot Duels finish with no stall", function()
	for seed = 1, 6 do
		local state, t = duel(Bot.Make(2, Random.new(seed)), Bot.Make(2, Random.new(seed + 50)), seed)
		expectEq(state.phase, "Ended", "ended, seed " .. seed .. " t=" .. t)
		expectEq(state.result, "Duel", "duel result")
	end
end)

test("mixed-rank Duels all resolve with a winner (no rank-based win rate is asserted)", function()
	for seed = 1, 20 do
		local gold, bronze = Bot.Make(3, Random.new(seed)), Bot.Make(1, Random.new(seed + 100))
		-- Alternate seats so a seat edge cannot decide it.
		local state
		if seed % 2 == 0 then
			state = duel(gold, bronze, seed)
		else
			state = duel(bronze, gold, seed)
		end
		expectEq(state.phase, "Ended", "ended, seed " .. seed)
		expect(state.duel.Winner ~= nil, "winner decided, seed " .. seed)
	end
end)
