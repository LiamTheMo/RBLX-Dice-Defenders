-- Decisions of a reserved Duel server (docs/DICE_RATING.md section 9). Pure: TeleportData in, plain tables out.
-- The service reads `player:GetJoinData().TeleportData`, hands it to Parse, and asks Decide every tick.

local Config = require(script.Parent.Parent.Config.Matchmaking)
local Dice = require(script.Parent.Parent.Config.Dice)
local RatingConfig = require(script.Parent.Parent.Config.Rating)
local Deck = require(script.Parent.Deck)
local Rating = require(script.Parent.Rating)
local Validate = require(script.Parent.Validate)

local DuelRoom = {}

local MAX_RANK_INDEX = #RatingConfig.Ranks

local function cleanInfo(info: any): any?
	if type(info) ~= "table" then
		return nil
	end
	if
		not Validate.IsInt(info.UserId, 1, 2 ^ 53)
		or not Validate.IsInt(info.DR, 0, 2 ^ 31 - 1)
		or type(info.Name) ~= "string"
		or #info.Name > 64
	then
		return nil
	end
	local rank = Rating.RankOf(info.DR)
	return { UserId = info.UserId, DR = info.DR, RankIndex = rank.Index, Rank = rank.Name, Name = info.Name }
end

local function cleanBot(bot: any): any?
	if type(bot) ~= "table" or type(bot.Name) ~= "string" or #bot.Name > 64 then
		return nil
	end
	if not Validate.IsInt(bot.DR, 0, 2 ^ 31 - 1) or not Validate.IsInt(bot.RankIndex, 1, MAX_RANK_INDEX) then
		return nil
	end
	if not Deck.Shape(bot.Deck) or #bot.Deck ~= Deck.SIZE then
		return nil
	end
	local deck = {}
	for i, id in bot.Deck do
		if Dice.Types[id] == nil then
			return nil
		end
		deck[i] = id
	end
	return { Name = bot.Name, DR = bot.DR, RankIndex = bot.RankIndex, Deck = deck, IsBot = true }
end

-- A validated descriptor { MatchId, Players = {PlayerInfo}, Bot? } or nil. Two humans and no bot, or one human and a bot.
function DuelRoom.Parse(data: any)
	if type(data) ~= "table" or data.Mode ~= "Duel" then
		return nil
	end
	if type(data.MatchId) ~= "string" or #data.MatchId < 1 or #data.MatchId > 64 then
		return nil
	end
	if type(data.Players) ~= "table" then
		return nil
	end
	local players, seen = {}, {}
	for index = 1, 2 do
		local raw = data.Players[index]
		if raw == nil then
			break
		end
		local info = cleanInfo(raw)
		if info == nil or seen[info.UserId] then
			return nil
		end
		seen[info.UserId] = true
		players[index] = info
	end
	if data.Players[#players + 1] ~= nil then
		return nil -- more than two (or a hole)
	end
	local bot = nil
	if data.Bot ~= nil then
		bot = cleanBot(data.Bot)
		if bot == nil then
			return nil
		end
	end
	if #players ~= (if bot then 1 else 2) then
		return nil
	end
	return { MatchId = data.MatchId, Players = players, Bot = bot }
end

-- Seat (1 or 2) of a user in the descriptor, or nil for an unexpected player.
function DuelRoom.SeatOf(desc, userId: number): number?
	for index, info in desc.Players do
		if info.UserId == userId then
			return index
		end
	end
	return nil
end

-- "Start" when every expected human is loaded; "Abort" when one failed to load or the wait ran out (no DR changes);
-- else "Wait". `loaded` and `failed` are sets of user ids; `since` is when the first expected player arrived.
function DuelRoom.Decide(
	desc,
	loaded: { [number]: boolean },
	failed: { [number]: boolean },
	since: number,
	now: number
): string
	local allLoaded = true
	for _, info in desc.Players do
		if failed[info.UserId] then
			return "Abort"
		end
		if not loaded[info.UserId] then
			allLoaded = false
		end
	end
	if allLoaded then
		return "Start"
	end
	if now - since >= Config.SecondPlayerTimeoutSeconds then
		return "Abort"
	end
	return "Wait"
end

return DuelRoom
