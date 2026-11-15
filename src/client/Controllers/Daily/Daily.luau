-- Daily Rewards menu controller: one Shell (banner, close) hosting the Daily View.
-- Daily.new(parent, { hud = LobbyHud, toast = (string) -> () }) -> :Open() :Close() :Toggle() :IsOpen() :Destroy()
-- Display only: the client-only SampleData shows in Studio (with a sample countdown); a live server shows "Coming soon". CLAIM just toasts.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local DailyLogic = require(script.Parent.DailyLogic)
local NetClient = require(script.Parent.Parent.NetClient)
local SampleData = require(script.Parent.SampleData)
local ShopLogic = require(script.Parent.Parent.Shop.ShopLogic)
local QuestSprites = require(script.Parent.Parent.QuestLog.QuestSprites)
local Shell = require(script.Parent.Parent.Bag.Shell)
local Sprites = require(script.Parent.Parent.Sprites)
local View = require(script.Parent.View)

-- Studio-only sample data (nil live: the "Coming soon" card).
local DATA = if RunService:IsStudio() then SampleData else nil
local ACTION = "DailyClose"
local PRESS_COOLDOWN = 0.5 -- UX throttle only

-- Banner emblems on the rolled ends (scroll-ink fractions). Their inner edges stay at 0.105 / 0.895, outside the parchment's flat band
-- (0.114-0.890; the title keeps 8 design px off it, so >= 4 real px clear); they grow outward over the rolled ends and upward over the
-- scroll's top edge: 0.215 wide (105 design px, the reference's ~102 / 88 visible ink), 1.014 tall (the calendar's aspect), centred a little above the title's height (0.512).
local BOX_L = { -0.11, -0.087, 0.215, 1.014 }
local BOX_R = { 0.895, -0.087, 0.215, 1.014 }

local Daily = {}
Daily.__index = Daily

function Daily.new(parent, deps)
	local self = setmetatable({}, Daily)
	local hud = deps.hud
	local shell = Shell.new(parent, {
		fit = function()
			return hud:GetBagInsets()
		end,
		name = "Daily",
		free = true,
		banner = {
			text = "DAILY REWARDS",
			noGem = true,
			emblems = {
				{ sprite = QuestSprites.IconCalendar, box = { full = BOX_L, compact = BOX_L } },
				{ sprite = Sprites.Icon.Daily, box = { full = BOX_R, compact = BOX_R } },
			},
		},
	})
	local view = View.new(shell.Slots.Content)
	local conns = {}

	local flight = ShopLogic.guard()
	view:OnAction(function()
		if not flight.begin() then
			return
		end
		task.delay(PRESS_COOLDOWN, flight.finish)
		deps.toast("Daily: coming soon")
	end)
	local deadline: number? -- sample countdown target, fixed on first open
	view:SetClaimState(DailyLogic.claimState(DATA))
	if DATA then
		view:SetDays(DATA.Days)
		view:SetStreak(DATA.Streak, DATA.ClaimedToday)
	else
		view:SetSoon(true)
		view:SetTimer(nil)
	end
	local function refreshTimer()
		if deadline then
			view:SetTimer("Next claim in:", DailyLogic.timerText(deadline - workspace:GetServerTimeNow()))
		end
	end

	table.insert(
		conns,
		NetClient.State:Connect(function(snap)
			if shell:IsOpen() and snap.Phase ~= "Lobby" and snap.Phase ~= "Ended" then
				shell:Close() -- a match started
			end
		end)
	)
	local timerToken = 0
	shell:OnClose(function()
		timerToken += 1
		ContextActionService:UnbindAction(ACTION)
		hud:SetBagMode(false)
	end)
	table.insert(
		conns,
		GuiService.MenuOpened:Connect(function()
			shell:Close()
		end)
	)

	local opened = false
	self.Shell, self.View, self._conns = shell, view, conns
	self._open = function()
		if shell:IsOpen() then
			return
		end
		if not opened then
			opened = true
			if DATA then
				deadline = workspace:GetServerTimeNow() + DATA.NextClaimIn
			end
		end
		refreshTimer()
		shell:Open()
		hud:SetBagMode(true, "Daily")
		timerToken += 1
		local token = timerToken
		if deadline then
			task.spawn(function()
				while token == timerToken do
					task.wait(1)
					if token == timerToken then
						refreshTimer()
					end
				end
			end)
		end
		ContextActionService:BindActionAtPriority(ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				shell:Close()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
	end
	return self
end

function Daily:Open()
	self._open()
end

function Daily:Close()
	self.Shell:Close()
end

function Daily:Toggle()
	if self.Shell:IsOpen() then
		self.Shell:Close()
	else
		self._open()
	end
end

function Daily:IsOpen(): boolean
	return self.Shell:IsOpen()
end

function Daily:Destroy()
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

return Daily
