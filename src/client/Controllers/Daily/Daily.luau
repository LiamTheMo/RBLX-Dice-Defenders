-- Daily Rewards menu controller: one Shell (banner, close) hosting the Daily View.
-- Daily.new(parent, { hud = LobbyHud, toast = (string) -> () }) -> :Open() :Close() :Toggle() :IsOpen() :Destroy()
-- Renders Catalog.Daily + Meta.Login (a loading card until both arrived); CLAIM sends ClaimQuest("LOGIN") and the server's next Meta
-- shows the result (a rejection is toasted by Lobby's NetClient.Rejected handler). The client never opens a day itself.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local DailyLogic = require(script.Parent.DailyLogic)
local NetClient = require(script.Parent.Parent.NetClient)
local ShopLogic = require(script.Parent.Parent.Shop.ShopLogic)
local QuestSprites = require(script.Parent.Parent.QuestLog.QuestSprites)
local Shell = require(script.Parent.Parent.Bag.Shell)
local Sprites = require(script.Parent.Parent.Sprites)
local View = require(script.Parent.View)

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

	local deadline: number? -- Login.NextClaimAt while today is claimed
	local function refreshTimer()
		if deadline then
			view:SetTimer("Next claim in:", DailyLogic.timerText(deadline - workspace:GetServerTimeNow()))
		end
	end
	local function render()
		local catalog, meta = NetClient.LastCatalog, NetClient.LastMeta
		local days = catalog and catalog.Daily and catalog.Daily.Days
		local login = meta and meta.Login
		if type(days) ~= "table" or type(login) ~= "table" then
			view:SetSoon(true)
			return
		end
		view:SetSoon(false)
		view:SetDays(DailyLogic.days(days))
		view:SetLogin(login)
		view:SetClaimState(DailyLogic.claimState(login))
		deadline = DailyLogic.timerTarget(login)
		if deadline then
			refreshTimer()
		else
			view:SetTimer(nil)
		end
	end

	local flight = ShopLogic.guard()
	local metaSeen, awaitMeta = 0, false -- a successful claim holds the button until a Meta newer than the press
	view:OnAction(function()
		if not flight.begin() then
			return
		end
		local seen = metaSeen
		task.spawn(function()
			if NetClient.Request("ClaimQuest", "LOGIN") then
				if metaSeen ~= seen then
					flight.finish()
				else
					awaitMeta = true
				end
			else
				task.delay(PRESS_COOLDOWN, flight.finish)
			end
		end)
	end)
	local function onData()
		if shell:IsOpen() then
			render()
		end
	end
	table.insert(conns, NetClient.Catalog:Connect(onData))
	table.insert(
		conns,
		NetClient.Meta:Connect(function()
			metaSeen += 1
			if awaitMeta then
				awaitMeta = false
				flight.finish()
			end
			onData()
		end)
	)

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

	self.Shell, self.View, self._conns = shell, view, conns
	self._open = function()
		if shell:IsOpen() then
			return
		end
		render()
		shell:Open()
		hud:SetBagMode(true, "Daily")
		timerToken += 1
		local token = timerToken
		task.spawn(function()
			while token == timerToken do
				task.wait(1)
				if token == timerToken then
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
