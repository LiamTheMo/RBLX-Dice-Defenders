-- Thin glue between the remotes, the profile and the pure Rules.Match. Owns the
-- server's shared match. The first player can start Solo and the first two can opt into Co-op.
-- A Duel never uses the local ready-up: it is queued through QueueService and runs in a reserved "Duel server"
-- (this module detects that role from the TeleportData and starts the match itself). Only when the queue or the
-- teleport service is unavailable (Studio) does a human-vs-bot Duel run in the lobby server.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Balance = require(script.Parent.Parent.Config.Balance)
local Matchmaking = require(script.Parent.Parent.Config.Matchmaking)
local Progression = require(script.Parent.Parent.Config.Progression)
local Passes = require(script.Parent.Parent.Config.Passes)
local RollConfig = require(script.Parent.Parent.Config.Roll)
local ShopConfig = require(script.Parent.Parent.Config.Shop)
local Net = require(script.Parent.Parent.Infrastructure.Net)
local Admin = require(script.Parent.Parent.Rules.Admin)
local Bag = require(script.Parent.Parent.Rules.Bag)
local Catalog = require(script.Parent.Parent.Rules.Catalog)
local Bot = require(script.Parent.Parent.Rules.Bot)
local Claims = require(script.Parent.Parent.Rules.Claims)
local Deck = require(script.Parent.Parent.Rules.Deck)
local DuelRoom = require(script.Parent.Parent.Rules.DuelRoom)
local DuelSettle = require(script.Parent.Parent.Rules.DuelSettle)
local Matchmaker = require(script.Parent.Parent.Rules.Matchmaker)
local Rating = require(script.Parent.Parent.Rules.Rating)
local ResultCarry = require(script.Parent.Parent.Rules.ResultCarry)
local Teams = require(script.Parent.Parent.Rules.Teams)
local Economy = require(script.Parent.Parent.Rules.Economy)
local Formulas = require(script.Parent.Parent.Rules.Formulas)
local Match = require(script.Parent.Parent.Rules.Match)
local Quests = require(script.Parent.Parent.Rules.Quests)
local Roll = require(script.Parent.Parent.Rules.Roll)
local Shop = require(script.Parent.Parent.Rules.Shop)
local Settings = require(script.Parent.Parent.Rules.Settings)
local Tutorial = require(script.Parent.Parent.Rules.Tutorial)
local Upgrade = require(script.Parent.Parent.Rules.Upgrade)
local PlayerPolicy = require(script.Parent.PlayerPolicy)
local ProfileService = require(script.Parent.ProfileService)
local QueueService = require(script.Parent.QueueService)
local VipService = require(script.Parent.VipService)

local MatchService = {}

local owner: Player? = nil
local order: { Player } = {} -- loaded players, oldest first
local match = nil -- nil = Lobby
local participants: { Player } = {}
local readyForCoop: { [Player]: boolean } = {}
local duelResults: { [Player]: any } = {} -- this match's DuelResult per player
local rewards = {}
local xpFrom: { [Player]: any } = {} -- {XpFrom, LevelFrom, XpNeedFrom} per player, taken before this match's reward
local pendingResult: { [Player]: any } = {} -- lobby: {Data, Until} validated Duel result carried in TeleportData
local PENDING_RESULT_SECONDS = 60 -- PendingResult rides every State push this long after join (the client may connect late)
local returning: { [Player]: boolean } = {} -- a lobby teleport is already in flight
local shuttingDown = false -- set first thing in BindToClose: leavers then Abort a Duel instead of forfeiting
local DUEL_RETURN_SECONDS = 3 -- grace after a Duel ends before everyone is sent home (the result screen shows in the lobby)
-- A reserved Duel server (not a VIP server): PrivateServerId is set and nobody owns it.
local isDuelServer = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
local duelDesc = nil -- DuelRoom descriptor read from the first expected player's TeleportData
local duelFirstSeen = 0 -- server time the first expected player arrived
local duelArrived: { [number]: Player } = {} -- expected humans that joined, by UserId
local duelAborted = false -- the Duel was called off before it began (no DR)
local duelEndedAt: number? = nil
local duelReturned = false
local botState = nil -- Rules/Bot play state of seat 2 in a Duel against a bot
local searchSince: { [Player]: number } = {} -- server time each searching player pressed Find match
local catalog = Catalog.Build() -- the same display catalogue for every player
local lastTick = 0
local runRng = Random.new()
local rollRng = Random.new() -- server-only: every Roll draw
local lastDay = Quests.Day(os.time()) -- UTC day of the last Meta day-change check

local function isOwner(player: Player): boolean
	return owner == player
end

local function seatFor(player: Player): number?
	return table.find(participants, player)
end

local function boardView(seat)
	local view = {}
	for i = 1, Balance.BoardCells do
		local die = seat.board[i]
		view[i] = if die then { T = die.type, P = die.pip, L = if die.lockedBy then true else nil } else false
	end
	return view
end

-- Everything the lobby needs to draw the Find match button for this player.
local function canQueue(profile): boolean
	return not isDuelServer
		and (match == nil or match.phase ~= "Playing")
		and Tutorial.CanStart(profile)
		and Deck.IsReady(profile)
