-- Roll menu controller: one Shell (banner, close, STANDARD / EVENT tabs + rotation timer) hosting the Roll View.
-- Roll.new(parent, { hud = LobbyHud, toast = (string) -> () }) -> :Open() :Close() :Toggle() :IsOpen() :Destroy()
-- Static render from RollLogic + the client-only SampleData (Studio shows the full reference). Display only: the roll buttons
-- and (i) just toast; nothing is rolled, spent or sent. The server has no roll feature or Gems balance yet.

local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local NetClient = require(script.Parent.Parent.NetClient)
local Draw = require(script.Parent.Parent.QuestLog.Draw)
local PlaySprites = require(script.Parent.Parent.Play.PlaySprites)
local QuestLogic = require(script.Parent.Parent.QuestLog.QuestLogic)
local RollLogic = require(script.Parent.RollLogic)
local SampleData = require(script.Parent.SampleData)
local Shell = require(script.Parent.Parent.Bag.Shell)
local RollSprites = require(script.Parent.RollSprites)
local View = require(script.Parent.View)

local ACTION = "RollClose"
local POOLS = { "Standard", "Event" }
-- Roll_BannerDie (gold die + pink orbit ring + sparkles) over the scroll top as in the reference: ink 93 x 44 design px on the
-- title axis, its top 33 px above the scroll ink top (on-screen at every size) and its bottom above the ROLL cap. Box = scroll-ink fractions.
local SCROLL_H = 488.5 * PlaySprites.ScrollBase.Ink.Height / PlaySprites.ScrollBase.Ink.Width -- design px
local ICON_BOX = { 0.4, -33 / SCROLL_H, 0.19, 44 / SCROLL_H }
local TIMER_W, SEP_W = 223, 30 -- the Quest Log pill width (full tier)
local PRESS_COOLDOWN = 0.5 -- UX throttle only

local Roll = {}
Roll.__index = Roll

function Roll.new(parent, deps)
	local self = setmetatable({}, Roll)
	local hud = deps.hud
	local conns = {}
	local shell = Shell.new(parent, {
		fit = function()
			return hud:GetBagInsets()
		end,
		name = "Roll",
		free = true,
		tabW = 278.3, -- the Bag's mean tab width: two tabs keep its height, sprites and text role
		tabReserve = SEP_W + TIMER_W + 16, -- (+ the two layout gaps) phones: the tabs shrink to leave this much of the row for the divider and timer
		banner = {
			text = "ROLL",
			textX = 0.5,
			textW = 0.45,
			emblems = { { sprite = RollSprites.BannerDie, box = ICON_BOX } },
		},
	})
	shell:SetTabs({ { Id = "Standard", Label = "STANDARD" }, { Id = "Event", Label = "EVENT" } })
	-- rotation timer after the tabs: white divider, then the Quest Log's timer pill
	local bar = shell.TabBar
	local sep = Draw.img(
		bar,
		{ Name = "Sep", LayoutOrder = 5, Size = UDim2.fromOffset(SEP_W, 40), ZIndex = bar.ZIndex + 1 },
		"Frame"
	)
	local divider = Draw.img(sep, {
		Name = "Divider",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4, 31),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, "Frame")
	divider.BackgroundTransparency = 0 -- Draw.img makes frames clear
	local timer = Draw.timerPill(bar, 0, 0, TIMER_W, bar.ZIndex + 1)
	timer.Group.LayoutOrder = 10
	local view = View.new(shell.Slots.Content)

	local function rotationEnd()
		return SampleData.get(RunService:IsStudio()).RotationEnd -- nil live: no countdown
	end

	local function refreshTimer()
		local rotation = rotationEnd()
		if rotation then
			local now = workspace:GetServerTimeNow()
			timer:Set("Rotates in:", QuestLogic.resetText(rotation(now) - now))
		end
	end

	local function setPool(i)
		local standard = i == 1
		view:SetPool(POOLS[i])
		-- the divider + timer keep their slot in the tab row (the tabs must not move); only their contents hide
		local on = standard and rotationEnd() ~= nil
		divider.Visible = on
		for _, c in timer.Group:GetChildren() do
			if c:IsA("GuiObject") then
				c.Visible = on
			end
		end
	end

	local shown -- the State fields the last render drew
	local function gemsNow()
		local snap = NetClient.Last
		local gems = snap and snap.Gems -- no such field yet; the sample balance stands in
		return if type(gems) == "number" then gems else SampleData.get(RunService:IsStudio()).Gems
	end

	local function render()
		local sample = SampleData.get(RunService:IsStudio())
		local gems = gemsNow()
		shown = tostring(gems)
		refreshTimer()
		view:SetFeatured(sample.Featured)
		view:SetOdds(RollLogic.oddsRows(sample.Odds))
		view:SetPity(sample.Pity)
		local buttons = {}
		for i, count in { 1, 10 } do
			local price = sample.Prices[count]
			buttons[i] = { Count = count, Price = price, Enabled = RollLogic.canAfford(gems, price) }
		end
		view:SetButtons(buttons)
	end

	local cooling = false
	view:OnRoll(function()
		if cooling then
			return
		end
		cooling = true
		task.delay(PRESS_COOLDOWN, function()
			cooling = false
		end)
		deps.toast("Roll: coming soon")
	end)
	view:OnInfo(function()
		deps.toast("Odds and pity are previews until rolls launch")
	end)
	shell:OnTab(setPool)
	shell:SetTab(1)

	local preloaded, timerToken = false, 0
	table.insert(
		conns,
		NetClient.State:Connect(function(snap)
			if not shell:IsOpen() then
				return
			end
			if snap.Phase ~= "Lobby" and snap.Phase ~= "Ended" then
				shell:Close()
			elseif tostring(gemsNow()) ~= shown then -- State ticks often; rebuild only on a visible change
				render()
			end
		end)
	)
	shell:OnClose(function()
		ContextActionService:UnbindAction(ACTION)
		timerToken += 1
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
		if not preloaded then
			preloaded = true
			task.spawn(pcall, ContentProvider.PreloadAsync, ContentProvider, { shell.Bag }) -- stream the art so the first frame is not blank
		end
		render()
		shell:Open()
		hud:SetBagMode(true, "Roll")
		timerToken += 1
		local token = timerToken
		task.spawn(function()
			while token == timerToken do
				task.wait(1)
				if token == timerToken and shell:GetTab() == 1 then
					refreshTimer()
				end
			end
		end)
		ContextActionService:BindActionAtPriority(ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				shell:Close()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
	end
	return self
end

function Roll:Open()
	self._open()
end

function Roll:Close()
	self.Shell:Close()
end

function Roll:Toggle()
	if self.Shell:IsOpen() then
		self.Shell:Close()
	else
		self._open()
	end
end

function Roll:IsOpen(): boolean
	return self.Shell:IsOpen()
end

function Roll:Destroy()
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

return Roll
