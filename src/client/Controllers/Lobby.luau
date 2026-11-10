-- Lobby (placeholder UI): menu + one panel at a time, shown in Lobby / Ended only.
-- Reads NetClient.Last / LastMeta and calls NetClient.Request; no game logic here.
--
-- Placeholder art that needs generated art later (ART_PIPELINE): menu buttons, panel frames,
-- world / mode cards, die icons (colour squares now), rarity badges, results banner, toast frame.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local NetClient = require(script.Parent.NetClient)
local UiKit = require(script.Parent.UiKit)
local Display = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Display"))

local make, panel, label, button = UiKit.make, UiKit.panel, UiKit.label, UiKit.button
local NAVY, NAVY_LIGHT, WHITE, ORANGE, GREEN, GREY =
	UiKit.NAVY, UiKit.NAVY_LIGHT, UiKit.WHITE, UiKit.ORANGE, UiKit.GREEN, UiKit.GREY
local PALE = Color3.fromRGB(200, 200, 230)
local GOLD = Color3.fromRGB(255, 215, 90)

local MENU_WIDTH = 180
local ROW = 48 -- touch row / button height in px (>= 44)
local TOAST_NAMES = { Start = true, EquipDeck = true, ClaimQuest = true }
local TOASTS = {
	WrongPhase = "Not available right now",
	BadDeck = "Your deck is invalid. Fix it in Deck.",
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
local RESULT_TITLES = { Won = "Victory!", Lost = "Defeat", Aborted = "Run Ended", Error = "Something went wrong" }
local PANELS = { "Play", "Deck", "Collection", "Quests", "Profile" }
local SOON = { "Shop", "Chests", "Craft", "Leaderboards", "Settings" }

local Lobby = {}

local connections = {}
local gui, ui
local toastToken = 0
local openPanel = "Play"
local draft = {} -- unsaved deck edit (client-only UI state)
local selectedSlot = 1
local dismissed = false
local questTimers = {} -- { label, base, resetAt }

local function toast(text: string)
	toastToken += 1
	local token = toastToken
	ui.Toast.Text = text
	ui.ToastFrame.Visible = true
	task.delay(2.5, function()
		if token == toastToken then
			ui.ToastFrame.Visible = false
		end
	end)
end

local function setEnabled(btn, enabled: boolean, color: Color3)
	btn.Active = enabled
	btn.BackgroundColor3 = enabled and color or GREY
	btn.TextTransparency = enabled and 0 or 0.35
end

-- Intent call on its own thread; returns nothing, surfaces failures via Rejected -> toast.
local function send(name: string, onOk: (() -> ())?, ...)
	local args = table.pack(...)
	task.spawn(function()
		local ok = NetClient.Request(name, table.unpack(args, 1, args.n))
		if ok and onOk then
			onOk()
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
	return panel({
		Size = UDim2.new(1, -8, 0, height or ROW),
		LayoutOrder = order,
		BackgroundColor3 = NAVY_LIGHT,
	}, body)
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

-- A panel with a header (title + Close) and a scrolling body.
local function newPanel(name: string)
	local frame = panel({
		Name = name,
		Position = UDim2.fromOffset(MENU_WIDTH + 12, 0),
		Size = UDim2.new(1, -(MENU_WIDTH + 12), 1, 0),
		Visible = false,
	}, ui.Root)
	make("UISizeConstraint", { MaxSize = Vector2.new(720, math.huge) }, frame)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
	}, frame)
	label({ Text = name, Size = UDim2.new(1, -110, 0, ROW), TextXAlignment = Enum.TextXAlignment.Left }, frame, 32)
	local close = button(
		{
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(100, ROW),
			Text = "Close",
		},
		frame,
		PALE,
		function()
			openPanel = nil
			for _, p in ui.Panels do
				p.Frame.Visible = false
			end
		end
	)
	close.Name = "Close"
	local body = make("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, ROW + 8),
		Size = UDim2.new(1, 0, 1, -(ROW + 8)),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, frame)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, body)
	ui.Panels[name] = { Frame = frame, Body = body }
	return body
end

local function showPanel(name: string?)
	openPanel = name
	for key, p in ui.Panels do
		p.Frame.Visible = key == name
	end
end

local function deckName(id: string): string
	local die = Display.Dice[id]
	return die and die.Name or id
end

local function resetDraft()
	local meta = NetClient.LastMeta
	draft = meta and table.clone(meta.Deck) or {}
end

