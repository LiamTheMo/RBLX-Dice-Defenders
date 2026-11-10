-- Thin glue between the remotes, the profile and the pure Rules.Match. Owns the
-- single match of this server (solo MVP): the owner is the first player whose
-- profile loaded; everyone else is "NotOwner". Rules stay in Rules/*.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Balance = require(script.Parent.Parent.Config.Balance)
local Net = require(script.Parent.Parent.Infrastructure.Net)
local Deck = require(script.Parent.Parent.Rules.Deck)
local Formulas = require(script.Parent.Parent.Rules.Formulas)
local Match = require(script.Parent.Parent.Rules.Match)
local Quests = require(script.Parent.Parent.Rules.Quests)
local ProfileService = require(script.Parent.ProfileService)

local MatchService = {}

local owner: Player? = nil
local order: { Player } = {} -- loaded players, oldest first
local match = nil -- nil = Lobby
local rewardGold: number? = nil
local lastTick = 0
local runRng = Random.new()
local lastDay = Quests.Day(os.time()) -- UTC day of the last Meta day-change check

local function isOwner(player: Player): boolean
	return owner == player
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
		Energy = 0,
		SummonCost = Formulas.SummonCost(0),
		Wave = 0,
		Lives = 0,
		Board = {},
	}
	for i = 1, Balance.BoardCells do
		out.Board[i] = false
	end
	if not isOwner(player) then
		out.Phase = "NotOwner"
		return out
	end
	if match == nil then
		out.Phase = "Lobby"
		return out
	end
	out.Phase = match.phase
	out.Energy = match.energy
	out.SummonCost = Match.SummonCost(match)
	out.Wave = match.wave
	out.Lives = match.lives
	out.NextWaveAt = if match.waveState == "Prep" and match.phase == "Playing" then match.nextWaveAt else nil
	out.BossAt = match.bossAt
	out.Result = match.result
	out.RewardGold = rewardGold
	for i = 1, Balance.BoardCells do
		local die = match.board[i]
		if die then
			out.Board[i] = { T = die.type, P = die.pip }
		end
	end
	return out
end

local function push(player: Player)
	Net.Fire("State", player, snapshot(player))
end

-- Lobby data for one player, sent to that player only. Arrays only (no sparse keys).
local function meta(profile)
	local dice = {}
	for id, die in profile.Dice do
		table.insert(dice, { Id = id, Level = die.Level, Copies = die.Copies })
	end
	table.sort(dice, function(a, b)
		return a.Id < b.Id
	end)
	local view = Quests.View(profile, os.time())
	return { Dice = dice, Deck = table.clone(profile.Deck), Quests = view.Quests, DailyResetAt = view.DailyResetAt }
end

local function pushMeta(player: Player)
	local profile = ProfileService.Get(player)
	if profile ~= nil then
		Net.Fire("Meta", player, meta(profile))
	end
end

local function pushAll()
	for _, player in Players:GetPlayers() do
		push(player)
	end
end

-- Drains the outbox to the owner: Enemies batch if non-empty, State if changed.
local function flush(intent: boolean?)
	if match == nil or owner == nil then
		return
	end
	local batch, dirty = Match.TakeOut(match)
	if #batch.S > 0 or #batch.H > 0 or #batch.R > 0 or #batch.F > 0 then
		Net.Fire("Enemies", owner, batch)
	end
	if dirty or intent then
		push(owner)
	end
end

-- Pays the reward once per match end; Aborted and Error grant nothing.
local function settle()
	if match == nil or match.phase ~= "Ended" or match.rewardGranted then
		return
	end
	match.rewardGranted = true
	if (match.result ~= "Won" and match.result ~= "Lost") or owner == nil then
		return
	end
	local profile = ProfileService.Get(owner)
	if profile == nil then
		return
	end
	local ok, gold =
		Quests.SettleRun(profile, match.runId, match.wavesCompleted, match.result == "Won", match.kills, os.time())
	if not ok then
		warn("[MatchService] Reward refused: " .. tostring(gold))
		return
	end
	rewardGold = gold
	ProfileService.MarkChanged(owner)
	task.spawn(ProfileService.SaveNow, owner)
end

local function abortMatch()
	if match then
		Match.Finish(match, "Aborted")
		match.rewardGranted = true -- no reward
		match = nil
		rewardGold = nil
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

local function onLoaded(player: Player)
	if table.find(order, player) == nil then
		table.insert(order, player)
	end
	if owner == nil then
		owner = player
	end
	push(player)
	pushMeta(player)
end

-- Before the release save: an owner leaving (or shutdown) aborts without reward.
local function onRemoving(player: Player)
	removeFromOrder(player)
	if player == owner then
		abortMatch()
		assignOwner()
	end
end

-- runId is a random 31-bit integer so ids never repeat across servers; it only
-- has to differ from the profile's last paid id.
local function newRunId(profile): number
	-- shortcut: a fresh id collides with LastRewardRunId with probability 1/2^31 (re-rolled here); two matches sharing an id elsewhere is accepted.
	local id = runRng:NextInteger(1, 2 ^ 31 - 1)
	while id == profile.LastRewardRunId do
		id = runRng:NextInteger(1, 2 ^ 31 - 1)
	end
	return id
end

local function handleStart(player: Player): (boolean, string?)
	if match and match.phase ~= "Ended" then
		return false, "WrongPhase"
	end
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "NotLoaded"
	end
	if not Deck.Check(profile.Dice, profile.Deck) then
		return false, "BadDeck" -- never swap in a different deck silently
	end
	rewardGold = nil
	match = Match.New(newRunId(profile), Random.new(), workspace:GetServerTimeNow(), profile.Deck)
	flush(true)
	return true, nil
end

local function handleSummon(): (boolean, string?)
	if match == nil then
		return false, "WrongPhase"
	end
	local ok, code = Match.TrySummon(match)
	flush(true)
	return ok, code
end

local function handleMerge(_, from: number, to: number): (boolean, string?)
	if match == nil then
		return false, "WrongPhase"
	end
	local ok, code = Match.TryMerge(match, from, to)
	flush(true)
	return ok, code
end

local function handleEquipDeck(player: Player, ids: any): (boolean, string?)
	if match and match.phase == "Playing" then
		return false, "WrongPhase"
	end
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "NotLoaded"
	end
	local ok, code = Deck.Equip(profile, ids)
	if ok then
		ProfileService.MarkChanged(player) -- Changed pushes Meta
	end
	return ok, code
end

local function handleClaimQuest(player: Player, id: string): (boolean, string?)
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "NotLoaded"
	end
	local ok, code = Quests.Claim(profile, id, os.time())
	if ok then
		ProfileService.MarkChanged(player)
	end
	return ok, code
end

local function tick()
	local now = workspace:GetServerTimeNow()
	if now - lastTick < 1 / Balance.TickHz then
		return
	end
	lastTick = now
	-- Before the match early-out: the lobby needs the new day's quests too.
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
	local ok, err = pcall(Match.Step, match, now)
	if not ok then
		warn("[MatchService] Step failed: " .. tostring(err))
		Match.Finish(match, "Error")
	end
	settle()
	flush()
end

function MatchService.Init()
	Net.SetReadyCheck(function(player)
		if ProfileService.Get(player) == nil then
			return false, "NotLoaded"
		end
		if not isOwner(player) then
			return false, "NotOwner"
		end
		return true, nil
	end)
	Net.Handle("Start", handleStart)
	Net.Handle("Summon", handleSummon)
	Net.Handle("Merge", handleMerge)
	Net.Handle("EquipDeck", handleEquipDeck)
	Net.Handle("ClaimQuest", handleClaimQuest)
end

function MatchService.Start()
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
	RunService.Heartbeat:Connect(tick)
end

return MatchService
