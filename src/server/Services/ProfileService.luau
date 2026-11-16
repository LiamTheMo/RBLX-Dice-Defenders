-- Profile lifecycle: leased load on join, autosave, save + release on leave and
-- shutdown. Other services read the live profile with Get(player), mutate it
-- WITHOUT yielding, then call MarkChanged(player). A failed load never creates or
-- saves a default profile: LoadState is "Failed" and Get returns nil.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Signal = require(ReplicatedStorage.Shared.Core.Signal)

local DataStoreGateway = require(script.Parent.Parent.Infrastructure.DataStoreGateway)
local InMemoryDataStore = require(script.Parent.Parent.Infrastructure.InMemoryDataStore)
local ProfileStore = require(script.Parent.Parent.Infrastructure.ProfileStore)

local ProfileService = {}

-- Studio playtests get their own store so test progress never touches live profiles.
ProfileService.STORE_NAME = if RunService:IsStudio() then "DD_Profiles_v1_Studio" else "DD_Profiles_v1"
ProfileService.AUTOSAVE_SECONDS = 60
-- A crashed server's lease lasts SessionLease.DURATION_SECONDS (120); keep waiting a bit longer.
ProfileService.LOAD_WAIT_SECONDS = 130
ProfileService.LOAD_RETRY_SECONDS = 3
ProfileService.SHUTDOWN_BUDGET_SECONDS = 25
ProfileService.SHUTDOWN_DATASTORE_ATTEMPTS = 3

-- Loaded(player, profile): once loaded. Removing(player, profile): just before the
-- final release save. Left(player): every departure. LoadStateChanged(player):
-- Loading or Failed was entered. Changed(player): MarkChanged on a live profile.
ProfileService.Loaded = Signal.new()
ProfileService.Removing = Signal.new()
ProfileService.Left = Signal.new()
ProfileService.LoadStateChanged = Signal.new()
ProfileService.Changed = Signal.new()

local store = nil -- nil when no DataStore could be opened on a live server
local usingMemoryStore = false
local states = {} -- player -> { loadState: string }
local activeGateway = nil
local shuttingDown = false
local loading = {} -- userId -> true while a load/release for that user is running
local pendingLoads = 0

local function createStore()
	local opened, dataStore = pcall(function()
		return DataStoreService:GetDataStore(ProfileService.STORE_NAME)
	end)
	if opened and RunService:IsStudio() then
		-- Studio without "Enable Studio Access to API Services" cannot reach DataStores.
		opened, dataStore = pcall(function()
			dataStore:GetAsync("__probe")
			return dataStore
		end)
	end
	if not opened then
		if not RunService:IsStudio() then
			warn("[ProfileService] Could not open the DataStore; every load will fail: " .. tostring(dataStore))
			return nil
		end
		warn("[ProfileService] DataStores unavailable in Studio; using an in-memory store (not saved).")
		usingMemoryStore = true
		return DataStoreGateway.new({ store = InMemoryDataStore.new() })
	end
	return DataStoreGateway.new({
		store = dataStore,
		waitForBudget = function()
			while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) < 1 do
				task.wait(1)
			end
		end,
	})
end

local function setLoadState(player: Player, state, loadState: string)
	state.loadState = loadState
	if loadState == "Loading" or loadState == "Failed" then
		ProfileService.LoadStateChanged:Fire(player)
	end
end

local function waitForSaveSlot(userId: number)
	while store and store:IsSaving(userId) do
		task.wait(0.1)
	end
end

-- True while a connected player (other than `except`) holds a state for this user,
-- e.g. a rejoin on this server while an earlier release is still queued.
local function hasLivePlayer(userId: number, except: Player?): boolean
	for other in states do
		if other ~= except and other.UserId == userId and other.Parent ~= nil then
			return true
		end
	end
	return false
end

-- Sleeps up to `seconds`, waking early when the player leaves or the server closes.
local function sleepWhileHere(player: Player, seconds: number)
	local untilTime = os.clock() + seconds
	while os.clock() < untilTime and player.Parent ~= nil and not shuttingDown do
		task.wait(math.min(0.5, untilTime - os.clock()))
	end
end

-- Saves one cached profile; `player` is nil once they left (a release that failed
-- earlier is retried by the autosave loop).
local function saveUser(userId: number, release: boolean?, player: Player?)
	waitForSaveSlot(userId)
	if store == nil or not store:IsLoaded(userId) then
		return false, "NotLoaded"
	end
	if release and not shuttingDown and hasLivePlayer(userId, player) then
		release = false -- they rejoined meanwhile: keep the entry for the new session
	end
	local token = store:Peek(userId)
	local ok, reason = store:Save(userId, release)
	if not ok then
		warn(("[ProfileService] Save for %d failed: %s"):format(userId, tostring(reason)))
		if reason == "LeaseLost" or reason == "StaleRevision" then
			-- Another server owns this profile now; never write from here again.
			store:Forget(userId, token)
			local state = player and states[player]
			if state then
				setLoadState(player :: Player, state, "Failed")
			end
		end
	end
	return ok, reason
end

