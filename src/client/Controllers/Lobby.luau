-- Lobby: sprite HUD (LobbyHud) + one placeholder panel at a time, shown in Lobby / Ended only.
-- Reads NetClient.Last / LastMeta; no game logic here.
--
-- Placeholder art that needs generated art later (ART_PIPELINE): panel frames,
-- world / mode cards, die icons (colour squares now), rarity badges, results banner, toast frame.

local Players = game:GetService("Players")

local NetClient = require(script.Parent.NetClient)
local UiKit = require(script.Parent.UiKit)
local LobbyHud = require(script.Parent.LobbyHud)
local Chrome = require(script.Parent.Bag.Chrome)
local Bag = require(script.Parent.Bag.Bag)
local QuestLog = require(script.Parent.QuestLog.QuestLog)
local Play = require(script.Parent.Play.Play)
local Roll = require(script.Parent.Roll.Roll)
local Daily = require(script.Parent.Daily.Daily)
local Shop = require(script.Parent.Shop.Shop)
local Settings = require(script.Parent.Settings.Settings)
local Codes = require(script.Parent.Codes.Codes)

local make, panel, label, button = UiKit.make, UiKit.panel, UiKit.label, UiKit.button
local NAVY, WHITE, GREEN = UiKit.NAVY, UiKit.WHITE, UiKit.GREEN
local GOLD = Color3.fromRGB(255, 215, 90)
-- Panel / toast skin matching the HUD: dark-brown fill, copper outline, white text with a dark outline.
local BROWN = Color3.fromRGB(58, 30, 23)
local COPPER = Color3.fromRGB(224, 135, 90)
local ROW_BROWN = Color3.fromRGB(86, 46, 34)
local ROW_EDGE = Color3.fromRGB(128, 70, 46) -- dark copper row outline
local CREAM = Color3.fromRGB(242, 226, 205)
local TEXT_STROKE = Color3.fromRGB(9, 14, 24)

local ROW = 48 -- touch row / button height in px (>= 44)
local TOAST_NAMES = { Start = true, EquipDeck = true, ClaimQuest = true }
local TOASTS = {
	WrongPhase = "Not available right now",
	BadDeck = "Your deck is invalid. Fix it in your Bag.",
	UnknownDie = "Unknown die",
	NotOwned = "You don't own that die",
	UnknownQuest = "Unknown quest",
	NotComplete = "Quest not complete yet",
	AlreadyClaimed = "Already claimed",
	Overflow = "Can't claim that right now",
	NotLoaded = "Still loading",
	NotOwner = "This server is in use",
	Throttled = "Slow down",
	Network = "Connection problem",
}
local RESULT_TITLES = { Lost = "Defeat", Aborted = "Run Ended", Error = "Something went wrong" }

local Lobby = {}

local connections = {}
local gui, ui
local toastToken = 0
local openPanel = nil
local dismissed = false
local lobbyActive = false

-- Every menu window: HUD name -> ui key. Opening one closes the others.
local MENUS = {
	{ Name = "Bag", Key = "Bag" },
	{ Name = "Quests", Key = "QuestLog" },
	{ Name = "Play", Key = "Play" },
	{ Name = "Roll", Key = "Roll" },
	{ Name = "Shop", Key = "Shop" },
	{ Name = "Daily", Key = "Daily" },
	{ Name = "Settings", Key = "Settings" },
	{ Name = "Codes", Key = "Codes" },
}

local function closeMenus()
	for _, menu in MENUS do
		ui[menu.Key]:Close()
	end
end

local function anyMenuOpen(): boolean
	for _, menu in MENUS do
		if ui[menu.Key]:IsOpen() then
			return true
		end
	end
	return false
end

local function toast(text: string)
	toastToken += 1
	local token = toastToken
	ui.Toast.Text = text
	-- A menu open: sit over the coin row so the banner, X and tabs stay visible.
	if anyMenuOpen() then
		ui.ToastFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		-- Clamped: on phones the coin row is hidden and bottomTopReal is the screen height.
		local row = ui.LobbyHud.Currencies
		local y = if row.Visible
			then row.AbsolutePosition.Y + row.AbsoluteSize.Y / 2
			else math.min(ui.LobbyHud:GetBagInsets().bottomTopReal + 26, UiKit.screenSize(ui.Root).Y - 26)
		ui.ToastFrame.Position = UDim2.new(0.5, 0, 0, y)
	else
		ui.ToastFrame.AnchorPoint = Vector2.new(0.5, 0)
		ui.ToastFrame.Position = UDim2.new(0.5, 0, 0, 10)
	end
	ui.ToastFrame.Visible = true
	task.delay(2.5, function()
		if token == toastToken then
			ui.ToastFrame.Visible = false
		end
	end)