end

local function snapshot(player: Player)
	local profile = ProfileService.Get(player)
	if profile == nil then
		return { Phase = if ProfileService.LoadState(player) == "Failed" then "Failed" else "Loading" }
	end
	local out = {
		Gold = profile.Gold,
		BestWave = profile.BestWave,
		RunsPlayed = profile.RunsPlayed,
		TrialCleared = profile.TrialCleared,
		MP = 0,
		SummonCost = Formulas.SummonCost(0),
		Wave = 0,
		Lives = 0,
		MaxLives = Balance.StartLives,
		Board = {},
		CanSolo = isOwner(player) and not isDuelServer,
		CanCoop = not isDuelServer and order[2] ~= nil and (order[1] == player or order[2] == player),
		CoopReady = readyForCoop[player] == true,
		CanQueue = canQueue(profile),
		QueueState = QueueService.State(player),
		QueueSince = searchSince[player],
		QueueBotAfter = Matchmaking.BotAfterSeconds,
		CanSurrender = false,
		InDuelServer = isDuelServer,
		DuelWaiting = isDuelServer and match == nil and not duelAborted,
		Rating = Rating.View(profile.Rating),
	}
	for i = 1, Balance.BoardCells do
		out.Board[i] = false
	end
	local pending = pendingResult[player]
	if pending and os.clock() >= pending.Until then
		pendingResult[player] = nil
		pending = nil
	end
	out.PendingResult = if pending then pending.Data else nil -- lobby only: a Duel result carried by teleport
	local index = seatFor(player)
	if match == nil or not index then
		out.Phase = if match and match.phase == "Playing" then "NotOwner" else "Lobby"
		return out
	end
	local seat = Match.Seat(match, index)
	local partner = Match.Seat(match, 3 - index)
	out.Phase = match.phase
	out.Seat = index
	out.PlayerCount = match.playerCount
	out.MP = seat.mp
	out.SummonCost = Match.SummonCost(seat)
	out.Wave = match.wave
	out.WavesCompleted = match.wavesCompleted
	out.Mode = match.mode
	out.Lives = match.lives
	if match.mode == "Duel" then
		local other = 3 - index
		out.Lives = seat.lives
		out.OpponentLives = partner.lives
		local opponent = participants[other]
		local opponentDr = match.duelDr[other]
		out.Opponent = {
			Name = if opponent then opponent.DisplayName elseif match.bot then match.bot.Name else "Opponent",
			DR = opponentDr,
			Rank = Rating.RankOf(opponentDr).Name,
			IsBot = match.bot ~= nil,
		}
		out.CanSurrender = match.phase == "Playing"
		out.DuelResult = if match.phase == "Ended" then duelResults[player] else nil
	end
	out.NextWaveAt = if match.waveState == "Prep"
			and match.phase == "Playing"
			and not (match.playerCount == 1 and Tutorial.CanFinish(profile))
		then match.nextWaveAt
		else nil
	out.BossAt = match.bossAt
	out.BossVariant = match.nextBossVariant -- the boss that comes next, fixed until it spawns
	out.BossWave = Match.NextBossWave(match)
	out.BossPlan = Match.BossPlan(match, 4) -- read-only: upcoming boss waves, all fixed by runId
	out.Result = match.result
	if match.phase == "Ended" then -- read-only result-card extras; the client only displays them
		out.Kills = if match.mode == "Duel" then seat.kills else match.kills -- Co-op: the shared lane total
		out.DurationSec = math.max(0, math.floor(match.lastNow - match.startedAt))
		local opponent = if match.mode == "Duel" then participants[3 - index] else nil
		out.OpponentUserId = if opponent and match.bot == nil then opponent.UserId else nil
	end
	if match.phase == "Ended" then
		local before = xpFrom[player]
		if before then
			out.XpFrom, out.LevelFrom, out.XpNeedFrom = before.XpFrom, before.LevelFrom, before.XpNeedFrom
		end
		local duel = out.DuelResult
		out.RatingBefore = if type(duel) == "table" then duel.DRBefore else nil
	end
	local reward = rewards[player]
	out.RewardGold, out.RewardXp, out.RewardGems =
		if reward then reward.Gold or 0 else nil,
		if reward then reward.Xp or 0 else nil,
		if reward then reward.Gems or 0 else nil
	out.Tiers = Match.TiersView(seat)
	out.ChronoCells = if match.phase == "Playing" then Match.SupportCells(seat, "L01") else nil
	out.Board = boardView(seat)
	out.PartnerBoard = if partner then boardView(partner) else nil
	return out
end

local function push(player: Player)
	Net.Fire("State", player, snapshot(player))
end

local function byId(a, b)
	return a.Id < b.Id
end

-- {{Id, Quantity}} sorted by Id for a {[id] = count} map.
local function quantities(map)
	local list = {}
	for id, quantity in map do
		table.insert(list, { Id = id, Quantity = quantity })
	end
	table.sort(list, byId)
	return list
end