-- Leases and loads the profile; returns (profile) or (nil, reason). Runs while
-- loading[userId] is set so a rejoin cannot interleave with it.
local function loadBody(player: Player, userId: number)
	waitForSaveSlot(userId)
	local profile = store and store:Get(userId)
	local reason = if store then nil else "DataStoreUnavailable"
	if store and profile == nil then
		store:Forget(userId) -- a lost-lease copy is never reused
		local deadline = os.clock() + ProfileService.LOAD_WAIT_SECONDS
		local delay = ProfileService.LOAD_RETRY_SECONDS
		while true do
			if not player.Parent then
				return nil, "Left"
			end
			profile, reason = store:Load(userId)
			if profile or reason ~= "LeaseHeld" or shuttingDown or os.clock() + delay > deadline then
				break
			end
			sleepWhileHere(player, delay)
			delay = math.min(delay * 1.5, 10)
		end
	end
	if profile and (not player.Parent or shuttingDown) then
		saveUser(userId, true, nil) -- left (or server closing) while loading: hand the lease back
		return nil, "Left"
	end
	return profile, reason
end

local function loadPlayer(player: Player)
	local userId = player.UserId
	local state = { loadState = "Loading" }
	states[player] = state
	ProfileService.LoadStateChanged:Fire(player)

	-- A load or release for this user from an earlier session is still running:
	-- wait for it so it cannot delete this session's entry.
	while loading[userId] do
		task.wait(0.1)
	end
	if not player.Parent or states[player] ~= state then
		return
	end
	loading[userId] = true
	pendingLoads += 1
	local ran, profile, reason = pcall(loadBody, player, userId)
	loading[userId] = nil
	pendingLoads -= 1
	if not ran then
		reason = profile
		profile = nil
		warn("[ProfileService] Load crashed: " .. tostring(reason))
	end

	if reason == "Left" or not player.Parent or states[player] ~= state then
		return
	end
	if profile == nil then
		warn(("[ProfileService] Could not load profile %d: %s"):format(userId, tostring(reason)))
		setLoadState(player, state, "Failed")
		return
	end
	setLoadState(player, state, if usingMemoryStore then "Studio" else "Loaded")
	ProfileService.Loaded:Fire(player, profile)
end

local function removePlayer(player: Player)
	local state = states[player]
	if state == nil then
		return
	end
	local profile = store and store:Get(player.UserId)
	if profile then
		ProfileService.Removing:Fire(player, profile)
	end
	-- Always fires, even when there is no profile (failed load, lost lease).
	ProfileService.Left:Fire(player)
	if profile then
		saveUser(player.UserId, true, player)
	end
	if states[player] == state then
		states[player] = nil
	end
end

function ProfileService.Init()
	store = nil
	local gateway = createStore()
	activeGateway = gateway
	if gateway then
		local jobId = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)
		store = ProfileStore.new({ gateway = gateway, jobId = jobId, clock = os.time })
	end
end

function ProfileService.Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(loadPlayer, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end
	Players.PlayerRemoving:Connect(removePlayer)

	-- Autosave renews every lease; profiles whose player left (a release that
	-- failed earlier) are released again.
	task.spawn(function()
		while true do
			task.wait(ProfileService.AUTOSAVE_SECONDS)
			if store then
				for _, userId in store:LoadedUserIds() do
					local player = Players:GetPlayerByUserId(userId)
					task.spawn(saveUser, userId, player == nil, player)
				end
			end
		end
	end)

	game:BindToClose(function()
		shuttingDown = true
		if store == nil then
			return
		end
		activeGateway:SetMaxAttempts(ProfileService.SHUTDOWN_DATASTORE_ATTEMPTS)
		local remaining = 0
		for _, player in Players:GetPlayers() do
			local profile = store:Get(player.UserId)
			if profile then
				pcall(function()
					ProfileService.Removing:Fire(player, profile)
				end)
			end
		end
		for _, userId in store:LoadedUserIds() do
			remaining += 1
			task.spawn(function()
				saveUser(userId, true, Players:GetPlayerByUserId(userId))
				remaining -= 1
			end)
		end
		local deadline = os.clock() + ProfileService.SHUTDOWN_BUDGET_SECONDS
		while (remaining > 0 or pendingLoads > 0) and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

-- The live profile, or nil while loading, after a failed load or lost lease.
function ProfileService.Get(player: Player)
	local state = states[player]
	if state == nil or store == nil then
		return nil
	end
	if state.loadState ~= "Loaded" and state.loadState ~= "Studio" then
		return nil
	end
	return store:Get(player.UserId)
end

-- "Loading" | "Loaded" | "Studio" | "Failed" (nil for an unknown player).
function ProfileService.LoadState(player: Player): string?
	local state = states[player]
	return state and state.loadState
end

-- Call after mutating the profile (without yielding in between): marks it for saving.
function ProfileService.MarkChanged(player: Player)
	if ProfileService.Get(player) == nil then
		return
	end
	store:MarkDirty(player.UserId)
	ProfileService.Changed:Fire(player)
end

function ProfileService.SaveNow(player: Player)
	return saveUser(player.UserId, false, player)
end

return ProfileService