end

local function clear(body)
	for _, child in body:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function row(body, order: number, height: number?)
	local r = panel({
		Size = UDim2.new(1, -8, 0, height or ROW),
		LayoutOrder = order,
		BackgroundColor3 = ROW_BROWN,
	}, body)
	r:FindFirstChildOfClass("UIStroke").Color = ROW_EDGE
	return r
end

local function text(parent, str: string, size: UDim2, pos: UDim2?, maxSize: number, color: Color3?)
	return label({
		Text = str,
		Size = size,
		Position = pos or UDim2.new(),
		TextColor3 = color or WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent, maxSize)
end

local function skin(frame)
	frame.BackgroundColor3 = BROWN
	frame:FindFirstChildOfClass("UIStroke").Color = COPPER
	return frame
end

local function outline(lbl)
	make("UIStroke", { Color = TEXT_STROKE, Thickness = 2, LineJoinMode = Enum.LineJoinMode.Round }, lbl)
end

local function showPanel(name: string?, tab: number?)
	for _, menu in MENUS do -- the menus are their own windows, not placeholder panels: opening one closes the rest
		if menu.Name == name then
			for _, other in MENUS do
				if other ~= menu then
					ui[other.Key]:Close()
				end
			end
			ui[menu.Key]:Toggle(tab)
			return
		end
	end
	closeMenus()
	openPanel = name
	for key, p in ui.Panels do
		p.Frame.Visible = key == name
	end
	ui.Hud.Visible = name == nil
end

-- A panel with a header (title + Close) and a scrolling body.
local function newPanel(name: string)
	local frame = skin(panel({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 1, -24),
		Visible = false,
	}, ui.Root))
	make("UISizeConstraint", { MaxSize = Vector2.new(720, 600) }, frame)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
	}, frame)
	outline(
		label({ Text = name, Size = UDim2.new(1, -110, 0, ROW), TextXAlignment = Enum.TextXAlignment.Left }, frame, 32)
	)
	local close = button(
		{
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(100, ROW),
			Text = "Close",
		},
		frame,
		CREAM,
		function()
			showPanel(nil)
		end
	)
	close.Name = "Close"
	close.BackgroundColor3 = COPPER
	close.TextColor3 = WHITE
	make("UIStroke", { Color = TEXT_STROKE, Thickness = 2, LineJoinMode = Enum.LineJoinMode.Round }, close)
	local body = make("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, ROW + 8),
		Size = UDim2.new(1, 0, 1, -(ROW + 8)),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = COPPER,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, frame)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, body)
	ui.Panels[name] = { Frame = frame, Body = body }
	return body
end

local function renderProfile(snap)
	local body = ui.Panels.Profile.Body
	clear(body)
	snap = snap or {}
	local meta = NetClient.LastMeta or {}
	local lines = {
		"Gold: " .. tostring(snap.Gold or 0),
		"XP: " .. tostring(meta.Xp or 0),
		"Best wave: " .. tostring(snap.BestWave or 0),
		"Runs played: " .. tostring(snap.RunsPlayed or 0),
		"Trial cleared: " .. (snap.TrialCleared and "Yes" or "No"),
	}
	for i, line in lines do
		text(row(body, i), line, UDim2.new(1, -16, 1, -8), UDim2.fromOffset(8, 4), 26)
	end
end

local function renderResult(snap)
	local show = snap.Phase == "Ended" and not dismissed
	ui.ResultBackdrop.Visible = show
	if show then
		ui.ResultTitle.Text = RESULT_TITLES[snap.Result] or "Run Ended"
		ui.ResultWave.Text = "Wave " .. tostring(snap.Wave or 0)
		ui.ResultReward.Text = ("+%d Gold   +%d XP   +%d Gems"):format(
			snap.RewardGold or 0,
			snap.RewardXp or 0,
			snap.RewardGems or 0
		)
		ui.ResultReward.Visible = snap.RewardGold ~= nil
	end
end

local function renderState(snap)
	local phase = snap.Phase
	if phase ~= "Ended" then
		dismissed = false
	end
	local active = phase == "Lobby" or phase == "Ended"
	ui.Root.Visible = active
	if not active then
		if lobbyActive then
			showPanel(nil) -- closes every menu; only on the transition, not every State tick
		end
		lobbyActive = false
		ui.ResultBackdrop.Visible = false
		return
	end
	lobbyActive = true
	renderProfile(snap)
	ui.LobbyHud:SetGold(snap.Gold)
	renderResult(snap)
end