-- Lobby data for one player, sent to that player only. Arrays only (no sparse keys).
-- Saved team presets as {["1"] = {ids}, ...} (string keys: a sparse number-keyed table does not survive a remote).
local function teamsView(profile)
	local out = {}
	for key, ids in profile.Teams do
		out[key] = table.clone(ids)
	end
	return out
end

local function meta(player: Player, profile)
	local dice = {}
	for id, die in profile.Dice do
		table.insert(dice, { Id = id, Level = die.Level, Copies = die.Copies })
	end
	table.sort(dice, byId)
	local equipped = {}
	for _, id in profile.Cosmetics.Equipped do
		equipped[id] = true
	end
	local cosmetics = {}
	for id in profile.Cosmetics.Owned do
		table.insert(cosmetics, { Id = id, Equipped = equipped[id] == true })
	end
	table.sort(cosmetics, byId)
	local locked = {}
	for id in profile.Locked do
		table.insert(locked, id)
	end
	table.sort(locked)
	local pity = {}
	for _, pool in RollConfig.Pools do
		table.insert(pity, { Pool = pool.Id, Count = profile.RollPity[pool.Id] or 0 })
	end
	local purchases = {}
	for _, offer in ShopConfig.Offers do
		if offer.Limit then
			table.insert(purchases, { Id = offer.Id, Count = profile.Purchases[offer.Id] or 0 })
		end
	end
	local level, xpInto, xpNeed = Progression.Level(profile.Xp, Progression.Account)
	local now = os.time()
	local view, claims = Quests.View(profile, now), Claims.View(profile, now)
	return {
		Dice = dice,
		Deck = table.clone(profile.Deck),
		Teams = teamsView(profile), -- {[slot 1..5] = {dieIds}} for the saved presets only
		Quests = view.Quests,
		DailyResetAt = view.DailyResetAt,
		WeeklyResetAt = view.WeeklyResetAt,
		Login = claims.Login,
		Milestones = claims.Milestones,
		Achievements = claims.Achievements,
		Mastery = claims.Mastery,
		Rating = Rating.View(profile.Rating),
		Gems = profile.Gems,
		Gold = profile.Gold, -- die level-ups spend it
		CritBonus = Upgrade.CritBonus(profile), -- account crit damage percent earned from die levels
		Xp = profile.Xp,
		Level = level,
		XpInto = xpInto,
		XpNeed = xpNeed,
		Materials = quantities(profile.Materials),
		Items = quantities(profile.Items),
		Cosmetics = cosmetics,
		Locked = locked, -- sorted locked Material and Item ids
		Settings = table.clone(profile.Settings), -- {[settingId] = value}; a missing id is its default
		RollAllowed = PlayerPolicy.RollAllowed(player), -- false until the policy answer arrives (fail closed)
		RollDiscountPct = if VipService.IsVip(player) then RollConfig.VipDiscountPct else 0, -- VIP pass perk
		VipOffer = if Passes.Vip.Id ~= 0
				and not VipService.IsVip(player) -- the pass for sale: nil once owned or not created
			then { PassId = Passes.Vip.Id, Robux = Passes.Vip.Robux, Pct = RollConfig.VipDiscountPct }
			else nil,
		Tutorial = Tutorial.View(profile),
		Pity = pity, -- {{Pool, Count}}: rolls toward each pool's guarantee, in Config/Roll order
		Purchases = purchases, -- {{Id, Count}}: purchases of each limited Shop offer, in Config/Shop order
	}
end

local function pushMeta(player: Player)
	local profile = ProfileService.Get(player)
	if profile ~= nil then
		Net.Fire("Meta", player, meta(player, profile))
	end
end

local function pushAll()
	for _, player in Players:GetPlayers() do
		push(player)
	end
end

-- Drains the outbox to the owner: Enemies batch if non-empty, State if changed.
local function flush(intent: boolean?)
	if match == nil then
		return
	end
	local batch, dirty = Match.TakeOut(match)
	if #batch.S > 0 or #batch.H > 0 or #batch.R > 0 or #batch.F > 0 or #batch.A > 0 then
		for _, player in participants do
			Net.Fire("Enemies", player, batch)
		end
	end
	if dirty or intent then
		pushAll()
	end
end

