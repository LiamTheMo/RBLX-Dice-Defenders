-- Quest Log detail panel, one template for all three tabs: title, a scrolling body (kind-specific widgets) and, for quests, a pinned CLAIM strip.
-- Detail.new(slot) -> :Show(model|nil) :OnAction(cb(state, model)) :Destroy. Code-drawn (plan D1); the slot is the detail panel's interior.
-- model = { Kind = "Quest" | "Achievement" | "Mastery", Title, Name, Icon (QuestSprites key), Action = { Label, State, Enabled }, Body }
--   Quest Body = { Desc, Progress, Goal, Gold, Gems? }. State = Claim | Claimed | Progress.
--   Achievement Body = { Desc, Progress, Goal, Badge, Rewards = Catalog reward lines }; the button sits in its reward box.
--   Mastery Body = a QuestLogic.masteryRows row; the CLAIM button sits under the description while a milestone is claimable (a real claim action).
-- Design px. Heights are scroll-origin offsets measured on the mockups (origin = 48 px below the panel top). Under 430 px tall the hero art is
-- dropped (every y shifts up by HERO_H) and the body scrolls. Name paths: QuestDetail.Scroll.Body.<Quest|Achievement|Mastery>.*, QuestDetail.ActionRow.

local UiKit = require(script.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Bag.Parts)
local Chrome = require(script.Parent.Parent.Bag.Chrome)
local HudSprites = require(script.Parent.Parent.Sprites)
local Shared = require(script.Parent.Parent.SharedSprites)
local QuestLogic = require(script.Parent.QuestLogic)
local Kit = require(script.Parent.Kit)
local Q = require(script.Parent.QuestSprites)
local Achievements = require(script.Parent.Tabs.Achievements)
local Mastery = require(script.Parent.Tabs.Mastery)

local make = UiKit.make
local V2 = Vector2.new

local TITLE_H = 46 -- title strip (mockup 230..276)
local ACTION_H = 70 -- pinned CLAIM strip (quests only)
local HERO_H = 84 -- the hero art's height; dropped when the panel is short
local HERO_MIN = 430 -- panel height that still shows the hero
local INS = 12 -- body side inset
local BODY_H = { Quest = 376, Achievement = 444, Mastery = 448 }
local ORANGE = Color3.fromRGB(255, 165, 40)

local function put(inst, cx: number, cy: number)
	inst.AnchorPoint = V2(0.5, 0.5)
	inst.Position = UDim2.fromOffset(math.floor(cx + 0.5), math.floor(cy + 0.5))
end

local Detail = {}