local function renderMeta()
	local meta = NetClient.LastMeta
	ui.LobbyHud:SetDeck(meta and meta.Deck)
	if meta then
		ui.LobbyHud:SetGems(meta.Gems)
		ui.LobbyHud:SetXp(meta.Level, meta.XpInto, meta.XpNeed)
	end
	renderProfile(NetClient.Last)
end

local function build()
	gui = make("ScreenGui", {
		Name = "Lobby",
		ResetOnSpawn = false,
		DisplayOrder = 6,
		-- Roblox's own menu/chat buttons sit in the top corners: stay below them.
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	})
	ui = { Panels = {} }
	ui.Root =
		make("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false }, gui)
	ui.LobbyHud = LobbyHud.build(ui.Root, { open = showPanel, toast = toast })
	ui.Hud = ui.LobbyHud.Hud
	-- Sibling of Hud (so Hud.Visible never hides it); Toast lives on the gui and stays above.
	ui.Bag = Bag.new(ui.Root, { hud = ui.LobbyHud, toast = toast })
	ui.QuestLog = QuestLog.new(ui.Root, { hud = ui.LobbyHud, toast = toast })
	ui.Play = Play.new(ui.Root, { hud = ui.LobbyHud, toast = toast })
	ui.Roll = Roll.new(ui.Root, { hud = ui.LobbyHud, toast = toast })
	ui.Shop = Shop.new(ui.Root, { hud = ui.LobbyHud, toast = toast })
	ui.Daily = Daily.new(ui.Root, { hud = ui.LobbyHud, toast = toast })
	ui.Settings = Settings.new(ui.Root, { hud = ui.LobbyHud, toast = toast })
	ui.Codes = Codes.new(ui.Root, { hud = ui.LobbyHud, toast = toast })

	newPanel("Profile")

	-- Results card (Ended): local dismiss only; backdrop swallows input behind it.
	ui.ResultBackdrop = make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = NAVY,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 20,
	}, ui.Root)
	local card = skin(panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.8),
		ZIndex = 21,
	}, ui.ResultBackdrop))
	make("UISizeConstraint", { MinSize = Vector2.new(280, 240), MaxSize = Vector2.new(400, 300) }, card)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
	}, card)
	make("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, card)
	ui.ResultTitle = label({ Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 1, ZIndex = 22 }, card, 40)
	ui.ResultWave = label({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 2, ZIndex = 22 }, card, 26)
	ui.ResultReward =
		label({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 3, ZIndex = 22, TextColor3 = GOLD }, card, 26)
	outline(ui.ResultTitle)
	outline(ui.ResultWave)
	outline(ui.ResultReward)
	local continue = button(
		{ Size = UDim2.fromOffset(160, ROW), LayoutOrder = 4, ZIndex = 22, Text = "Continue" },
		card,
		GREEN,
		function()
			dismissed = true
			ui.ResultBackdrop.Visible = false
		end
	)
	continue.Name = "Continue"

	-- Top-centre: the bottom of the screen holds the HUD's deck bar.
	ui.ToastFrame = Chrome.panel(gui, {
		Name = "ToastFrame",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(0.5, 0, 0, 44),
		Visible = false,
		ZIndex = 60, -- above the bag banner (Z 30+)
		Radius = 22,
		Rim = 2,
	})
	make("UISizeConstraint", { MinSize = Vector2.new(220, 44), MaxSize = Vector2.new(460, 48) }, ui.ToastFrame)
	ui.Toast = label({ Size = UDim2.fromScale(1, 1), ZIndex = 61 }, ui.ToastFrame, 22)
	outline(ui.Toast)
end

function Lobby.Start()
	build()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	showPanel(openPanel)

	table.insert(connections, NetClient.State:Connect(renderState))
	table.insert(connections, NetClient.Meta:Connect(renderMeta))
	table.insert(
		connections,
		NetClient.Rejected:Connect(function(name, code)
			if TOAST_NAMES[name] then
				toast(TOASTS[code] or tostring(code))
			end
		end)
	)

	renderMeta()
	renderState(NetClient.Last or { Phase = "Loading" })
end

function Lobby.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if ui and ui.Bag then
		ui.Bag:Destroy()
	end
	if ui and ui.QuestLog then
		ui.QuestLog:Destroy()
	end
	if ui and ui.Play then
		ui.Play:Destroy()
	end
	if ui and ui.Roll then
		ui.Roll:Destroy()
	end
	if ui and ui.Shop then
		ui.Shop:Destroy()
	end
	if ui and ui.Daily then
		ui.Daily:Destroy()
	end
	if ui and ui.Settings then
		ui.Settings:Destroy()
	end
	if ui and ui.Codes then
		ui.Codes:Destroy()
	end
	if gui then
		gui:Destroy()
	end
end

return Lobby
