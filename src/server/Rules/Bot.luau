-- Duel bot (docs/DICE_RATING.md section 9 item 2). Pure and rng-seeded: no Roblox services, no clock of its own.
-- Bot.Make builds the identity and deck; Bot.New/Bot.Step play a seat through the normal Match intents
-- (TrySummon / TryMerge / TryPowerUp) at a human-like pace set by Config/Bots.
local Balance = require(script.Parent.Parent.Config.Balance)
local Bots = require(script.Parent.Parent.Config.Bots)
local Dice = require(script.Parent.Parent.Config.Dice)
local Board = require(script.Parent.Board)
local Deck = require(script.Parent.Deck)
local Formulas = require(script.Parent.Formulas)
local Match = require(script.Parent.Match)

local Bot = {}

local function settings(rankIndex: number)
	return Bots.Ranks[math.clamp(rankIndex, 1, #Bots.Ranks)]
end

-- Sorted ids of one rarity, so a seeded draw is reproducible.
local function idsOf(rarity: string): { string }
	local ids = {}
	for id, die in Dice.Types do
		if die.rarity == rarity then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

-- Removes and returns `count` random entries of `pool`.
local function take(rng, pool: { string }, count: number): { string }
	local out = {}
	for _ = 1, math.min(count, #pool) do
		table.insert(out, table.remove(pool, rng:NextInteger(1, #pool)))
	end
	return out
end

local function buildDeck(rankIndex: number, rng): { string }
	local s = settings(rankIndex)
	local deck = {}
	local commons, rares, epics = idsOf("Common"), idsOf("Rare"), idsOf("Epic")
	if s.Commons then
		deck = take(rng, commons, s.Commons)
	elseif s.RareMin then
		local nRare = rng:NextInteger(s.RareMin, s.RareMax)
		deck = take(rng, rares, nRare)
		for _, id in take(rng, commons, Deck.SIZE - nRare) do
			table.insert(deck, id)
		end
	else
		local nEpic = rng:NextInteger(s.EpicMin, s.EpicMax)
		deck = take(rng, rares, Deck.SIZE - nEpic)
		for _, id in take(rng, epics, nEpic) do
			table.insert(deck, id)
		end
	end
	-- Shuffle the order (Fisher-Yates).
	for i = #deck, 2, -1 do
		local j = rng:NextInteger(1, i)
		deck[i], deck[j] = deck[j], deck[i]
	end
	return deck
end

-- {Name, DR, RankIndex, Deck}: a display name, a DR inside the rank's range and a recipe deck.
function Bot.Make(rankIndex: number, rng)
	local rank = math.clamp(rankIndex, 1, #Bots.Ranks)
	local s = settings(rank)
	return {
		Name = Bots.Names[rng:NextInteger(1, #Bots.Names)],
		DR = rng:NextInteger(s.DR.Min, s.DR.Max),
		RankIndex = rank,
		Deck = buildDeck(rank, rng),
	}
end

-- Play state for one bot seat. `rng` should be its own Random (not the match's) so play stays reproducible.
function Bot.New(rankIndex: number, rng)
	local rank = math.clamp(rankIndex, 1, #Bots.Ranks)
	return { rankIndex = rank, s = settings(rank), rng = rng, nextAt = nil, recent = {} }
end

local function delay(bot): number
	return bot.rng:NextNumber(bot.s.ReactionMin, bot.s.ReactionMax)
end

-- Legal merge pair on the board: the lowest-pip pair, or the highest-pip pair when `high`. Ties go to the lowest cell.
local function findPair(board, high: boolean): (number?, number?)
	local seen = {} -- "type|pip" -> first cell
	local bestPip, bestFrom, bestTo
	for cell = 1, Balance.BoardCells do
		local die = board[cell]
		if die and die.pip < Board.MAX_PIP then
			local key = die.type .. "|" .. die.pip
			local first = seen[key]
			if first == nil then
				seen[key] = cell
			elseif bestPip == nil or (if high then die.pip > bestPip else die.pip < bestPip) then
				bestPip, bestFrom, bestTo = die.pip, first, cell
			end
		end
	end
	return bestFrom, bestTo
end

-- The deck type with the most dice on the board (lowest tier on ties) that can still be powered up.
local function powerUpTarget(seat): string?
	local count = {}
	for _, die in seat.board do
		if die then
			count[die.type] = (count[die.type] or 0) + 1
		end
	end
	local best, bestCount, bestTier
	for _, id in seat.deck do
		local tier = seat.tiers[id]
		if tier and Formulas.PowerUpCost(tier) ~= nil then
			local n = count[id] or 0
			if best == nil or n > bestCount or (n == bestCount and tier < bestTier) then
				best, bestCount, bestTier = id, n, tier
			end
		end
	end
	return best
end

local function diceOnBoard(board): number
	local n = 0
	for _, die in board do
		if die then
			n += 1
		end
	end
	return n
end

-- Performed intents so far this rolling second (the human tap-rate cap).
local function underCap(bot, now: number): boolean
	local keep = {}
	for _, t in bot.recent do
		if now - t < 1 then
			table.insert(keep, t)
		end
	end
	bot.recent = keep
	return #keep < bot.s.MaxPerSecond
end

-- Lets the bot act for `seatIndex` at time `now`. At most one intent per reaction delay. Returns the intents it
-- performed this call: { { Kind = "Summon" } | { Kind = "Merge", From, To } | { Kind = "PowerUp", TypeId } }.
-- `match` can be swapped for a stub in tests.
function Bot.Step(bot, state, seatIndex: number, now: number, match: any?)
	local performed = {}
	if state.phase ~= "Playing" then
		return performed
	end
	local M = match or Match
	if bot.nextAt == nil then
		bot.nextAt = now + delay(bot)
	end
	if now < bot.nextAt or not underCap(bot, now) then
		return performed
	end
	local s, rng = bot.s, bot.rng
	local seat = M.Seat(state, seatIndex)
	bot.nextAt = now + delay(bot)

	if rng:NextNumber() < s.MistakeChance then
		bot.nextAt += delay(bot) -- hesitates: loses this turn
		return performed
	end

	local empties = #Board.EmptyCells(seat.board)
	local canSummon = empties > 0 and seat.mp >= Formulas.SummonCost(seat.summons)
	local from, to = findPair(seat.board, rng:NextNumber() < s.HighPipBias)
	local wantsMerge = from ~= nil and (empties <= 2 or rng:NextNumber() < s.MergeEagerness)

	local function record(intent)
		table.insert(performed, intent)
		table.insert(bot.recent, now)
	end

	if wantsMerge and (empties <= 2 or not canSummon or rng:NextNumber() < 0.5) then
		if M.TryMerge(state, from, to, seatIndex) then
			record({ Kind = "Merge", From = from, To = to })
			return performed
		end
	end
	if canSummon then
		if M.TrySummon(state, seatIndex) then
			record({ Kind = "Summon" })
			return performed
		end
	end
	-- Nothing else to do: spend spare MP on a Power Up once the board is busy enough.
	if
		s.PowerUpEagerness > 0
		and diceOnBoard(seat.board) >= s.PowerUpMinDice
		and rng:NextNumber() < s.PowerUpEagerness
	then
		local typeId = powerUpTarget(seat)
		if typeId and M.TryPowerUp(state, typeId, seatIndex) then
			record({ Kind = "PowerUp", TypeId = typeId })
			return performed
		end
	end
	return performed
end

return Bot