function Detail.new(parent)
	local api, conns = {}, {}
	local onAction
	local current

	local root = make("Frame", {
		Name = "QuestDetail",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = parent.ZIndex,
	}, parent)
	local z0 = root.ZIndex
	local title = Kit.text(root, {
		Name = "Title",
		TextSize = 28,
		AnchorPoint = V2(0.5, 0.5),
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = z0 + 2,
	}, 3)
	local titleRule = Chrome.divider(root, { Name = "TitleRule", ZIndex = z0 + 1, Size = UDim2.fromOffset(10, 2) })
	local scroll = make("ScrollingFrame", {
		Name = "Scroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 0, -- the code-drawn bar below replaces the native one
		ScrollBarImageTransparency = 1,
		ZIndex = z0 + 1,
	}, root)
	local body = make("Frame", { Name = "Body", BackgroundTransparency = 1, ZIndex = z0 + 2 }, scroll)
	local sbar = Kit.scrollbar(root, scroll, z0 + 6)
	local placeholder = Kit.text(root, {
		Name = "Placeholder",
		Text = "Nothing selected",
		TextSize = 24,
		TextColor3 = Kit.Soft,
		AnchorPoint = V2(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -40, 0, 40),
		ZIndex = z0 + 2,
	})

	local function kind(name: string)
		return make(
			"Frame",
			{ Name = name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = body.ZIndex + 1 },
			body
		)
	end
	local function glow(f)
		return make("ImageLabel", {
			Name = "Glow",
			BackgroundTransparency = 1,
			Image = Q.GlowRadial.Image,
			ImageColor3 = ORANGE,
			ImageTransparency = 0.1,
			Size = UDim2.fromOffset(240, 240),
			ZIndex = f.ZIndex + 1,
		}, f)
	end
	local function heroImage(f, name: string)
		return make("ImageLabel", { Name = name, BackgroundTransparency = 1, ZIndex = f.ZIndex + 2 }, f)
	end
	local function label(f, name: string, size: number, o)
		o = o or {}
		o.Name, o.TextSize = name, size
		o.AnchorPoint = V2(0.5, 0.5)
		o.ZIndex = o.ZIndex or f.ZIndex + 3
		local stroke = o.Stroke or 2
		o.Stroke = nil
		return Kit.text(f, o, stroke)
	end
	local function box(f, name: string)
		return Chrome.panel(f, {
			Name = name,
			BackgroundColor3 = Kit.DetailFill,
			NoGradient = true,
			Radius = 10,
			Rim = 2,
			AnchorPoint = V2(0.5, 0.5),
			ZIndex = f.ZIndex + 1,
		})
	end
	local function chip(f, name: string, text: string, w: number)
		local c = Kit.chip(f, text, w, 24, { Name = name, AnchorPoint = V2(0.5, 0.5), ZIndex = f.ZIndex + 4 })
		return c
	end

	-- Quest kind ------------------------------------------------------------------------------------------------
	local quest = kind("Quest")
	local qGlow, qIcon = glow(quest), heroImage(quest, "Icon")
	local qName = label(quest, "Name", 30, { TextTruncate = Enum.TextTruncate.None, Stroke = 3 })
	local qObjBox, qProgBox, qRewBox = box(quest, "ObjectiveBox"), box(quest, "ProgressBox"), box(quest, "RewardsBox")
	local qObjChip, qProgChip, qRewChip =
		chip(quest, "ObjectiveChip", "OBJECTIVE", 135),
		chip(quest, "ProgressChip", "PROGRESS", 135),
		chip(quest, "RewardsChip", "REWARDS", 135)
	local qObj = label(quest, "ObjectiveText", 16, { TextWrapped = true, TextTruncate = Enum.TextTruncate.None })
	local qBar = Kit.bar(quest, {
		Name = "ProgressBar",
		AnchorPoint = V2(0.5, 0.5),
		Size = UDim2.fromOffset(250, 25),
		ZIndex = quest.ZIndex + 4,
	}, Kit.Yellow, 19)
	local function rewardPair(f, prefix: string, ref, color: Color3)
		local ic = make("ImageLabel", { Name = prefix .. "Icon", BackgroundTransparency = 1, ZIndex = f.ZIndex + 4 }, f)
		Kit.setIcon(ic, ref)
		local t =
			label(f, prefix .. "Text", 28, { TextColor3 = color, TextTruncate = Enum.TextTruncate.None, Stroke = 3 })
		return ic, t
	end
	local coinIcon, coinText = rewardPair(quest, "Gold", HudSprites.Coin, Kit.CoinText)
	local gemIcon, gemText = rewardPair(quest, "Gems", HudSprites.Gem, Color3.new(1, 1, 1))

	-- Achievement kind --------------------------------------------------------------------------------------------
	local ach = kind("Achievement")
	ach.Visible = false
	local aGlow, aBadge = glow(ach), heroImage(ach, "Badge")
	local aName = label(ach, "Name", 30, { TextTruncate = Enum.TextTruncate.None, Stroke = 3 })
	local aStatus =
		Achievements.status(ach, { Name = "Status", AnchorPoint = V2(0.5, 0.5), Size = UDim2.fromOffset(150, 26) }, 17)
	local aDesc =
		label(ach, "Desc", 17, { TextWrapped = true, TextColor3 = Kit.Soft, TextTruncate = Enum.TextTruncate.None })
	local aRule1 = Kit.rule(
		ach,
		{ Name = "Rule1", Size = UDim2.fromOffset(276, 8), Position = UDim2.fromOffset(0, 0), ZIndex = ach.ZIndex + 2 }
	)
	local aRule2 = Kit.rule(
		ach,
		{ Name = "Rule2", Size = UDim2.fromOffset(276, 8), Position = UDim2.fromOffset(0, 0), ZIndex = ach.ZIndex + 2 }
	)
	local aLabel = label(ach, "ProgressLabel", 20, { Text = "PROGRESS" })
	local aBar = Kit.bar(
		ach,
		{ Name = "ProgressBar", AnchorPoint = V2(0.5, 0.5), Size = UDim2.fromOffset(250, 24), ZIndex = ach.ZIndex + 4 },
		Kit.Green,
		18
	)
	local aRewChip = chip(ach, "RewardChip", "REWARD", 115)
	local aRewards = {}
	for i = 1, 2 do
		local ic =
			make("ImageLabel", { Name = "RewardIcon" .. i, BackgroundTransparency = 1, ZIndex = ach.ZIndex + 4 }, ach)
		aRewards[i] = { icon = ic, text = label(ach, "RewardText" .. i, 24, { TextTruncate = Enum.TextTruncate.None }) }
	end

	-- Mastery kind --------------------------------------------------------------------------------------------------
	local mas = kind("Mastery")
	mas.Visible = false
	local mGlow, mDie = glow(mas), heroImage(mas, "Die")
	local mName = label(mas, "Name", 29, { TextTruncate = Enum.TextTruncate.None, Stroke = 3 })
	local mPill
	local mBar = Kit.bar(
		mas,
		{ Name = "XpBar", AnchorPoint = V2(0.5, 0.5), Size = UDim2.fromOffset(262, 24), ZIndex = mas.ZIndex + 4 },
		Kit.Yellow,
		18
	)
	local mDesc =
		label(mas, "Desc", 16, { TextWrapped = true, TextColor3 = Kit.Soft, TextTruncate = Enum.TextTruncate.None })
	local mRule = Kit.rule(
		mas,
		{ Name = "Rule", Size = UDim2.fromOffset(276, 8), Position = UDim2.fromOffset(0, 0), ZIndex = mas.ZIndex + 2 }
	)
	local mNext = chip(mas, "NextChip", "NEXT REWARDS", 190)
	local mCards = {} -- rebuilt per Show

	-- Action: transparent touch-size hit button over a non-interactive Parts.button (reparented per kind).
	local actions = make("Frame", {
		Name = "ActionRow",
		BackgroundTransparency = 1,
		AnchorPoint = V2(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, ACTION_H),
		ZIndex = z0 + 3,
	}, root)
	local hit = make("TextButton", {
		Name = "Action",
		BackgroundTransparency = 1,
		Text = "",
		AnchorPoint = V2(0.5, 0.5),
		ZIndex = actions.ZIndex + 1,
	}, actions)
	local visual = Parts.button(hit, {
		Name = "Claim",
		Style = "Green",
		Label = "CLAIM",
		TextSize = 34,
		Size = UDim2.fromOffset(226, 52),
	})
	visual.AnchorPoint = V2(0.5, 0.5)
	visual.Position = UDim2.fromScale(0.5, 0.5)
	visual.Interactable = false -- the hit button above takes the tap
	visual.Selectable = false
	UiKit.wire(hit, function(state)
		visual:SetAttribute("DebugState", if state == "Normal" then nil else state)
	end)
	table.insert(
		conns,
		hit.Activated:Connect(function()
			if onAction and current and current.Action then
				onAction(current.Action.State, current)
			end
		end)
	)
	local function placeAction(parentFrame, cx: number, cy: number, w: number, h: number, textMax: number)
		hit.Parent = parentFrame
		hit.ZIndex = parentFrame.ZIndex + 8
		put(hit, cx, cy)
		hit.Size = UDim2.fromOffset(math.max(w, Kit.minHit), math.max(h, Kit.minHit))
		visual.Size = UDim2.fromOffset(w, h)
		visual:SetAttribute("TextMax", textMax)
	end

	-- Layout ------------------------------------------------------------------------------------------------------
	local hero = true
	local function stripH(k: string?): number
		return if k == "Quest" then ACTION_H else 0
	end
	local function fitScroll()
		local W, H = parent.Size.X.Offset, parent.Size.Y.Offset
		if W <= 0 then
			return
		end
		hero = H >= HERO_MIN
		local k = current and current.Kind
		title.Size = UDim2.fromOffset(W - 24, 36)
		put(title, W / 2, TITLE_H / 2 - 1)
		titleRule.Position = UDim2.fromOffset(INS, TITLE_H)
		titleRule.Size = UDim2.fromOffset(W - 2 * INS, 2)
		local top = TITLE_H + 3
		local viewH = H - top - stripH(k)
		scroll.Position = UDim2.fromOffset(0, top)
		scroll.Size = UDim2.fromOffset(W, math.max(10, viewH))
		local bodyH = BODY_H[k or "Quest"] - (if hero then 0 else HERO_H)
		body.Position = UDim2.fromOffset(INS, 0)
		body.Size = UDim2.fromOffset(W - 2 * INS, bodyH)
		scroll.CanvasSize = UDim2.fromOffset(0, bodyH)
		sbar.Layout(math.max(10, viewH - 8), 8, 3, top + 4)
		actions.Size = UDim2.new(1, 0, 0, ACTION_H)
	end

	local function toggleHero(on: boolean, ...)
		for _, v in { ... } do
			v.Visible = on
		end
	end

	local function showQuest(m)
		local b = m.Body
		local BW = body.Size.X.Offset
		local cx = BW / 2
		local dy = if hero then 0 else -HERO_H
		put(qGlow, cx, 52)
		put(qIcon, cx, 52)
		qIcon.Size = UDim2.fromOffset(84, 84)
		Kit.setIcon(qIcon, m.Icon)
		toggleHero(hero, qGlow, qIcon)
		qName.Text = m.Name or ""
		qName.Size = UDim2.fromOffset(BW, 40)
		put(qName, cx, 108 + dy)
		qName.TextSize = Kit.fitSize(qName.Text, BW - 4, 30, 16)
		local function section(boxInst, chipInst, y0: number, y1: number)
			boxInst.Size = UDim2.fromOffset(BW, y1 - y0)
			put(boxInst, cx, (y0 + y1) / 2 + dy)
			put(chipInst, cx, y0 + dy)
		end
		section(qObjBox, qObjChip, 147, 200)
		section(qProgBox, qProgChip, 221, 275)
		section(qRewBox, qRewChip, 296, 368)
		qObj.Text = b.Desc or ""
		qObj.Size = UDim2.fromOffset(BW - 20, 36)
		put(qObj, cx, 181 + dy) -- starts under the OBJECTIVE chip
		qObj.TextSize = Kit.fitSize(qObj.Text, (BW - 20) * 1.8, 16, 10)
		while qObj.TextBounds.Y > qObj.AbsoluteSize.Y and qObj.TextSize > 11 do -- wrapped value must stay inside its box, clear of the chip
			qObj.TextSize -= 1
		end
		qBar.Frame.Size = UDim2.fromOffset(BW - 28, 25)
		put(qBar.Frame, cx, 250 + dy)
		local complete = b.Goal > 0 and b.Progress >= b.Goal
		qBar:Set(
			QuestLogic.percent(b.Progress, b.Goal),
			QuestLogic.progressText(b.Progress, b.Goal),
			if complete then Kit.Green else Kit.Yellow
		)
		local hasGems = b.Gems ~= nil
		local half = BW / 2 - 10
		local function pair(ic, text, str: string, cxp: number, maxW: number)
			text.Text = str
			text.TextSize = Kit.fitSize(str, maxW - 42, 28, 14)
			local tw = math.ceil(Kit.measure(str, text.TextSize)) + 2
			local left = cxp - (36 + 6 + tw) / 2
			ic.Size = UDim2.fromOffset(36, 36)
			put(ic, left + 18, 334 + dy)
			text.Size = UDim2.fromOffset(tw, 36)
			put(text, left + 42 + tw / 2, 334 + dy)
		end
		pair(
			coinIcon,
			coinText,
			"+" .. QuestLogic.format(b.Gold or 0),
			if hasGems then BW * 0.28 else cx,
			if hasGems then half else BW - 20
		)
		toggleHero(hasGems, gemIcon, gemText)
		if hasGems then
			pair(gemIcon, gemText, "+" .. QuestLogic.format(b.Gems), BW * 0.74, half)
		end
		placeAction(actions, parent.Size.X.Offset / 2, ACTION_H / 2 - 8, 226, 52, 34)
	end

	local function showAchievement(m)
		local b = m.Body
		local BW = body.Size.X.Offset
		local cx = BW / 2
		local dy = if hero then 0 else -HERO_H
		put(aGlow, cx, 50)
		local rec = Q[(b.Badge or "") .. "Big"] or Q[b.Badge] or Q.BadgeKing
		Kit.setIcon(aBadge, rec)
		aBadge.Size = UDim2.fromOffset(math.min(190, BW - 20), 92)
		put(aBadge, cx, 50)
		toggleHero(hero, aGlow, aBadge)
		aName.Text = string.upper(m.Name or "")
		aName.Size = UDim2.fromOffset(BW, 40)
		put(aName, cx, 109 + dy)
		aName.TextSize = Kit.fitSize(aName.Text, BW - 4, 30, 15)
		put(aStatus.Frame, cx, 143 + dy)
		aStatus:Set(b)
		aDesc.Text = b.Desc or ""
		aDesc.Size = UDim2.fromOffset(BW - 12, 62)
		put(aDesc, cx, 199 + dy)
		aDesc.TextSize = Kit.fitSize(aDesc.Text, (BW - 12) * 2.6, 17, 12)
		aRule1.Size, aRule2.Size = UDim2.fromOffset(BW, 8), UDim2.fromOffset(BW, 8)
		put(aRule1, cx, 243 + dy)
		aLabel.Size = UDim2.fromOffset(BW, 26)
		put(aLabel, cx, 264 + dy)
		aBar.Frame.Size = UDim2.fromOffset(BW - 26, 24)
		put(aBar.Frame, cx, 291 + dy)
		local complete = b.Goal > 0 and b.Progress >= b.Goal
		aBar:Set(
			QuestLogic.percent(b.Progress, b.Goal),
			QuestLogic.progressText(b.Progress, b.Goal),
			if complete then Kit.Green else Kit.Yellow
		)
		put(aRule2, cx, 317 + dy)
		put(aRewChip, cx, 336 + dy)
		for i, r in aRewards do
			local entry = b.Rewards[i]
			r.icon.Visible, r.text.Visible = entry ~= nil, entry ~= nil
			if entry then
				local x = 46 + (i - 1) * 90
				Kit.setIcon(r.icon, QuestLogic.rewardIcon(entry))
				r.icon.Size = UDim2.fromOffset(76, 72)
				put(r.icon, x, 376 + dy)
				r.text.Text = "x" .. QuestLogic.format(entry.Amount)
				r.text.Size = UDim2.fromOffset(80, 28)
				put(r.text, x, 428 + dy)
				r.text.TextSize = Kit.fitSize(r.text.Text, 78, 24, 13)
			end
		end
		placeAction(ach, BW - 52, 395 + dy, 100, 52, 30)
	end

	local function showMastery(m)
		local b = m.Body
		local BW = body.Size.X.Offset
		local cx = BW / 2
		local dy = if hero then 0 else -HERO_H
		put(mGlow, cx, 52)
		Kit.setIcon(mDie, b.Art)
		mDie.ImageColor3 = b.Tint or Color3.new(1, 1, 1) -- the roll glyph takes the die colour; elemental art keeps its own
		mDie.Size = UDim2.fromOffset(120, 120)
		put(mDie, cx, 52)
		toggleHero(hero, mGlow, mDie)
		local dieName = Kit.dieName(b.Name)
		mName.Text = dieName
		mName.Size = UDim2.fromOffset(BW, 40)
		put(mName, cx, 111 + dy)
		mName.TextSize = Kit.fitSize(dieName, BW - 4, 29, 15)
		if mPill then
			mPill:Destroy()
		end
		mPill = Mastery.pill(mas, 190, 28, b.Level, 18)
		put(mPill, cx, 149 + dy)
		mBar.Frame.Size = UDim2.fromOffset(BW - 14, 24)
		put(mBar.Frame, cx, 188 + dy)
		mBar:Set(QuestLogic.percent(b.Xp, b.XpGoal), QuestLogic.progressText(b.Xp, b.XpGoal))
		local claimable = m.Action and m.Action.State == "Claim"
		local shift = if claimable then 14 else 0 -- CLAIM squeezes between the description and the rule; the cards keep their size
		mDesc.Text = "Increase the power of " .. dieName .. " to unlock exclusive rewards!"
		mDesc.Size = UDim2.fromOffset(BW - 8, if claimable then 36 else 44)
		put(mDesc, cx, (if claimable then 223 else 228) + dy)
		mDesc.TextSize = Kit.fitSize(mDesc.Text, (BW - 8) * 1.9, if claimable then 12 else 16, 9)
		while mDesc.TextBounds.Y > mDesc.AbsoluteSize.Y and mDesc.TextSize > 10 do -- never over the XP bar or CLAIM
			mDesc.TextSize -= 1
		end
		local cardH = 138
		mRule.Size = UDim2.fromOffset(BW, 8)
		put(mRule, cx, 258 + dy + shift)
		put(mNext, cx, 280 + dy + shift)
		for _, c in mCards do
			c:Destroy()
		end
		table.clear(mCards)
		local cw = math.floor((BW - 12) / 2)
		for i, entry in QuestLogic.nextRewards(b) do
			local card = Chrome.panel(mas, {
				Name = "Card" .. i,
				BackgroundColor3 = Kit.DetailFill,
				NoGradient = true,
				Radius = 12,
				Rim = 2,
				AnchorPoint = V2(0.5, 0),
				Position = UDim2.fromOffset(cw / 2 + (i - 1) * (cw + 12), 292 + dy + shift),
				Size = UDim2.fromOffset(cw, cardH),
				ZIndex = mas.ZIndex + 1,
			})
			table.insert(mCards, card)
			local ic = make("ImageLabel", {
				Name = "Icon",
				BackgroundTransparency = 1,
				AnchorPoint = V2(0.5, 0.5),
				Position = UDim2.fromOffset(cw / 2, cardH * 0.29),
				Size = UDim2.fromOffset(56, 52),
				ZIndex = card.ZIndex + 1,
			}, card)
			Kit.setIcon(ic, entry.Icon)
			local name = Kit.text(card, {
				Name = "Name",
				Text = entry.Name,
				TextSize = 16,
				TextWrapped = true,
				AnchorPoint = V2(0.5, 0.5),
				Position = UDim2.fromOffset(cw / 2, cardH * 0.64),
				Size = UDim2.fromOffset(cw - 8, 36),
				ZIndex = card.ZIndex + 1,
			}, 2)
			name.TextSize = Kit.fitSize(entry.Name, (cw - 8) * 1.8, 16, 11)
			local locked = entry.State == "Locked"
			local lv = Kit.chip(card, "Lv. " .. entry.Lv, cw - 24, 24, {
				Name = "LevelChip",
				AnchorPoint = V2(0.5, 0.5),
				Position = UDim2.fromOffset(cw / 2, cardH * 0.86),
				ZIndex = card.ZIndex + 1,
			})
			if locked then
				make("ImageLabel", {
					Name = "Lock",
					BackgroundTransparency = 1,
					AnchorPoint = V2(0, 0.5),
					Position = UDim2.fromOffset(8, 12),
					Size = UDim2.fromOffset(20, 20),
					Image = Shared.Padlock.Image,
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = lv.ZIndex + 2,
				}, lv)
			end
		end
		if claimable then
			placeAction(mas, cx, 253 + dy, 226, 30, 24)
		end
	end

	local function layout()
		if parent.Size.X.Offset <= 0 then
			return
		end
		fitScroll()
		if current then
			api:Show(current)
		end
	end
	table.insert(conns, parent:GetPropertyChangedSignal("Size"):Connect(layout))

	function api:Show(model)
		current = model
		local k = model and model.Kind
		placeholder.Visible = model == nil
		scroll.Visible, title.Visible, titleRule.Visible = model ~= nil, model ~= nil, model ~= nil
		quest.Visible, ach.Visible, mas.Visible = k == "Quest", k == "Achievement", k == "Mastery"
		fitScroll()
		if not model then
			actions.Visible = false
			return
		end
		title.Text = model.Title or ""
		title.TextSize = Kit.fitSize(title.Text, parent.Size.X.Offset - 24, if hero then 28 else 22, 14)
		scroll.CanvasPosition = Vector2.zero
		local a = model.Action
		actions.Visible = k == "Quest"
		if k == "Quest" then
			showQuest(model)
		elseif k == "Achievement" then
			showAchievement(model)
		else
			showMastery(model)
		end
		local shown = a ~= nil and (k ~= "Mastery" or a.State == "Claim")
		hit.Visible = shown
		if shown then
			Parts.setButton(visual, { Label = a.Label, Enabled = a.Enabled ~= false })
		end
	end
	function api:OnAction(cb)
		onAction = cb
	end
	function api:Destroy()
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
		root:Destroy()
	end
	api:Show(nil)
	return api
end

return Detail