-- Pays the reward once per match end; an Aborted run pays like a Lost one, Error grants nothing.
local function settle(skipPlayer: Player?)
	if match == nil or match.phase ~= "Ended" or match.rewardGranted then
		return
	end
	match.rewardGranted = true
	for _, player in participants do
		local profile = if player ~= skipPlayer then ProfileService.Get(player) else nil
		if profile then
			local level, into, need = Progression.Level(profile.Xp, Progression.Account)
			xpFrom[player] = { XpFrom = into, LevelFrom = level, XpNeedFrom = need }
		end
	end
	if match.result == "Duel" then
		-- DR and Gold apply once (Rating guards by run id); no quests and no Tutorial rewards for a Duel.
		local profiles = {}
		for index, player in participants do
			profiles[index] = if player ~= skipPlayer then ProfileService.Get(player) else nil
		end
		local vsBot = match.bot ~= nil
		local results = DuelSettle.Run(
			profiles,
			match.duelDr,
			match.duel,
			match.runId,
			match.wavesCompleted,
			if vsBot then Matchmaking.BotGoldFactor else nil,
			vsBot
		)
		local now = os.time()
		for index, player in participants do
			local profile = profiles[index]
			if profile == nil then
				continue
			end
			if not vsBot then
				-- Two humans: each remembers the other (cooldown). A bot is never recorded.
				local opponent = participants[3 - index]
				if opponent then
					Matchmaker.Record(profile, opponent.UserId, now)
				end
			end
			duelResults[player] = results[index]
			local result = results[index]
			if result then
				rewards[player] = { Gold = result.Gold, Xp = result.Xp, Gems = result.Gems }
			end
			ProfileService.MarkChanged(player) -- Changed pushes State and Meta (DR, Gold, Recent)
			task.spawn(ProfileService.SaveNow, player)
		end
		return
	end
	if match.mode == "Duel" then
		return -- an Aborted or Error Duel: no DR, no quest or Tutorial rewards, no reward panel
	end
	if match.result ~= "Lost" and match.result ~= "Aborted" then
		return
	end
	for index, player in participants do
		local profile = if player ~= skipPlayer then ProfileService.Get(player) else nil
		if profile then
			local seat = Match.Seat(match, index)
			local ok, bundle =
				Quests.SettleRun(profile, match.runId, match.wavesCompleted, match.kills, os.time(), seat.deck)
			local changed = Tutorial.ReachWave(profile, match.wavesCompleted)
			changed = Tutorial.Finish(profile) or changed
			if ok then
				rewards[player] = bundle
			else
				warn("[MatchService] Reward refused: " .. tostring(bundle))
			end
			if changed or ok then
				ProfileService.MarkChanged(player)
				task.spawn(ProfileService.SaveNow, player)
			end
		end
	end
end

local function assignOwner()
	owner = order[1]
	pushAll()
end

local function removeFromOrder(player: Player)
	local index = table.find(order, player)
	if index then
		table.remove(order, index)
	end
end

-- Sends a player back to the public lobby server (never yields the caller).
local function returnToLobby(player: Player, withResult: boolean?)
	if returning[player] then
		return
	end
	returning[player] = true
	local carry = if withResult and match and match.phase == "Ended" then ResultCarry.Build(snapshot(player)) else nil
	task.spawn(function()
		local ok = QueueService.TeleportToLobby(player, if carry then { [ResultCarry.KEY] = carry } else nil)
		if not ok then
			returning[player] = nil -- a failed teleport may be retried
		end
	end)
end

-- A Duel server whose Duel never began (second player missing or failed to load): no DR changes, everyone goes home.
local function abortDuel()
	if duelAborted then
		return
	end
	duelAborted = true
	for _, player in duelArrived do
		returnToLobby(player)
	end
	pushAll()
end

local function onLoaded(player: Player)
	if table.find(order, player) == nil then
		table.insert(order, player)
	end
	if owner == nil then
		owner = player
	end
	pushAll()
	Net.Fire("Catalog", player, catalog) -- before the first Meta, which refers to its ids
	local profile = ProfileService.Get(player)
	if profile and Tutorial.Finish(profile) then
		ProfileService.MarkChanged(player)
		task.spawn(ProfileService.SaveNow, player)
	else
		pushMeta(player)
	end
end

-- A departing teammate ends the shared run and settles earned rewards before profile release.
local function onRemoving(player: Player)
	removeFromOrder(player)
	readyForCoop[player] = nil
	QueueService.Cancel(player)
	searchSince[player] = nil
	duelArrived[player.UserId] = nil
	local seat = seatFor(player)
	if seat and match and match.phase == "Playing" then
		if match.mode == "Duel" and not (shuttingDown or ProfileService.IsShuttingDown()) then
			Match.Forfeit(match, seat) -- the leaver takes the loss; settle runs before the profile is released
		else
			Match.Finish(match, "Aborted")
		end
		settle()
	end
	if isDuelServer and match == nil and duelDesc and DuelRoom.SeatOf(duelDesc, player.UserId) then
		abortDuel() -- an expected player left before the Duel began
	end
	if player == owner then
		assignOwner()
	else
		pushAll()
	end
	rewards[player] = nil
	duelResults[player] = nil
	xpFrom[player] = nil
	pendingResult[player] = nil
	returning[player] = nil
end

-- runId is a random 31-bit integer so ids never repeat across servers; it only
-- has to differ from the profile's last paid id.
local function newRunId(profile, otherProfile): number
	-- shortcut: a fresh id collides with LastRewardRunId with probability 1/2^31 (re-rolled here); two matches sharing an id elsewhere is accepted.
	local id = runRng:NextInteger(1, 2 ^ 31 - 1)
	while
		id == profile.LastRewardRunId
		or id == profile.Rating.LastDuelRunId
		or (otherProfile and (id == otherProfile.LastRewardRunId or id == otherProfile.Rating.LastDuelRunId))
	do
		id = runRng:NextInteger(1, 2 ^ 31 - 1)
	end
	return id
