-- Play menu controller: one Shell (title, close, WORLDS / 1v1 tabs) hosting the Play View.
-- Play.new(parent, { hud = LobbyHud, toast = (string) -> () }) -> :Open() :Close() :Toggle() :IsOpen() :Destroy()
-- Renders from PlayLogic with NetClient.Last, LastCatalog and LastMeta on open, whenever the phase, best wave or clear state
-- changes and on every Catalog / Meta push; START sends the guarded Start request, one at a time. CLAIM sends ClaimQuest for
-- that milestone, once per id until the next Meta (the server re-checks it and re-pushes Meta).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local NetClient = require(script.Parent.Parent.NetClient)
local PlayLogic = require(script.Parent.PlayLogic)
local RatingLogic = require(script.Parent.Parent.RatingLogic)
local Shell = require(script.Parent.Parent.Bag.Shell)
local View = require(script.Parent.View)

local ACTION = "PlayClose"

local Play = {}
Play.__index = Play

function Play.new(parent, deps)
	local self = setmetatable({}, Play)
	local hud = deps.hud
	local conns = {}
	local shell = Shell.new(parent, {
		fit = function()
			return hud:GetBagInsets()
		end,
		name = "Play",
		free = true,
		banner = { text = "PLAY" },
	})
	local view = View.new(shell.Slots.Content)
	shell:SetTabs({ { Id = "Worlds", Label = "WORLDS" }, { Id = "Ranks", Label = "1v1" } })
	shell:OnTab(function(i)
		view:SetPage(i)
	end)
	shell:SetTab(1)

	local busy = false
	local alive = true
	local function viewKey(snap)
		return snap
			and `{snap.Phase}|{snap.BestWave}|{snap.TrialCleared}|{snap.CanSolo}|{snap.CanCoop}|{snap.CoopReady}|{snap.CanQueue}|{snap.QueueState}|{snap.QueueSince}|{RatingLogic.progress(
				snap.Rating
			).Text}|{snap.Rating and snap.Rating.Streak}|{snap.Rating and snap.Rating.Rank}`
	end
	local pending = {} -- milestone ids with a ClaimQuest in flight, held until the next Meta after a success

	local shown -- the State fields the last render drew
	local function render()
		local snap = NetClient.Last
		shown = viewKey(snap)
		local catalog = NetClient.LastCatalog
		view:SetWorlds(PlayLogic.worlds(snap))
		view:SetSelected(PlayLogic.WORLD.Id)
		view:SetMilestones(PlayLogic.milestones(catalog, NetClient.LastMeta, pending))
		view:SetRepeat(PlayLogic.repeatTiles(catalog))
		local tutorial = NetClient.LastMeta and NetClient.LastMeta.Tutorial
		local blocked = tutorial and tutorial.Stage == "Roll"
		view:SetStartState(
			if blocked or (snap and snap.CanSolo == false) then "Disabled" else PlayLogic.startState(snap, busy)
		)
		view:SetCoopState(
			if busy
					or blocked
					or not snap
					or not snap.CanCoop
				then "Disabled"
				elseif snap.CoopReady then "Waiting"
				else "Ready"
		)
		local rating = (snap and snap.Rating) or (NetClient.LastMeta and NetClient.LastMeta.Rating)
		view:SetDuel(RatingLogic.queueButton(snap, busy, blocked == true, workspace:GetServerTimeNow()), rating)
	end

	view:OnSelect(function(id)
		view:SetSelected(id)
	end)
	view:OnLocked(function()
		deps.toast("Coming soon!")
	end)
	view:OnDuelBlocked(function(note)
		deps.toast(note)
	end)
	view:OnClaim(function(row)
		local id = PlayLogic.claimTarget(row, pending)
		if not id then
			return
		end
		pending[id] = true -- set before the yield: a double tap sends once
		render()
		task.spawn(function()
			local ok = NetClient.Request("ClaimQuest", id) -- a rejection toast comes from Lobby; the Meta push shows the claim
			if not ok then
				pending[id] = nil
			end
			if shell:IsOpen() then
				render()
			end
		end)
	end)
	view:OnStart(function()
		if busy then
			return
		end
		busy = true
		render()
		task.spawn(function()
			local ok = NetClient.Request("Start") -- a rejection toast comes from Lobby
			busy = false
			if ok then
				shell:Close() -- the match is starting
			elseif shell:IsOpen() then
				render()
			end
		end)
	end)
	view:OnCoop(function(ready)
		if busy then
			return
		end
		busy = true
		render()
		task.spawn(function()
			local ok = NetClient.Request("CoopReady", ready)
			busy = false
			if shell:IsOpen() then
				if ok and ready then
					deps.toast("Ready for co-op. Waiting for your partner.")
				end
				render()
			end
		end)
	end)
	view:OnDuel(function(on)
		if busy then
			return
		end
		busy = true
		render()
		task.spawn(function()
			NetClient.Request("QueueDuel", on) -- a rejection toast comes from Lobby
			busy = false
			if shell:IsOpen() then
				render()
			end
		end)
	end)
	-- Live search timer: 1 Hz, rewrites the button text only (the view is not rebuilt).
	task.spawn(function()
		while alive do
			task.wait(1)
			local snap = NetClient.Last
			if alive and shell:IsOpen() and snap and snap.QueueState == "Searching" then
				view:SetDuelLabel(RatingLogic.queueButton(snap, false, false, workspace:GetServerTimeNow()).Label)
			end
		end
	end)
	table.insert(
		conns,
		NetClient.State:Connect(function(snap)
			if not shell:IsOpen() then
				return
			end
			if snap.Phase ~= "Lobby" and snap.Phase ~= "Ended" then
				shell:Close()
			else
				local key = viewKey(snap)
				if key ~= shown then
					render()
				end
			end
		end)
	)

	table.insert(
		conns,
		NetClient.Meta:Connect(function()
			table.clear(pending)
			if shell:IsOpen() then
				render()
			end
		end)
	)
	table.insert(
		conns,
		NetClient.Catalog:Connect(function()
			if shell:IsOpen() then
				render()
			end
		end)
	)

	shell:OnClose(function()
		ContextActionService:UnbindAction(ACTION)
		view:SetScroll(0)
		hud:SetBagMode(false)
	end)
	table.insert(
		conns,
		GuiService.MenuOpened:Connect(function()
			shell:Close()
		end)
	)

	self.Shell, self.View, self._conns = shell, view, conns
	self._kill = function()
		alive = false
	end
	self._open = function()
		if shell:IsOpen() then
			return
		end
		render()
		shell:Open()
		hud:SetBagMode(true, "Play")
		ContextActionService:BindActionAtPriority(ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				shell:Close()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
	end
	return self
end

function Play:Open()
	self._open()
end

function Play:Close()
	self.Shell:Close()
end

function Play:Toggle()
	if self.Shell:IsOpen() then
		self.Shell:Close()
	else
		self._open()
	end
end

function Play:IsOpen(): boolean
	return self.Shell:IsOpen()
end

function Play:Destroy()
	self._kill()
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)
	if self.Shell:IsOpen() then
		self.Shell:Close() -- unbinds ButtonB and restores the HUD
	end
	self.View:Destroy()
	self.Shell:Destroy()
end

return Play
