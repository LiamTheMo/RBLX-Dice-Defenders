-- Duel matchmaking core (docs/DICE_RATING.md section 9). Pure: no Roblox services, no clock reads;
-- callers pass `now` (os.time seconds). Services live behind MemoryStoreGateway / TeleportGateway.
--
-- Queue entry (stored in the sorted map, key = tostring(UserId)):
--   { UserId, DR, RankIndex, EnqueuedAt, Recent = { {UserId, At} ... }, IsAdmin }
-- Match ticket (stored once per player, key = tostring(UserId), written by the pairing server):
--   { MatchId, ReservedAccessCode, PlaceId, Players = { {UserId, DR, RankIndex, Rank, Name} x2 }, CreatedAt }
-- TeleportData for the reserved server: { Mode = "Duel", MatchId, Players }.

local Config = require(script.Parent.Parent.Config.Matchmaking)

local Matchmaker = {}

export type Recent = { UserId: number, At: number }
export type Entry = {
	UserId: number,
	DR: number,
	RankIndex: number,
	EnqueuedAt: number,
	Recent: { Recent },
	IsAdmin: boolean?,
}
export type PlayerInfo = { UserId: number, DR: number, RankIndex: number, Rank: string, Name: string }
export type Ticket = {
	MatchId: string,
	ReservedAccessCode: string,
	PlaceId: number,
	Players: { PlayerInfo },
	CreatedAt: number,
}

local function foughtRecently(entry: Entry, otherId: number, now: number): boolean
	for _, past in entry.Recent or {} do
		if past.UserId == otherId and now - past.At < Config.CooldownSeconds then
			return true
		end
	end
	return false
end

function Matchmaker.Compatible(a: Entry, b: Entry, now: number): boolean
	if a.UserId == b.UserId or math.abs(a.RankIndex - b.RankIndex) > Config.MaxRankGap then
		return false
	end
	if a.IsAdmin or b.IsAdmin then
		return true
	end
	return not (foughtRecently(a, b.UserId, now) or foughtRecently(b, a.UserId, now))
end

-- True when `x` is tried before `y` (longest waiting first, UserId breaks ties).
local function waitsLonger(x: Entry, y: Entry): boolean
	if x.EnqueuedAt ~= y.EnqueuedAt then
		return x.EnqueuedAt < y.EnqueuedAt
	end
	return x.UserId < y.UserId
end

-- The longest-waiting entry that has a compatible partner, with its best partner (smallest rank gap,
-- then DR gap, then longest waiting). Deterministic for any input order. Returns (a, b) or (nil, nil).
function Matchmaker.FindPair(entries: { Entry }, now: number): (Entry?, Entry?)
	local order = table.clone(entries)
	table.sort(order, waitsLonger)
	for _, a in order do
		local best: Entry? = nil
		local bestRank, bestDr = 0, 0
		for _, b in order do
			if Matchmaker.Compatible(a, b, now) then
				-- `order` is sorted longest-waiting first, so a strict improvement keeps the longest waiter on ties.
				local rankGap, drGap = math.abs(a.RankIndex - b.RankIndex), math.abs(a.DR - b.DR)
				if best == nil or rankGap < bestRank or (rankGap == bestRank and drGap < bestDr) then
					best, bestRank, bestDr = b, rankGap, drGap
				end
			end
		end
		if best then
			return a, best
		end
	end
	return nil, nil
end

function Matchmaker.WantsBot(entry: Entry, now: number): boolean
	return now - entry.EnqueuedAt >= Config.BotAfterSeconds
end

-- A ticket or entry created `createdAt` is dead after `ttl` seconds (default: the queue ticket lifetime).
function Matchmaker.IsExpired(createdAt: number, now: number, ttl: number?): boolean
	return now - createdAt >= (ttl or Config.TicketTtlSeconds)
end

-- Remember a human opponent on profile.Rating.Recent (newest last, at most RecentMax). Bots (no or
-- non-positive UserId) are never recorded; an older record of the same opponent is replaced.
function Matchmaker.Record(profile, opponentUserId: number?, now: number)
	if type(opponentUserId) ~= "number" or opponentUserId <= 0 then
		return
	end
	local rating = profile.Rating
	local kept = {}
	for _, past in rating.Recent or {} do
		if past.UserId ~= opponentUserId then
			table.insert(kept, past)
		end
	end
	table.insert(kept, { UserId = opponentUserId, At = now })
	while #kept > Config.RecentMax do
		table.remove(kept, 1)
	end
	rating.Recent = kept
end

function Matchmaker.QueueEntry(
	userId: number,
	dr: number,
	rankIndex: number,
	recent: { Recent },
	isAdmin: boolean,
	now: number
): Entry
	return { UserId = userId, DR = dr, RankIndex = rankIndex, EnqueuedAt = now, Recent = recent, IsAdmin = isAdmin }
end

function Matchmaker.PlayerInfo(userId: number, dr: number, rankIndex: number, rank: string, name: string): PlayerInfo
	return { UserId = userId, DR = dr, RankIndex = rankIndex, Rank = rank, Name = name }
end

function Matchmaker.Ticket(
	matchId: string,
	accessCode: string,
	placeId: number,
	players: { PlayerInfo },
	now: number
): Ticket
	return { MatchId = matchId, ReservedAccessCode = accessCode, PlaceId = placeId, Players = players, CreatedAt = now }
end

function Matchmaker.TeleportData(ticket: Ticket)
	return { Mode = "Duel", MatchId = ticket.MatchId, Players = ticket.Players }
end

return Matchmaker