end

-- Solo and Co-op only (a Duel starts through beginDuel).
local function startMatch(player, partner): (boolean, string?)
	if isDuelServer or (match and match.phase ~= "Ended") then
		return false, "WrongPhase"
	end
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "NotLoaded"
	end
	local otherProfile = if partner then ProfileService.Get(partner) else nil
	if partner and not otherProfile then
		return false, "NotLoaded"
	end
	if not Tutorial.CanStart(profile) or (otherProfile and not Tutorial.CanStart(otherProfile)) then
		return false, "FinishStarterRolls"
	end
	if not Deck.IsReady(profile) then
		return false, if partner then "PartnerDeck" else "BadDeck"
	end
	if otherProfile and not Deck.IsReady(otherProfile) then
		return false, "PartnerDeck"
	end
	table.clear(rewards)
	table.clear(duelResults)
	table.clear(xpFrom)
	table.clear(readyForCoop)
	participants = if partner then { player, partner } else { player }
	for _, member in participants do
		QueueService.Cancel(member) -- starting a match ends a search
		searchSince[member] = nil
	end
	botState = nil
	duelEndedAt = nil
	match = Match.New(
		newRunId(profile, otherProfile),
		Random.new(),
		workspace:GetServerTimeNow(),
		profile.Deck,
		otherProfile and otherProfile.Deck,
		Upgrade.CritBonus(profile),
		otherProfile and Upgrade.CritBonus(otherProfile),
		Upgrade.Levels(profile),
		otherProfile and Upgrade.Levels(otherProfile)
	)
	flush(true)
	return true, nil
end

-- Starts a Duel for `humans` (seat order) with their pre-match DR; `bot` fills seat 2 of a one-human Duel.
local function beginDuel(humans: { Player }, duelDr: { number }, bot): boolean
	local profiles = {}
	for index, human in humans do
		profiles[index] = ProfileService.Get(human)
		if profiles[index] == nil or not Deck.IsReady(profiles[index]) then
			return false
		end
	end
	if match and match.phase ~= "Ended" then
		return false
	end
	table.clear(rewards)
	table.clear(duelResults)
	table.clear(xpFrom)
	table.clear(readyForCoop)
	participants = table.clone(humans)
	for _, member in participants do
		QueueService.Cancel(member)
		searchSince[member] = nil
	end
	duelEndedAt = nil
	match = Match.NewDuel(
		newRunId(profiles[1], profiles[2]),
		Random.new(),
		workspace:GetServerTimeNow(),
		profiles[1].Deck,
		if bot then bot.Deck else profiles[2].Deck
	)
	-- Both seats are rated against the other's DR from before the match.
	match.duelDr = duelDr
	match.bot = bot
	botState = if bot then Bot.New(bot.RankIndex, Random.new()) else nil
	flush(true)
	return true
end

local function handleStart(player: Player): (boolean, string?)
	if QueueService.State(player) == "Matched" then
		return false, "WrongPhase" -- already being sent to a reserved Duel server
	end
	if not isOwner(player) then
		return false, "NotOwner"
	end
	return startMatch(player, nil)
end

local function handleCoopReady(player: Player, ready: boolean): (boolean, string?)
	if isDuelServer or (match and match.phase == "Playing") or QueueService.State(player) == "Matched" then
		return false, "WrongPhase"
	end
	local first, second = order[1], order[2]
	if not second or (player ~= first and player ~= second) then
		return false, "NeedPartner"
	end
	if ready then
		local profile = ProfileService.Get(player)
		if not profile then
			return false, "NotLoaded"
		end
		if not Tutorial.CanStart(profile) then
			return false, "FinishStarterRolls"
		end
		if not Deck.IsReady(profile) then
			return false, "BadDeck"
		end
	end
	readyForCoop[player] = if ready then true else nil
	if readyForCoop[first] and readyForCoop[second] then
		local ok, code = startMatch(first, second)
		if not ok then
			readyForCoop[player] = nil
			pushAll()
		end
		return ok, code
	end
	pushAll()
	return true, nil
end

-- Find match on (search) or off (stop). The decision logic lives in QueueService / Rules/DuelQueue.
local function handleQueueDuel(player: Player, on: boolean): (boolean, string?)
	if not on then
		if QueueService.State(player) == "Matched" then
			return false, "WrongPhase" -- the reserved server is already being joined
		end
		if QueueService.Cancel(player) then
			searchSince[player] = nil
			push(player)
		end
		return true, nil
	end
	if shuttingDown or ProfileService.IsShuttingDown() then
		return false, "Unavailable"
	end
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "NotLoaded"
	end
	if isDuelServer or (match and match.phase == "Playing") then
		return false, "WrongPhase"
	end
	if not Tutorial.CanStart(profile) then
		return false, "FinishStarterRolls"
	end
	if not Deck.IsReady(profile) then
		return false, "BadDeck"
	end
	if QueueService.State(player) == nil then
		readyForCoop[player] = nil -- a player searches or waits for Co-op, not both
		if not QueueService.Enqueue(player) then
			return false, "Unavailable"
		end
		searchSince[player] = workspace:GetServerTimeNow()
	end
	pushAll()
	return true, nil
