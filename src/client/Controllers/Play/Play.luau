-- Play menu controller: one Shell (banner, close; no tabs) hosting the Play View.
-- Play.new(parent, { hud = LobbyHud, toast = (string) -> () }) -> :Open() :Close() :Toggle() :IsOpen() :Destroy()
-- Renders from PlayLogic with NetClient.Last and the client-only SampleData (Studio shows the full reference) on open and
-- whenever the phase, best wave or clear state changes; START sends the guarded Start request, one at a time.

local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local NetClient = require(script.Parent.Parent.NetClient)
local PlayLogic = require(script.Parent.PlayLogic)
local PlaySprites = require(script.Parent.PlaySprites)
local SampleData = require(script.Parent.SampleData)
local Shell = require(script.Parent.Parent.Bag.Shell)
local Sprites = require(script.Parent.Parent.Sprites)
local View = require(script.Parent.View)

local ACTION = "PlayClose"
local SWORDS = { Image = Sprites.Icon.Play, Size = Vector2.new(256, 239), Ink = Rect.new(6, 6, 250, 233) } -- Icon_Play.png

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
		banner = {
			text = "PLAY",
			textX = 0.5715, -- the ref PLAY centre (+41.5 px of the 587 px scroll) scaled into the 489 px scroll, with >= 5 px to the swords and the right laurel
			textW = 0.5,
			emblems = {
				{ sprite = PlaySprites.LaurelL, box = { 0.1538, 0.157, 0.1061, 0.645 } }, -- 0.83x the ref laurel (A-2 scale), drawn first: behind the swords
				{ sprite = PlaySprites.LaurelR, box = { 0.7374, 0.157, 0.1061, 0.645 } },
				{ sprite = SWORDS, box = { 0.221, -0.077, 0.172, 0.765 } },
			},
		},
	})
	local view = View.new(shell.Slots.Content)

	local preloaded, busy = false, false
	local function preload() -- first open only: stream the art so the first frame is not blank
		if preloaded then
			return
		end
		preloaded = true
		task.spawn(pcall, ContentProvider.PreloadAsync, ContentProvider, { shell.Bag }) -- Bag draws every Play sprite
	end

	local shown -- the State fields the last render drew
	local function render()
		local snap = NetClient.Last
		shown = snap and `{snap.Phase}|{snap.BestWave}|{snap.TrialCleared}`
		local sample = SampleData.get(RunService:IsStudio())
		view:SetWorlds(PlayLogic.worlds(snap, sample))
		view:SetSelected(PlayLogic.WORLD.Id)
		view:SetMilestones(PlayLogic.milestones(snap, sample), PlayLogic.worldClear(snap))
		view:SetRepeat(sample.Tiles, sample.Odds)
		view:SetStartState(PlayLogic.startState(snap, busy))
	end

	view:OnSelect(function(id)
		view:SetSelected(id)
	end)
	view:OnLocked(function()
		deps.toast("Coming soon!")
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
	table.insert(
		conns,
		NetClient.State:Connect(function(snap)
			if not shell:IsOpen() then
				return
			end
			if snap.Phase ~= "Lobby" and snap.Phase ~= "Ended" then
				shell:Close()
			else
				local key = `{snap.Phase}|{snap.BestWave}|{snap.TrialCleared}` -- State ticks often; rebuild only on a visible change
				if key ~= shown then
					render()
				end
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
	self._open = function()
		if shell:IsOpen() then
			return
		end
		preload()
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
