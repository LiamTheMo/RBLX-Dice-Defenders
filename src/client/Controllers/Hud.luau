-- Match HUD: display only. All state comes from NetClient snapshots; the server decides everything.
--
-- Placeholder art that needs generated art later (ART_PIPELINE):
--   * top bar panel + stat cells (9-slice frame), heart / energy / gold / wave icons (currently text glyphs)
--   * Summon button (chunky illustrated button, normal/pressed/disabled)
--   * boss banner (Thorn Warden portrait/frame), toast frame, full-screen message backdrop
-- Layout: HUD lives on the top edge and bottom corners; the centre ~60% stays clear for the 3D board.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local NetClient = require(script.Parent.NetClient)
local UiKit = require(script.Parent.UiKit)
local Display = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Display"))

local make, panel, label, button = UiKit.make, UiKit.panel, UiKit.label, UiKit.button
local NAVY, ORANGE, GREY = UiKit.NAVY, UiKit.ORANGE, UiKit.GREY

local TOASTS = {
	NoEnergy = "Not enough Energy",
	BoardFull = "Board is full",
	IllegalMerge = "Those dice can't merge",
}
local MESSAGES = {
	Loading = "Loading profile\u{2026}",
	Failed = "Couldn't load your save. Rejoin to try again.",
	NotOwner = "This server is in use. Join another server.",
}

local Hud = {}

local connections = {}
local gui, ui
local toastToken = 0

local function request(name: string)
	task.spawn(NetClient.Request, name)
end

local function showToast(text: string)
	toastToken += 1
	local token = toastToken
	ui.Toast.Text = text
	ui.ToastFrame.Visible = true
	task.delay(2, function()
		if token == toastToken then
			ui.ToastFrame.Visible = false
		end
	end)
end

local function build()
	gui = make("ScreenGui", {
		Name = "Hud",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		IgnoreGuiInset = true, -- deliberate: safe-area handled by DeviceSafeInsets; top bar is centred, clear of core buttons
	})
	ui = {}

	-- Top column: stat bar, then wave / boss countdown lines.
	local top = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromScale(0.62, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, gui)
	make("UISizeConstraint", { MinSize = Vector2.new(360, 0), MaxSize = Vector2.new(720, math.huge) }, top)
	make("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, top)

	local bar = panel({ Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 1 }, top)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder }, bar)
	for i, name in { "Wave", "Lives", "Energy", "Gold" } do
		ui[name] = label({ Size = UDim2.fromScale(0.25, 1), LayoutOrder = i, Name = name }, bar, 26)
	end
	ui.Lives.TextColor3 = Color3.fromRGB(255, 120, 130)
	ui.Energy.TextColor3 = Color3.fromRGB(120, 220, 255)
	ui.Gold.TextColor3 = Color3.fromRGB(255, 215, 90)

	ui.NextWave = label({ Size = UDim2.new(0.6, 0, 0, 24), LayoutOrder = 2, Visible = false }, top, 22)
	ui.Boss = label({
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 3,
		Visible = false,
		TextColor3 = Color3.fromRGB(255, 150, 120),
	}, top, 24)

	-- Bottom-right thumb zone.
	ui.Summon = button(
		{
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -12, 1, -12),
			Size = UDim2.fromScale(0.2, 0.2),
			Text = "Summon",
		},
		gui,
		ORANGE,
		function()
			request("Summon")
		end
	)
	make("UISizeConstraint", { MinSize = Vector2.new(130, 56), MaxSize = Vector2.new(240, 90) }, ui.Summon)

	-- Bottom centre: toast above the hint.
	ui.ToastFrame = panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -56),
		Size = UDim2.new(0.34, 0, 0, 34),
		Visible = false,
		ZIndex = 3,
	}, gui)
	make("UISizeConstraint", { MinSize = Vector2.new(200, 34), MaxSize = Vector2.new(420, 44) }, ui.ToastFrame)
	ui.Toast = label({ Size = UDim2.fromScale(1, 1), ZIndex = 4 }, ui.ToastFrame, 22)

	ui.Hint = panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(0.34, 0, 0, 30),
		Visible = false,
	}, gui)
	make("UISizeConstraint", { MinSize = Vector2.new(260, 30), MaxSize = Vector2.new(520, 36) }, ui.Hint)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, ui.Hint)
	label({ Size = UDim2.fromScale(1, 1), Text = "Tap a die, then a matching die to merge" }, ui.Hint, 20)

	-- Full-screen message (Loading / Failed / NotOwner); swallows input behind it.
	ui.Message = make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = NAVY,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 10,
	}, gui)
	ui.MessageText = label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.2),
		ZIndex = 11,
	}, ui.Message, 40)
end

local function updateCountdowns()
	local snap = NetClient.Last
	if not snap then
		return
	end
	local now = workspace:GetServerTimeNow()
	local nextIn = snap.NextWaveAt and snap.NextWaveAt - now
	local bossIn = snap.BossAt and snap.BossAt - now
	ui.NextWave.Visible = snap.Phase == "Playing" and nextIn ~= nil and nextIn > 0
	if ui.NextWave.Visible then
		ui.NextWave.Text = ("Next wave in %ds"):format(math.ceil(nextIn))
	end
	ui.Boss.Visible = snap.Phase == "Playing" and bossIn ~= nil and bossIn > 0
	if ui.Boss.Visible then
		ui.Boss.Text = ("%s approaches \u{2014} %ds"):format(Display.Enemies.Boss.Name, math.ceil(bossIn))
	end
end

local function render(snap)
	local phase = snap.Phase
	local message = MESSAGES[phase]
	ui.Message.Visible = message ~= nil
	ui.MessageText.Text = message or ""

	local playing = phase == "Playing"
	ui.Wave.Text = ("Wave %d/10"):format(snap.Wave or 0)
	ui.Lives.Text = "\u{2665} " .. tostring(snap.Lives or 0)
	ui.Energy.Text = "Energy " .. tostring(snap.Energy or 0)
	ui.Gold.Text = "Gold " .. tostring(snap.Gold or 0)
	ui.Wave.Parent.Visible = playing

	local cost = snap.SummonCost or 0
	local canSummon = playing and (snap.Energy or 0) >= cost
	ui.Summon.Visible = playing
	ui.Summon.Text = canSummon and ("Summon\n" .. cost .. " Energy")
		or (playing and ("Summon\nNeed " .. cost .. " Energy") or "Summon")
	ui.Summon.BackgroundColor3 = canSummon and ORANGE or GREY
	ui.Summon.TextTransparency = canSummon and 0 or 0.35
	ui.Summon.BackgroundTransparency = canSummon and 0 or 0.3

	ui.Hint.Visible = playing and (snap.Wave or 0) <= 2

	updateCountdowns()
end

function Hud.Start()
	build()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	table.insert(
		connections,
		NetClient.State:Connect(function(snap)
			render(snap)
		end)
	)
	table.insert(
		connections,
		NetClient.Rejected:Connect(function(_, code)
			if TOASTS[code] then
				showToast(TOASTS[code])
			end
		end)
	)
	table.insert(connections, RunService.Heartbeat:Connect(updateCountdowns))

	render(NetClient.Last or { Phase = "Loading" })
end

function Hud.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if gui then
		gui:Destroy()
	end
end

return Hud