local function renderPlay(snap)
	local body = ui.Panels.Play.Body
	clear(body)
	local card = row(body, 1, 110)
	text(card, "World 1 \u{2014} Verdant Trial (10 waves)", UDim2.new(1, -16, 0, 40), UDim2.fromOffset(8, 6), 26)
	local canStart = snap ~= nil and (snap.Phase == "Lobby" or snap.Phase == "Ended")
	local start = button(
		{
			Position = UDim2.new(0, 8, 1, -54),
			Size = UDim2.fromOffset(140, ROW),
			Text = "Start",
		},
		card,
		GREEN,
		function()
			if canStart then -- Active=false does not stop Activated
				send("Start")
			end
		end
	)
	setEnabled(start, canStart, GREEN)
	local locked = row(body, 2, 70)
	locked.BackgroundColor3 = GREY
	text(locked, "Infinite \u{2014} Coming soon", UDim2.new(1, -16, 1, -8), UDim2.fromOffset(8, 4), 26, PALE)
end

local function renderDeck()
	local body = ui.Panels.Deck.Body
	clear(body)
	local meta = NetClient.LastMeta
	if not meta then
		return
	end
	local slots = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 64), LayoutOrder = 1 }, body)
	make("UIGridLayout", {
		CellSize = UDim2.new(0.2, -6, 1, 0),
		CellPadding = UDim2.fromOffset(6, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, slots)
	for i = 1, 5 do
		button(
			{
				Text = draft[i] and deckName(draft[i]) or "Empty",
				LayoutOrder = i,
			},
			slots,
			i == selectedSlot and ORANGE or PALE,
			function()
				selectedSlot = i
				renderDeck()
			end
		)
	end
	-- Save + hint share one row so a 375 px phone still shows the owned dice below.
	local saveRow =
		make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, ROW), LayoutOrder = 2 }, body)
	local save = button({ Size = UDim2.fromOffset(140, ROW), Text = "Save Deck" }, saveRow, GREEN, function()
		local seen, count = {}, 0
		for i = 1, 5 do
			local id = draft[i]
			if id and not seen[id] then
				seen[id] = true
				count += 1
			end
		end
		if count ~= 5 or #draft ~= 5 then
			toast("Pick 5 different dice")
			return
		end
		send("EquipDeck", function()
			toast("Deck saved")
		end, table.clone(draft))
	end)
	save.Name = "Save"
	label({
		Text = "Tap a die to place it in the highlighted slot",
		Position = UDim2.fromOffset(148, 0),
		Size = UDim2.new(1, -148, 1, 0),
	}, saveRow, 20)
	for i, die in meta.Dice do
		local slot = table.find(draft, die.Id)
		local suffix = slot and ("  (slot " .. slot .. ")") or ""
		button(
			{
				Size = UDim2.new(1, -8, 0, ROW),
				Text = ("%s  Lv %d%s"):format(deckName(die.Id), die.Level, suffix),
				LayoutOrder = 10 + i,
			},
			body,
			slot and ORANGE or PALE,
			function()
				local other = table.find(draft, die.Id)
				if other then
					draft[other], draft[selectedSlot] = draft[selectedSlot], draft[other]
				else
					draft[selectedSlot] = die.Id
				end
				renderDeck()
			end
		)
	end
end

local function renderCollection()
	local body = ui.Panels.Collection.Body
	clear(body)
	local meta = NetClient.LastMeta
	local order = 0
	for _, die in meta and meta.Dice or {} do
		order += 1
		local info = Display.Dice[die.Id]
		local r = row(body, order)
		make("Frame", {
			BackgroundColor3 = info and info.Color or WHITE,
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.new(0, 10, 0.5, -14),
			BorderSizePixel = 0,
		}, r)
		text(
			r,
			("%s  %s  Lv %d  Copies %d"):format(deckName(die.Id), info and info.Rarity or "", die.Level, die.Copies),
			UDim2.new(1, -56, 1, -8),
			UDim2.fromOffset(46, 4),
			22
		)
	end
	for _, die in Display.Locked do
		order += 1
		local r = row(body, order)
		r.BackgroundColor3 = GREY
		text(
			r,
			("%s  %s \u{2014} Not available yet"):format(die.Name, die.Rarity),
			UDim2.new(1, -16, 1, -8),
			UDim2.fromOffset(8, 4),
			22,
			PALE
		)
	end
end