end

-- Gives up the live Duel: only the caller's own seat loses.
local function handleSurrender(player: Player): (boolean, string?)
	local index = seatFor(player)
	if match == nil or match.mode ~= "Duel" or not index then
		return false, "NotInDuel"
	end
	if match.phase ~= "Playing" or not Match.Surrender(match, index) then
		return false, "WrongPhase"
	end
	settle()
	flush(true)
	return true, nil
end

-- Back to the public lobby server from a Duel server: allowed while waiting for the opponent (DuelWaiting) and after
-- the end; not while seated in a Playing Duel (Surrender first, or leaving forfeits).
local function handleLeaveDuel(player: Player): (boolean, string?)
	if not isDuelServer then
		return false, "NotInDuel"
	end
	if match and match.phase == "Playing" and seatFor(player) then
		return false, "WrongPhase"
	end
	returnToLobby(player, true)
	return true, nil
end

local function handleSummon(player: Player): (boolean, string?)
	local index = seatFor(player)
	if match == nil or not index then
		return false, "WrongPhase"
	end
	local ok, code = Match.TrySummon(match, index)
	flush(true)
	return ok, code
end

local function handleMerge(player: Player, from: number, to: number): (boolean, string?)
	local index = seatFor(player)
	if match == nil or not index then
		return false, "WrongPhase"
	end
	local ok, code = Match.TryMerge(match, from, to, index)
	flush(true)
	return ok, code
end

local function handlePowerUp(player: Player, typeId: string): (boolean, string?)
	local index = seatFor(player)
	if match == nil or not index then
		return false, "WrongPhase"
	end
	local ok, code = Match.TryPowerUp(match, typeId, index)
	flush(true)
	return ok, code
end

local function handleEquipDeck(player: Player, ids: any): (boolean, string?)
	if match and match.phase == "Playing" and seatFor(player) then
		return false, "WrongPhase"
	end
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "NotLoaded"
	end
	local ok, code = Deck.Equip(profile, ids)
	if ok then
		ProfileService.MarkChanged(player) -- Changed pushes Meta
		if #profile.Deck < Deck.SIZE and (readyForCoop[player] or QueueService.Cancel(player)) then
			readyForCoop[player] = nil
			searchSince[player] = nil
			push(player)
		end
	end
	return ok, code
end

-- Save the equipped deck into a team slot, or equip a saved team (same rules as EquipDeck).
local function handleTeamAction(player: Player, action: string, slot: number): (boolean, string?)
	if match and match.phase == "Playing" and seatFor(player) then
		return false, "WrongPhase"
	end
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "NotLoaded"
	end
	local ok, code = Teams.Run(profile, action, slot)
	if ok then
		ProfileService.MarkChanged(player) -- Changed pushes Meta
		if #profile.Deck < Deck.SIZE and (readyForCoop[player] or QueueService.Cancel(player)) then
			readyForCoop[player] = nil
			searchSince[player] = nil
			push(player)
		end
	end
	return ok, code
end

local function handleUpgradeDie(player: Player, id: string): (boolean, string?)
	if match and match.phase == "Playing" then
		return false, "WrongPhase"
	end
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "NotLoaded"
	end
	local ok, code = Upgrade.Die(profile, id)
	if ok then
		ProfileService.MarkChanged(player) -- Changed pushes State and Meta
	end
	return ok, code
end

local function handleClaimQuest(player: Player, id: string): (boolean, string?)
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "NotLoaded"
	end
	local ok, code = Claims.Claim(profile, id, os.time())
	if ok then
		Tutorial.Claimed(profile, id)
		ProfileService.MarkChanged(player)
	end
	return ok, code
end

local function handleSaveSettings(player: Player, patch: any): (boolean, string?)
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "NotLoaded"
	end
	Settings.Merge(profile, patch)
	ProfileService.MarkChanged(player)
	return true
end

local function handleBagAction(player: Player, action: string, id: string, qty: number): (boolean, string?)
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "NotLoaded"
	end
	local ok, code = Bag.Act(profile, action, id, qty)
	if ok then
		ProfileService.MarkChanged(player) -- Changed pushes State (Gold) and Meta
	end
	return ok, code
end

-- One Roll purchase: Rules/Roll validates, pays one bundle and writes the pity; the client sees the draw only in
-- RollResult. The policy is read from PlayerPolicy's cache (never yields; unknown = Restricted).
local function handleRoll(player: Player, poolId: string, count: number): (boolean, string?)
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "NotLoaded"
	end
	if not Tutorial.CanStart(profile) then
		return false, "FinishStarterRolls"
	end
	local discount = if VipService.IsVip(player) then RollConfig.VipDiscountPct else 0
	local ok, code, result = Roll.Buy(profile, poolId, count, PlayerPolicy.RollAllowed(player), rollRng, discount)
	if ok then
		ProfileService.MarkChanged(player) -- Changed pushes Meta (Gems, dice, pity)
		Net.Fire("RollResult", player, result)
	end
	return ok, code
