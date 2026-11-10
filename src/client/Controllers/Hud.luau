-- Match HUD: display only. All state comes from NetClient snapshots; the server decides everything.
--
-- Placeholder art that needs generated art later (ART_PIPELINE):
--   * top bar panel + stat cells (9-slice frame), heart / energy / gold / wave icons (currently text glyphs)
--   * Summon + Start/Play Again buttons (chunky illustrated button, normal/pressed/disabled)
--   * result panel frame + Won/Lost banner art
--   * boss banner (Thorn Warden portrait/frame), toast frame, full-screen message backdrop
-- Layout: HUD lives on the top edge and bottom corners; the centre ~60% stays clear for the 3D board.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local NetClient = require(script.Parent.NetClient)
local Display = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Display"))

local NAVY = Color3.fromRGB(27, 22, 54)
local NAVY_LIGHT = Color3.fromRGB(52, 44, 96)
local WHITE = Color3.new(1, 1, 1)
local ORANGE = Color3.fromRGB(245, 160, 50)
local GREEN = Color3.fromRGB(90, 205, 125)
local GREY = Color3.fromRGB(110, 106, 140)
local FONT = Enum.Font.FredokaOne

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
local RESULT_TITLES = { Won = "Victory!", Lost = "Defeat", Aborted = "Run Ended", Error = "Something went wrong" }

local Hud = {}

local connections = {}
local gui, ui
local toastToken = 0

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(class)
	for key, value in props do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function panel(props: { [string]: any }, parent: Instance): any
	props.BackgroundColor3 = props.BackgroundColor3 or NAVY
	props.BorderSizePixel = 0
	local frame = make("Frame", props, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, frame)
	make("UIStroke", { Color = NAVY_LIGHT, Thickness = 2 }, frame)
	return frame
end

-- Text that scales with its box but never drops below 14 px.
local function label(props: { [string]: any }, parent: Instance, maxSize: number): any
	props.BackgroundTransparency = 1
	props.Font = FONT
	props.TextColor3 = props.TextColor3 or WHITE
	props.TextScaled = true
	local text = make("TextLabel", props, parent)
	make("UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = maxSize }, text)
	return text
end

local function button(props: { [string]: any }, parent: Instance, color: Color3, onClick: () -> ()): any
	props.BackgroundColor3 = color
	props.BorderSizePixel = 0
	props.AutoButtonColor = false
	props.Font = FONT
	props.TextColor3 = NAVY
	props.TextScaled = true
	local btn = make("TextButton", props, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, btn)
	make("UIStroke", { Color = WHITE, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, btn)
	make("UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = 30 }, btn)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
	}, btn)
	local scale = make("UIScale", { Scale = 1 }, btn)
	local hover = false
	btn.MouseEnter:Connect(function()
		hover = true
		scale.Scale = 1.04
	end)
	btn.MouseLeave:Connect(function()
		hover = false
		scale.Scale = 1
	end)
	btn.MouseButton1Down:Connect(function()
		scale.Scale = 0.94
	end)
	btn.MouseButton1Up:Connect(function()
		scale.Scale = hover and 1.04 or 1
	end)
	btn.Activated:Connect(onClick)
	return btn
end

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

	-- Bottom-right thumb zone: Summon / Start share the slot.
	local function bottomButton(text: string, color: Color3, onClick: () -> ())
		local btn = button({
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -12, 1, -12),
			Size = UDim2.fromScale(0.2, 0.2),
			Text = text,
		}, gui, color, onClick)
		make("UISizeConstraint", { MinSize = Vector2.new(130, 56), MaxSize = Vector2.new(240, 90) }, btn)
		return btn
	end
	ui.Summon = bottomButton("Summon", ORANGE, function()
		request("Summon")
	end)
	ui.Start = bottomButton("Start", GREEN, function()
		request("Start")
	end)

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

	-- Result panel (Ended).
	ui.Result = panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.36, 0.5),
		Visible = false,
		ZIndex = 2,
	}, gui)
	make("UISizeConstraint", { MinSize = Vector2.new(260, 170), MaxSize = Vector2.new(380, 260) }, ui.Result)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
	}, ui.Result)
	make("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0.03, 0),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, ui.Result)
	ui.ResultTitle = label({ Size = UDim2.fromScale(1, 0.28), LayoutOrder = 1, ZIndex = 3 }, ui.Result, 36)
	ui.ResultReward = label({
		Size = UDim2.fromScale(1, 0.2),
		LayoutOrder = 2,
		ZIndex = 3,
		TextColor3 = Color3.fromRGB(255, 215, 90),
	}, ui.Result, 24)
	ui.ResultBest = label({ Size = UDim2.fromScale(1, 0.18), LayoutOrder = 3, ZIndex = 3 }, ui.Result, 22)
	ui.ResultRuns = label({ Size = UDim2.fromScale(1, 0.18), LayoutOrder = 4, ZIndex = 3 }, ui.Result, 22)

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
	local inGame = playing or phase == "Lobby" or phase == "Ended"
	ui.Wave.Text = ("Wave %d/10"):format(snap.Wave or 0)
	ui.Lives.Text = "\u{2665} " .. tostring(snap.Lives or 0)
	ui.Energy.Text = "Energy " .. tostring(snap.Energy or 0)
	ui.Gold.Text = "Gold " .. tostring(snap.Gold or 0)
	ui.Wave.Parent.Visible = inGame

	local cost = snap.SummonCost or 0
	local canSummon = playing and (snap.Energy or 0) >= cost
	ui.Summon.Visible = playing
	ui.Summon.Text = canSummon and ("Summon\n" .. cost .. " Energy")
		or (playing and ("Summon\nNeed " .. cost .. " Energy") or "Summon")
	ui.Summon.BackgroundColor3 = canSummon and ORANGE or GREY
	ui.Summon.TextTransparency = canSummon and 0 or 0.35
	ui.Summon.BackgroundTransparency = canSummon and 0 or 0.3

	ui.Start.Visible = phase == "Lobby" or phase == "Ended"
	ui.Start.Text = phase == "Ended" and "Play Again" or "Start"

	ui.Hint.Visible = playing and (snap.Wave or 0) <= 2

	ui.Result.Visible = phase == "Ended"
	if phase == "Ended" then
		ui.ResultTitle.Text = RESULT_TITLES[snap.Result] or "Run Ended"
		ui.ResultReward.Text = snap.RewardGold and ("+" .. snap.RewardGold .. " Gold") or ""
		ui.ResultReward.Visible = snap.RewardGold ~= nil
		ui.ResultBest.Text = "Best wave: " .. tostring(snap.BestWave or 0)
		ui.ResultRuns.Text = "Runs played: " .. tostring(snap.RunsPlayed or 0)
	end
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