local function formatReset(resetAt: number): string
	local left = math.max(0, math.floor(resetAt - workspace:GetServerTimeNow()))
	return ("Resets in %02d:%02d"):format(left // 3600, (left % 3600) // 60)
end

local function renderQuests()
	local body = ui.Panels.Quests.Body
	clear(body)
	table.clear(questTimers)
	local meta = NetClient.LastMeta
	if not meta then
		return
	end
	for i, quest in meta.Quests do
		local r = row(body, i, 72)
		text(r, quest.Name, UDim2.new(0.5, -8, 0, 28), UDim2.fromOffset(8, 6), 22)
		local desc = text(r, quest.Desc, UDim2.new(0.5, -8, 0, 28), UDim2.fromOffset(8, 38), 18, PALE)
		if quest.Daily then
			table.insert(questTimers, { Label = desc, Base = quest.Desc, ResetAt = meta.DailyResetAt })
			desc.Text = quest.Desc .. " \u{00B7} " .. formatReset(meta.DailyResetAt)
		end
		label({
			Text = ("%d/%d"):format(quest.Progress, quest.Goal),
			Size = UDim2.new(0.16, 0, 0, 28),
			Position = UDim2.new(0.5, 0, 0, 6),
		}, r, 22)
		text(r, ("+%d Gold"):format(quest.Gold), UDim2.new(0.18, 0, 0, 28), UDim2.new(0.5, 0, 0, 38), 18, GOLD)
		local canClaim = quest.Progress >= quest.Goal and not quest.Claimed
		if quest.Claimed then
			label({
				Text = "Claimed",
				Size = UDim2.new(0.3, -8, 0, ROW),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				TextColor3 = GREEN,
			}, r, 22)
		else
			local claim = button(
				{
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -8, 0.5, 0),
					Size = UDim2.new(0.3, -8, 0, ROW),
					Text = "Claim",
				},
				r,
				ORANGE,
				function()
					if canClaim then
						send("ClaimQuest", nil, quest.Id)
					end
				end
			)
			setEnabled(claim, canClaim, ORANGE)
			make("UISizeConstraint", { MinSize = Vector2.new(84, ROW) }, claim)
		end
	end
end

local function renderProfile(snap)
	local body = ui.Panels.Profile.Body
	clear(body)
	snap = snap or {}
	local lines = {
		"Gold: " .. tostring(snap.Gold or 0),
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
		ui.ResultReward.Text = snap.RewardGold and ("+" .. snap.RewardGold .. " Gold") or ""
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
		ui.ResultBackdrop.Visible = false
		return
	end
	renderPlay(snap)
	renderProfile(snap)
	renderResult(snap)
end

local function renderMeta()
	resetDraft()
	renderDeck()
	renderCollection()
	renderQuests()
end

local function tick()
	if not ui.Root.Visible then
		return
	end
	for _, timer in questTimers do
		timer.Label.Text = timer.Base .. " \u{00B7} " .. formatReset(timer.ResetAt)
	end
end

local function build()
	gui = make("ScreenGui", {
		Name = "Lobby",
		ResetOnSpawn = false,
		DisplayOrder = 6,
		-- The menu sits top-left, where Roblox's own menu/chat buttons live: stay below them.
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	})
	ui = { Panels = {} }
	ui.Root = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false }, gui)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
	}, ui.Root)

	-- Left menu column (scrolls when the screen is short).
	local menu = make("ScrollingFrame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, MENU_WIDTH, 1, 0),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, ui.Root)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, menu)
	for i, name in PANELS do
		button({ Size = UDim2.new(1, -8, 0, ROW), Text = name, LayoutOrder = i }, menu, ORANGE, function()
			showPanel(name)
		end)
	end
	for i, name in SOON do
		local soon = panel({
			Size = UDim2.new(1, -8, 0, ROW),
			LayoutOrder = 10 + i,
			BackgroundColor3 = GREY,
			Active = false,
		}, menu)
		label({ Text = name .. "\nComing soon", Size = UDim2.fromScale(1, 1), TextColor3 = PALE }, soon, 20)
	end

	for _, name in PANELS do
		newPanel(name)
	end

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
	local card = panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.8),
		ZIndex = 21,
	}, ui.ResultBackdrop)
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

	ui.ToastFrame = panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(0.5, 0, 0, 40),
		Visible = false,
		ZIndex = 30,
	}, gui)
	make("UISizeConstraint", { MinSize = Vector2.new(220, 40), MaxSize = Vector2.new(460, 44) }, ui.ToastFrame)
	ui.Toast = label({ Size = UDim2.fromScale(1, 1), ZIndex = 31 }, ui.ToastFrame, 22)
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
	table.insert(connections, RunService.Heartbeat:Connect(tick))

	renderMeta()
	renderState(NetClient.Last or { Phase = "Loading" })
end

function Lobby.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if gui then
		gui:Destroy()
	end
end

return Lobby