end

-- One Gold or Gems Shop purchase: Rules/Shop validates, pays one bundle and counts a limited offer.
local function handleBuy(player: Player, offerId: string): (boolean, string?)
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "NotLoaded"
	end
	local ok, code = Shop.Buy(profile, offerId)
	if ok then
		ProfileService.MarkChanged(player) -- Changed pushes State (Gold) and Meta
	end
	return ok, code
end

-- Reserved Duel server: a joining player must be one the ticket expects; anyone else goes back to the lobby.
local function adoptDuelPlayer(player: Player)
	local ok, joinData = pcall(player.GetJoinData, player)
	local desc = DuelRoom.Parse(if ok and type(joinData) == "table" then joinData.TeleportData else nil)
	local expected = desc ~= nil
		and (duelDesc == nil or desc.MatchId == duelDesc.MatchId)
		and DuelRoom.SeatOf(desc, player.UserId) ~= nil
	if not expected or duelAborted or match ~= nil or shuttingDown then
		returnToLobby(player) -- unexpected, late (the Duel began without them) or the Duel was called off
		return
	end
	if duelDesc == nil then
		duelDesc = desc
		duelFirstSeen = workspace:GetServerTimeNow()
	end
	duelArrived[player.UserId] = player
end

-- Starts the ticketed Duel once every expected human has a loaded profile; aborts on a load failure or timeout.
local function checkDuelStart(now: number)
	if duelDesc == nil or match ~= nil or duelAborted then
		return
	end
	local loaded, failed = {}, {}
	for _, info in duelDesc.Players do
		local player = duelArrived[info.UserId]
		if player then
			if ProfileService.Get(player) then
				loaded[info.UserId] = true
			elseif ProfileService.LoadState(player) == "Failed" then
				failed[info.UserId] = true
			end
		end
	end
	local decision = DuelRoom.Decide(duelDesc, loaded, failed, duelFirstSeen, now)
	if decision == "Abort" then
		abortDuel()
	elseif decision == "Start" then
		local humans, duelDr = {}, {}
		for index, info in duelDesc.Players do
			humans[index] = duelArrived[info.UserId]
			duelDr[index] = info.DR -- DR from before the match, as ticketed
		end
		if duelDesc.Bot then
			duelDr[2] = duelDesc.Bot.DR
		end
		if not beginDuel(humans, duelDr, duelDesc.Bot) then
			abortDuel() -- a deck that is no longer valid: nobody is rated
		end
	end
end

-- Duel server upkeep: start or abort before the match, send everyone home a while after it ended.
local function duelServerTick(now: number)
	if match == nil then
		checkDuelStart(now)
	elseif match.phase == "Ended" and not duelReturned then
		duelEndedAt = duelEndedAt or now
		if now - duelEndedAt >= DUEL_RETURN_SECONDS then
			duelReturned = true
			for _, player in participants do
				returnToLobby(player, true)
			end
		end
	end
end

local function tick()
	local now = workspace:GetServerTimeNow()
	if now - lastTick < 1 / Balance.TickHz then
		return
	end
	lastTick = now
	if isDuelServer then
		duelServerTick(now)
	end
	-- Before the match early-out: the lobby needs the new day's quests and login too
	-- (a new week always starts on a new day, so this covers the weeklies).
	local day = Quests.Day(os.time())
	if day ~= lastDay then
		lastDay = day
		for _, player in order do
			pushMeta(player)
		end
	end
	if match == nil or match.phase ~= "Playing" then
		return
	end
	local soloProfile = if match.playerCount == 1 and participants[1] then ProfileService.Get(participants[1]) else nil
	if soloProfile and Tutorial.CanFinish(soloProfile) and match.wavesCompleted >= Tutorial.TargetWave then
		match.lastNow, match.nextWaveAt = now, now + 1
		return
	end
	if botState and match.bot then
		local botOk, botErr = pcall(Bot.Step, botState, match, 2, now)
		if not botOk then
			warn("[MatchService] Bot step failed: " .. tostring(botErr)) -- the Duel goes on without bot moves
			botState = nil
		end
	end
	local ok, err = pcall(Match.Step, match, now)
	if not ok then
		warn("[MatchService] Step failed: " .. tostring(err))
		Match.Finish(match, "Error")
	end
	for _, player in participants do
		local profile = if match.mode ~= "Duel" then ProfileService.Get(player) else nil -- no Tutorial rewards in a Duel
		if profile and Tutorial.ReachWave(profile, match.wavesCompleted) then
			ProfileService.MarkChanged(player)
			task.spawn(ProfileService.SaveNow, player)
		end
	end
	settle()
	flush()
end

function MatchService.AdminMP(player: Player?, delta: number)
	local index = if player then seatFor(player) else nil
	if not index or match == nil or match.phase ~= "Playing" then
		return false, "NoLiveMatch"
	end
	local ok, code = Economy.TryChange(Match.Seat(match, index), "mp", delta)
	if ok then
		push(player)
	end
	return ok, code
end

function MatchService.AdminReset(player: Player)
	readyForCoop[player] = nil
	QueueService.Cancel(player)
	searchSince[player] = nil
	if match and seatFor(player) and match.phase == "Playing" then
		Match.Finish(match, "Aborted")
		settle(player)
		flush(true)
	end
end

function MatchService.FinishTutorial(player: Player): (boolean, string?)
	if not match or match.phase ~= "Playing" or not seatFor(player) or match.wavesCompleted < Tutorial.TargetWave then
		return false, "WrongTutorialStep"
	end
	if match.playerCount ~= 1 then
		return false, "ContinueCoop"
	end
	Match.Finish(match, "Aborted")
	settle()
	flush(true)
	return true, nil
end

function MatchService.Init()
	Net.SetReadyCheck(function(player, name)
		if name == "AdminAction" then
			return Admin.IsAllowed(player.UserId), "Forbidden"
		end
		if name == "LeaveDuel" then
			return true, nil -- a player still loading in a Duel server may go home (the handler checks the server role)
		end
		if ProfileService.Get(player) == nil then
			return false, "NotLoaded"
		end
		return true, nil
	end)
	Net.Handle("Start", handleStart)
	Net.Handle("CoopReady", handleCoopReady)
	Net.Handle("QueueDuel", handleQueueDuel)
	Net.Handle("Surrender", handleSurrender)
	Net.Handle("LeaveDuel", handleLeaveDuel)
	Net.Handle("Summon", handleSummon)
	Net.Handle("Merge", handleMerge)
	Net.Handle("PowerUp", handlePowerUp)
	Net.Handle("EquipDeck", handleEquipDeck)
	Net.Handle("TeamAction", handleTeamAction)
	Net.Handle("ClaimQuest", handleClaimQuest)
	Net.Handle("SaveSettings", handleSaveSettings)
	Net.Handle("BagAction", handleBagAction)
	Net.Handle("Roll", handleRoll)
	Net.Handle("Buy", handleBuy)
	Net.Handle("UpgradeDie", handleUpgradeDie)
end

-- The queue found no human opponent in time (or the queue is unavailable): the Duel against a bot runs right here.
local function onLocalBot(player: Player, bot)
	searchSince[player] = nil
	local profile = ProfileService.Get(player)
	if profile == nil or player.Parent == nil or isDuelServer then
		push(player)
		return
	end
	if not beginDuel({ player }, { profile.Rating.DR, bot.DR }, bot) then
		push(player) -- busy (a match is Playing) or the deck went bad: the search simply ends
	end
end

-- Lobby server: a player arriving from a finished Duel carries its result; keep it only if it validates.
local function readCarry(player: Player)
	local ok, joinData = pcall(player.GetJoinData, player)
	local data = if ok then ResultCarry.FromJoinData(joinData) else nil
	pendingResult[player] = if data then { Data = data, Until = os.clock() + PENDING_RESULT_SECONDS } else nil
end

function MatchService.Start()
	if not isDuelServer then
		Players.PlayerAdded:Connect(readCarry)
		for _, player in Players:GetPlayers() do
			readCarry(player)
		end
	end
	if isDuelServer then
		Players.PlayerAdded:Connect(adoptDuelPlayer)
		for _, player in Players:GetPlayers() do
			task.spawn(adoptDuelPlayer, player)
		end
	end
	QueueService.Changed:Connect(function(player)
		if player.Parent ~= nil then
			if QueueService.State(player) == nil then
				searchSince[player] = nil
			end
			push(player) -- Matched or the match ticket expired
		end
	end)
	QueueService.LocalBot:Connect(onLocalBot)
	ProfileService.Loaded:Connect(onLoaded)
	ProfileService.Removing:Connect(onRemoving)
	ProfileService.LoadStateChanged:Connect(function(player)
		-- A lost lease (Failed) ends the owner's match like leaving: no reward, reassign.
		if ProfileService.LoadState(player) == "Failed" and table.find(order, player) then
			onRemoving(player)
		end
		push(player)
	end)
	ProfileService.Left:Connect(function(player)
		-- A player who failed to load or lost their lease is not in `order` or is dropped here.
		if table.find(order, player) then
			onRemoving(player)
		end
	end)
	ProfileService.Changed:Connect(function(player)
		push(player) -- Gold/stats live in State (a quest claim changes Gold)
		pushMeta(player)
	end)
	PlayerPolicy.Changed:Connect(pushMeta) -- RollAllowed arrived (no-op before the profile loads)
	VipService.Changed:Connect(pushMeta) -- the VIP discount arrived or was just bought
	RunService.Heartbeat:Connect(tick)
	-- Shutdown is a server reason, not a forfeit: end a live Duel as Aborted (no DR) before ProfileService's own
	-- BindToClose fires Removing for everyone (callbacks run concurrently: onRemoving also checks the shared flag).
	game:BindToClose(function()
		shuttingDown = true
		if match and match.phase == "Playing" and match.mode == "Duel" then
			Match.Finish(match, "Aborted")
			settle()
		end
	end)
end

return MatchService
