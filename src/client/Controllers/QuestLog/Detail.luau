-- Quest Log detail panel, one template for all three tabs: a scrolling body (kind-specific widgets) over one bottom action button.
-- Detail.new(Slots.Detail) -> :Show(model|nil) :OnAction(cb(state, model)) :Destroy
-- model = { Kind = "Quest" | "Achievement" | "Mastery", Title, Name, Icon (QuestSprites key), Action = { Label, State, Enabled }, Body }
--   Quest Body = { Desc, Progress, Goal, Gold, Gems? } (Gems nil hides the gems box). State = Claim | Claimed | Soon | Progress.
--   Achievement Body = { Desc, Progress, Goal, Unit?, Locked?, Badge, BadgeBig?, Rewards = { { Name, Amount } } }.
--   Mastery Body = the mastery row { Desc, Level, Xp, XpGoal, Die, Milestones } (SampleData.Mastery shape); Title "DICE MASTERY", no Action.

local UiKit = require(script.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Bag.Parts)
local HudSprites = require(script.Parent.Parent.Sprites)
local QuestLogic = require(script.Parent.QuestLogic)
local Draw = require(script.Parent.Draw)
local Achievements = require(script.Parent.Tabs.Achievements)
local Mastery = require(script.Parent.Tabs.Mastery)

local make = UiKit.make
local Bag, Q = Draw.Bag, Draw.Q

local EXT = 12 -- the bodies reach this far below the slot, inside the panel art (ref cards end ~11 px above the rim)
local COMPACT_H = 540 -- slots shorter than this (phones) drop the hero art and scroll the rest
local INSET = 12 -- the scroll sits inside the panel rim, so clipped art and the scroll thumb never cross it
local ACTION_H = 80 -- bottom strip: the button (248x81 box, ink ~238x66, ref 238x~66) stays put while the body scrolls
local BODY_H = 508
local MAST_H = 601 -- Mastery body: no action button, so no bottom strip (the scroll is the slot + EXT, so it never scrolls)
local ACH_H = 601 -- Achievement body: the CLAIM button sits in its reward row, so no bottom strip
-- compact (phone) bodies: a separate stacked layout per kind that fits the panel without scrolling (hero art and description dropped)
local COMPACT_BODY = { Quest = 216, Achievement = 245, Mastery = 276 }
local REWARD_ICON = { Crystals = "Crystals", Die = "SkinFire" } -- Die: closest available die art
local BOX_H, BOX_K = 55, 0.55 -- StatRow boxes: visible height and rim scale
local COIN_TEXT = Color3.fromRGB(251, 243, 137)
local SOFT = Color3.fromRGB(205, 210, 235)

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
	local scroll = make("ScrollingFrame", {
		Name = "Scroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, EXT - ACTION_H),
		CanvasSize = UDim2.fromOffset(0, BODY_H),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 0, -- the purple thumb below replaces the native bar (it must sit inside the panel rim)
		ScrollBarImageTransparency = 1, -- a 0-thickness bar still draws a 1 px hairline
		ZIndex = root.ZIndex + 1,
	}, root)
	local body =
		Draw.img(scroll, { Name = "Body", Size = UDim2.fromOffset(340, BODY_H), ZIndex = scroll.ZIndex + 1 }, "Frame")
	local placeholder = Parts.text(root, {
		Name = "Placeholder",
		Text = "Select a quest",
		TextSize = 24,
		TextColor3 = SOFT,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -40, 0, 40),
	})

	-- Thumb track: a 16 px strip just inside the scroll's right edge; the purple pill shows only while the body scrolls.
	local track = Draw.img(root, { Name = "ThumbTrack", ZIndex = scroll.ZIndex + 4 })
	track.Image = Bag.ScrollTrack.Image
	track.ScaleType = Enum.ScaleType.Slice
	track.SliceCenter = Rect.new(19, 65, 22, 227) -- narrow centre column, like the list bars
	track.SliceScale = 16 / Bag.ScrollTrack.Size.X
	local thumb = Draw.img(track, { Name = "Thumb" })
	local viewH = 0
	local function updateThumb()
		local canvas = scroll.CanvasSize.Y.Offset
		local maxY = canvas - viewH
		track.Visible = scroll.Visible and maxY > 1
		if not track.Visible then
			return
		end
		local room = viewH - 74 -- starts below the ribbon tail
		local h = math.clamp(math.floor(room * viewH / canvas), 30, room)
		Draw.thumb(thumb, 16, h, 64 + math.floor((room - h) * math.clamp(scroll.CanvasPosition.Y / maxY, 0, 1)))
	end
	table.insert(conns, scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(updateThumb))

	local function at(inst, x: number, y: number)
		inst.AnchorPoint = Vector2.new(0.5, 0.5)
		inst.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	end

	local compact = false
	local function actionH(): number
		return if compact then 64 else ACTION_H
	end
	local function bodyH(kind: string?): number
		if compact then
			return COMPACT_BODY[kind or "Quest"]
		end
		return if kind == "Achievement" then ACH_H elseif kind == "Mastery" then MAST_H else BODY_H
	end
	-- The scroll reaches EXT below the slot only while the whole body fits there; otherwise it stops at the slot edge
	-- (a little above the rim for the tall kinds) and scrolls.
	local function fitScroll()
		compact = parent.Size.Y.Offset < COMPACT_H
		local kind = current and current.Kind
		local tall = kind == "Achievement" or kind == "Mastery"
		local strip = if tall then 0 else actionH() + (if compact then 8 else 0) -- compact: the button floats 8 above the rim
		local ext = if bodyH(kind) <= parent.Size.Y.Offset - strip + EXT then EXT elseif tall then -10 else 0
		scroll.Position = UDim2.fromOffset(INSET, 0)
		scroll.Size = UDim2.new(1, -2 * INSET, 1, ext - strip)
		viewH = parent.Size.Y.Offset + ext - strip
		track.Position = UDim2.fromOffset(parent.Size.X.Offset - INSET - 17, 0)
		track.Size = UDim2.fromOffset(16, viewH)
		task.defer(updateThumb) -- after the canvas size of this kind is set
	end

	-- Quest kind --------------------------------------------------------------------------------------------
	local quest = Draw.img(body, { Name = "Quest", Size = UDim2.fromScale(1, 1) }, "Frame")
	local z = quest.ZIndex
	local glow = Draw.img(quest, { Name = "Glow", ImageTransparency = 0.5, ZIndex = z + 1 }) -- soft purple bloom (Epic glow)
	local icon = Draw.img(quest, { Name = "Icon", ZIndex = z + 3 })
	local sparkles = {}
	for i = 1, 4 do
		sparkles[i] = Draw.img(quest, { Name = "Sparkle" .. i, ZIndex = z + 4 })
	end
	local ribbon = Draw.img(quest, { Name = "Ribbon", ZIndex = z + 5 })
	local ribbonText =
		Parts.text(quest, { Name = "Title", TextSize = 26, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = z + 6 }, 3)
	local name =
		Parts.text(quest, { Name = "Name", TextSize = 38, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = z + 4 }, 3)
	local divider = Draw.img(quest, { Name = "Divider", ZIndex = z + 2 })
	local function boxed(boxName: string)
		local box = Draw.img(quest, { Name = boxName, ZIndex = z + 2 })
		return box
	end
	local objBox, progBox = boxed("ObjectiveBox"), boxed("ProgressBox")
	local goldBox, gemBox = boxed("GoldBox"), boxed("GemsBox")
	local objText = Parts.text(quest, { Name = "ObjectiveText", TextSize = 22, TextWrapped = true, ZIndex = z + 4 }, 2)
	objText.AnchorPoint = Vector2.new(0.5, 0.5)
	local bar, barW -- rebuilt when the panel width changes (the track sprite is sized at build)
	local showQuest
	local function pill(text: string)
		local p = Parts.Pill(quest, "Purple", text, { Name = text, InkW = 131, InkH = 25, TextSize = 18 })
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.ZIndex = z + 6
		p.Label.ZIndex = z + 7
		return p
	end
	local objPill, progPill, rewPill = pill("OBJECTIVE"), pill("PROGRESS"), pill("REWARDS")
	local function reward(cellName: string, iconId: string, color: Color3)
		local ic = Draw.img(quest, {
			Name = cellName .. "Icon",
			Image = iconId,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(46, 46),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = z + 4,
		})
		local t = Parts.text(quest, {
			Name = cellName .. "Text",
			TextSize = 26,
			TextColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = z + 4,
		}, 3)
		return ic, t
	end
	local coinIcon, coinText = reward("Gold", HudSprites.Coin, COIN_TEXT)
	local gemIcon, gemText = reward("Gems", HudSprites.Gem, Color3.new(1, 1, 1))

	-- Achievement / Mastery kinds: filled later (same body, own frame).
	local achievement = Draw.img(body, { Name = "Achievement", Size = UDim2.fromScale(1, 1), Visible = false }, "Frame")
	local az = achievement.ZIndex
	local aGlow = Draw.img(achievement, { Name = "Glow", ImageTransparency = 0.35, ZIndex = az + 1 })
	local aBadge = Draw.img(achievement, { Name = "Badge", ZIndex = az + 3 })
	local aSparkles = {}
	for i = 1, 4 do
		aSparkles[i] = Draw.img(achievement, { Name = "Sparkle" .. i, ZIndex = az + 4 })
	end
	local aRibbon = Draw.img(achievement, { Name = "Ribbon", ZIndex = az + 5 })
	local aRibbonText = Parts.text(
		achievement,
		{ Name = "Title", TextSize = 26, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = az + 6 },
		3
	)
	local aName = Parts.text(
		achievement,
		{ Name = "Name", TextSize = 34, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = az + 4 },
		3
	)
	local aPill = Achievements.pill(achievement, "Status", 188, 36, az + 4)
	aPill.Frame.AnchorPoint = Vector2.new(0.5, 0.5)
	local aDesc = Parts.text(achievement, {
		Name = "Desc",
		TextSize = 17,
		TextWrapped = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = az + 4,
	}, 2)
	local aDiv1 = Draw.img(achievement, { Name = "Divider1", ZIndex = az + 2 })
	local aDiv2 = Draw.img(achievement, { Name = "Divider2", ZIndex = az + 2 })
	local aLabel = Parts.text(achievement, {
		Name = "ProgressLabel",
		Text = "PROGRESS",
		TextSize = 20,
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = az + 4,
	}, 2)
	local aBar, aBarW
	local aRewPill =
		Parts.Pill(achievement, "Purple", "REWARD", { Name = "RewardPill", InkW = 150, InkH = 28, TextSize = 20 })
	aRewPill.AnchorPoint = Vector2.new(0.5, 0.5)
	aRewPill.ZIndex = az + 6
	aRewPill.Label.ZIndex = az + 7
	local aRewards = {} -- up to two reward boxes: { box, icon, text }
	for i = 1, 2 do
		aRewards[i] = {
			box = Draw.img(achievement, { Name = "RewardBox" .. i, ZIndex = az + 2 }),
			icon = Draw.img(achievement, { Name = "RewardIcon" .. i, ZIndex = az + 4 }),
			text = Parts.text(
				achievement,
				{ Name = "RewardText" .. i, TextSize = 22, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = az + 4 },
				3
			),
		}
	end
	local showAchievement
	local mastery = Draw.img(body, { Name = "Mastery", Size = UDim2.fromScale(1, 1), Visible = false }, "Frame")
	local mz = mastery.ZIndex
	local mFlagL = Draw.img(mastery, { Name = "FlagL", ZIndex = mz + 1 })
	local mFlagR = Draw.img(mastery, { Name = "FlagR", ZIndex = mz + 1 })
	local mRays = Draw.img(mastery, { Name = "Rays", ZIndex = mz + 1 })
	local mHalo = Draw.img(mastery, { Name = "Halo", ZIndex = mz + 2 })
	local mDie = Draw.img(mastery, { Name = "Die", ZIndex = mz + 3 })
	local mSparkles = {}
	for i = 1, 4 do
		mSparkles[i] = Draw.img(mastery, { Name = "Sparkle" .. i, ZIndex = mz + 4 })
	end
	local mRibbon = Draw.img(mastery, { Name = "Ribbon", ZIndex = mz + 5 })
	local mRibbonText =
		Parts.text(mastery, { Name = "Title", TextSize = 24, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = mz + 6 }, 3)
	local mName =
		Parts.text(mastery, { Name = "Name", TextSize = 32, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = mz + 4 }, 3)
	local mPill = Mastery.pill(mastery, "LevelPill", 200, mz + 4)
	mPill.Frame.AnchorPoint = Vector2.new(0.5, 0.5)
	local mBar, mBarW
	local mDesc = Parts.text(mastery, {
		Name = "Desc",
		TextSize = 17,
		TextWrapped = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = mz + 4,
	}, 2)
	local mDiv = Draw.img(mastery, { Name = "Divider", ZIndex = mz + 2 })
	local mNext = Draw.img(mastery, { Name = "NextBanner", ZIndex = mz + 3 })
	local mNextText = Parts.text(mastery, {
		Name = "NextText",
		Text = "NEXT REWARDS",
		TextSize = 18,
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = mz + 4,
	}, 2)
	local mRewards = {} -- up to two reward boxes: { box, icon, name, lock, lv }
	for i = 1, 2 do
		local function label(n: string)
			return Parts.text(
				mastery,
				{ Name = n .. i, TextSize = 16, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = mz + 4 },
				2
			)
		end
		mRewards[i] = {
			box = Draw.img(mastery, { Name = "RewardBox" .. i, ZIndex = mz + 2 }),
			icon = Draw.img(mastery, { Name = "RewardIcon" .. i, ZIndex = mz + 4 }),
			name = label("RewardName"),
			pill = Draw.img(mastery, { Name = "RewardLvPill" .. i, ZIndex = mz + 3 }),
			lock = Draw.img(mastery, { Name = "RewardLock" .. i, ZIndex = mz + 4 }),
			lv = label("RewardLv"),
		}
	end
	local showMastery

	-- Action button: transparent touch-size hit button over a non-interactive Parts.button visual.
	local actions = Draw.img(root, {
		Name = "ActionRow",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, ACTION_H),
		ZIndex = scroll.ZIndex + 3,
	}, "Frame")
	local sparkL = Draw.img(actions, { Name = "SparkleL", ZIndex = actions.ZIndex })
	local sparkR = Draw.img(actions, { Name = "SparkleR", ZIndex = actions.ZIndex })
	local hit = Draw.img(actions, {
		Name = "Action",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(256, 80),
		ZIndex = actions.ZIndex + 1,
	}, "ImageButton")
	Parts.interact(hit)
	local visual = Parts.button(hit, {
		Name = "Claim",
		Style = "Green",
		Label = "CLAIM",
		TextSize = 32,
		Size = UDim2.fromOffset(248, 81),
	})
	visual.AnchorPoint = Vector2.new(0.5, 0.5)
	visual.Position = UDim2.fromScale(0.5, 0.5)
	visual.Interactable = false -- a button still swallows clicks when only Active is false; the hit above takes the tap
	visual.Selectable = false
	table.insert(
		conns,
		hit.Activated:Connect(function()
			if onAction and current and current.Action then
				onAction(current.Action.State, current)
			end
		end)
	)

	local function placeAction() -- the strip's size and the button's, for the current tier (the Achievement branch overrides the button)
		actions.Size = UDim2.new(1, 0, 0, actionH())
		actions.Position = UDim2.new(0.5, 0, 1, if compact then -8 else 8) -- ref: CLAIM sits close to the bottom rim
		hit.Size = if compact then UDim2.fromOffset(228, 62) else UDim2.fromOffset(256, 80)
		visual.Size = if compact then UDim2.fromOffset(220, 62) else UDim2.fromOffset(248, 81)
	end

	local function layout()
		local slotW = parent.Size.X.Offset
		if slotW <= 0 then
			return
		end
		fitScroll()
		if not (current and current.Kind == "Achievement") then
			placeAction()
		end
		local W = slotW - 2 * (if slotW >= 380 then 40 else 14)
		local kind = current and current.Kind
		body.Size = UDim2.fromOffset(W, bodyH(kind))
		body.Position = UDim2.fromOffset((slotW - 2 * INSET - W) / 2, 0)
		local cx = W / 2
		local rw = math.min(300, W - 16)
		Draw.apply(ribbon, Q.DetailRibbon, cx, 36, rw, rw * Q.DetailRibbon.Ink.Height / Q.DetailRibbon.Ink.Width)
		at(ribbonText, cx, 33)
		ribbonText.Size = UDim2.fromOffset(rw * 0.62, 40)
		local gw, gh = Draw.fitIn(Bag.GlowEpic, 230, 230)
		Draw.apply(glow, Bag.GlowEpic, cx, 139, gw, gh)
		glow.Visible = not compact -- its soft square would end in a hard edge at the scroll rim
		local function spark(i: number, rec, dx: number, dy: number, size: number)
			local sw, sh = Draw.fitIn(rec, size, size)
			Draw.apply(sparkles[i], rec, cx + dx, 139 + dy, sw, sh)
		end
		local reach = math.min(112, W / 2 - 24)
		spark(1, Q.Sparkle1, -reach + 5, 0, 30) -- ref spots (design px from the icon centre)
		spark(2, Q.Sparkle2, reach - 9, -3, 26)
		spark(3, Q.Sparkle3, -80, -47, 18)
		spark(4, Q.Sparkle4, 83, 28, 17)
		for _, sp in sparkles do
			sp.Visible = not compact
		end
		at(name, cx, 223)
		name.Size = UDim2.fromOffset(W - 10, 46)
		Draw.apply(divider, Bag.DividerGold, cx, 254, rw, rw * Bag.DividerGold.Ink.Height / Bag.DividerGold.Ink.Width)

		local function box(inst, x: number, y: number, w: number, h: number)
			Draw.apply(inst, Bag.StatRow, x, y, w, h, BOX_K)
		end
		box(objBox, cx, 305, W, BOX_H)
		at(objPill, cx, 283)
		at(objText, cx, 307)
		objText.Size = UDim2.fromOffset(W - 28, BOX_H - 10)
		box(progBox, cx, 385, W, BOX_H)
		at(progPill, cx, 354)
		at(rewPill, cx, 430)
		if barW ~= W - 30 then
			barW = W - 30
			if bar then
				bar.Frame:Destroy()
			end
			bar = Draw.bar(quest, "ProgressBar", barW, 30, z + 4)
		end
		at(bar.Frame, cx, 385)
		for _, v in { glow, icon, objBox, progBox, objPill, progPill, rewPill } do
			v.Visible = not compact
		end
		if compact then -- stack: ribbon, name, objective line, progress bar, rewards (see showQuest), CLAIM strip
			at(name, cx, 74)
			name.Size = UDim2.fromOffset(W - 10, 34)
			Draw.apply(
				divider,
				Bag.DividerGold,
				cx,
				96,
				rw,
				rw * Bag.DividerGold.Ink.Height / Bag.DividerGold.Ink.Width
			)
			at(objText, cx, 114)
			objText.Size = UDim2.fromOffset(W - 20, 34)
			at(bar.Frame, cx, 152)
		end
		if current and current.Kind == "Quest" then
			showQuest(current)
		elseif current and current.Kind == "Achievement" then
			showAchievement(current)
		elseif current and current.Kind == "Mastery" then
			showMastery(current)
		end
	end
	table.insert(conns, parent:GetPropertyChangedSignal("Size"):Connect(layout))
	layout()

	function showQuest(m)
		local b = m.Body
		ribbonText.Text = m.Title or "QUEST DETAILS"
		Parts.fit(ribbonText, ribbonText.Size.X.Offset, 26, 16)
		name.Text = m.Name or ""
		Parts.fit(name, name.Size.X.Offset, if compact then 28 else 38, if compact then 16 else 22)
		local rec = Q.IconQuestScroll -- the reference always shows the scroll for the Quest kind
		local iw, ih = Draw.fitIn(rec, 175, 143)
		Draw.apply(icon, rec, body.Size.X.Offset / 2, 139, iw, ih)
		icon.Visible = not compact
		objText.Text = b.Desc or ""
		objText.TextSize = Parts.fitSize(
			objText.Text,
			objText.Size.X.Offset * (if compact then 1.9 else 1.8),
			if compact then 16 else 22,
			if compact then 12 else 15
		)
		local pct = QuestLogic.percent(b.Progress, b.Goal)
		bar:Set(pct, QuestLogic.progressText(b.Progress, b.Goal), b.Goal > 0 and b.Progress >= b.Goal)
		-- Rewards: two boxes; the gems box is hidden for real rows and the gold box then centres.
		local W = body.Size.X.Offset
		local cellW = math.floor((W - 8) / 2)
		local hasGems = b.Gems ~= nil
		local cy = if compact then 192 else 471
		local function cell(boxInst, ic, text, label: string, cx: number, w: number)
			local isz = if compact then 30 else 46
			Draw.apply(boxInst, Bag.StatRow, cx, cy, w, if compact then 46 else 70, BOX_K)
			local iconRight = cx - w / 2 + (if compact then 8 else 10) + isz
			ic.Size = UDim2.fromOffset(isz, isz)
			local textW = (cx + w / 2 - 12) - (iconRight + 6)
			text.Text = label
			text.Size = UDim2.fromOffset(textW, 40)
			Parts.fit(text, textW, if compact then 20 else 26, 12)
			at(ic, iconRight - isz / 2, cy)
			at(text, iconRight + 6 + textW / 2, cy)
			boxInst.Visible, ic.Visible, text.Visible = true, true, true
		end
		cell(
			goldBox,
			coinIcon,
			coinText,
			"+" .. QuestLogic.format(b.Gold or 0),
			if hasGems then cellW / 2 else W / 2,
			cellW
		)
		gemBox.Visible, gemIcon.Visible, gemText.Visible = hasGems, hasGems, hasGems
		if hasGems then
			cell(gemBox, gemIcon, gemText, "+" .. QuestLogic.format(b.Gems), W - cellW / 2, cellW)
		end
	end

	function showAchievement(m)
		local b = m.Body
		local W = body.Size.X.Offset
		local cx = W / 2
		local function sized(inst, rec, y: number, w: number)
			Draw.apply(inst, rec, cx, y, w, w * rec.Ink.Height / rec.Ink.Width)
		end
		local aw = math.min(280, W - 16) -- ref: ribbon grows with its text
		sized(aRibbon, Q.DetailRibbon, 36, aw)
		at(aRibbonText, cx, 33)
		aRibbonText.Size = UDim2.fromOffset(aw * 0.62, 40)
		aRibbonText.Text = m.Title or "ACHIEVEMENT"
		Parts.fit(aRibbonText, aRibbonText.Size.X.Offset, 26, 16)
		local gw, gh = Draw.fitIn(Bag.GlowLegendary, 250, 250)
		Draw.apply(aGlow, Bag.GlowLegendary, cx, 140, gw, gh)
		aGlow.Visible = not compact -- its soft square would end in a hard edge at the scroll rim
		local brec = Q[b.BadgeBig] or Q[b.Badge] or Q.BadgeKing
		local bw, bh = Draw.fitIn(brec, math.min(250, W - 20), if compact then 96 else 130)
		Draw.apply(aBadge, brec, cx, if compact then 112 else 140, bw, bh)
		local reach = math.min(112, W / 2 - 24)
		local sp = {
			{ Q.Sparkle1, -reach, -56, 38 },
			{ Q.Sparkle2, reach, -18, 42 },
			{ Q.Sparkle3, -reach + 20, 40, 18 },
			{ Q.Sparkle4, reach - 34, 44, 22 },
		}
		for i, s in sp do
			local sw, sh = Draw.fitIn(s[1], s[4], s[4])
			Draw.apply(aSparkles[i], s[1], cx + s[2], 140 + s[3], sw, sh)
			aSparkles[i].Visible = not compact
		end
		at(aName, cx, 216)
		aName.Size = UDim2.fromOffset(W - 10, 44)
		aName.Text = string.upper(m.Name or "")
		Parts.fit(aName, W - 10, 34, 20)
		aPill:Set(b)
		at(aPill.Frame, cx, 259)
		at(aDesc, cx, 321)
		aDesc.Size = UDim2.fromOffset(268, 68)
		aDesc.Text = b.Desc or ""
		aDesc.TextSize = Parts.fitSize(aDesc.Text, 268 * 3, 21, 14)
		sized(aDiv1, Bag.DividerGold, 364, math.min(330, W))
		at(aLabel, cx, 390)
		aLabel.Size = UDim2.fromOffset(W, 26)
		sized(aDiv2, Bag.DividerGold, 454, math.min(330, W))
		if aBarW ~= math.min(321, W - 20) then
			aBarW = math.min(321, W - 20)
			if aBar then
				aBar.Frame:Destroy()
			end
			aBar = Draw.bar(achievement, "ProgressBar", aBarW, 30, az + 4)
		end
		at(aBar.Frame, cx, 418)
		local done = not b.Locked and b.Goal > 0 and b.Progress >= b.Goal
		local pct = if b.Locked then 0 else QuestLogic.percent(b.Progress, b.Goal)
		aBar:Set(pct, QuestLogic.progressText(b.Progress, b.Goal, b.Unit), done)
		at(aRewPill, cx, 483)
		-- Reward row (ref): two 112x116 boxes left of the CLAIM button (128x59), all centred on y 540.
		local rowY = 540
		local k = math.min(1, (W - 4) / 357) -- the row is 357 wide: scale it down on phones so nothing leaves the panel
		for i, r in aRewards do
			local entry = b.Rewards[i]
			r.box.Visible, r.icon.Visible, r.text.Visible = entry ~= nil, entry ~= nil, entry ~= nil
			if entry then
				local rx = cx + (-122 + (i - 1) * 113) * k
				Draw.apply(r.box, Bag.StatRow, rx, rowY, 112 * k, 116 * k, BOX_K)
				local rec = Q[REWARD_ICON[entry.Name] or "Crystals"]
				local iw, ih = Draw.fitIn(rec, 60 * k, 64 * k)
				Draw.apply(r.icon, rec, rx + 2, rowY - 12 * k, iw, ih)
				r.text.Text = "x" .. QuestLogic.format(entry.Amount)
				r.text.Size = UDim2.fromOffset(104 * k, 28)
				at(r.text, rx + 3, rowY + 38 * k)
				Parts.fit(r.text, 104 * k, 22, 14)
			end
		end
		hit.Parent = achievement
		hit.ZIndex = az + 8
		hit.Size = UDim2.fromOffset(136 * k, 64 * k)
		hit.Position = UDim2.fromOffset(cx + 115 * k, rowY + 1)
		visual.Size = UDim2.fromOffset(128 * k, 59 * k)
		for _, v in { aBadge, aDesc, aDiv1, aDiv2, aLabel, aRewPill } do
			v.Visible = not compact
		end
		if compact then -- stack: ribbon, name, status pill, progress bar, reward boxes + action button
			at(aName, cx, 72)
			aName.Size = UDim2.fromOffset(W - 10, 34)
			Parts.fit(aName, W - 10, 28, 16)
			at(aPill.Frame, cx, 106)
			at(aBar.Frame, cx, 146)
			local y = 206
			for i, r in aRewards do
				if b.Rewards[i] then
					local rx = cx - 93 + (i - 1) * 76
					Draw.apply(r.box, Bag.StatRow, rx, y, 72, 66, BOX_K)
					local rec = Q[REWARD_ICON[b.Rewards[i].Name] or "Crystals"]
					local iw, ih = Draw.fitIn(rec, 34, 32)
					Draw.apply(r.icon, rec, rx, y - 10, iw, ih)
					r.text.Size = UDim2.fromOffset(68, 22)
					at(r.text, rx, y + 22)
					Parts.fit(r.text, 68, 16, 12)
				end
			end
			hit.Size = UDim2.fromOffset(112, 60)
			hit.Position = UDim2.fromOffset(cx + 79, y)
			visual.Size = UDim2.fromOffset(104, 56)
		end
	end

	function showMastery(m)
		local b = m.Body
		local W = body.Size.X.Offset
		local cx = W / 2
		local function sized(inst, rec, y: number, w: number)
			Draw.apply(inst, rec, cx, y, w, w * rec.Ink.Height / rec.Ink.Width)
		end
		local mw = math.min(262, W - 16)
		sized(mRibbon, Q.DetailRibbon, 36, mw)
		at(mRibbonText, cx, 33)
		mRibbonText.Size = UDim2.fromOffset(mw * 0.62, 40)
		mRibbonText.Text = m.Title or "DICE MASTERY"
		Parts.fit(mRibbonText, mRibbonText.Size.X.Offset, 24, 14)
		-- flame banners hang from both ribbon ends (the art is fire-themed for every die)
		local fh = 104 -- ref: ~60x105 at x +-150 from the centre, y 41..146 (clear of the ribbon tails)
		for _, f in { { mFlagL, Q.BannerFlameL, -1 }, { mFlagR, Q.BannerFlameR, 1 } } do
			local fw = fh * f[2].Ink.Width / f[2].Ink.Height
			Draw.apply(f[1], f[2], cx + f[3] * math.min(150, W / 2 - fw / 2 + 12), 93, fw, fh)
			f[1].Visible = not compact
		end
		local rayW, rayH = Draw.fitIn(Q.Rays, math.min(240, W - 20), if compact then 120 else 170)
		Draw.apply(mRays, Q.Rays, cx, if compact then 108 else 135, rayW, rayH)
		local hw, hh = Draw.fitIn(Q.Halo, if compact then 140 else 190, if compact then 51 else 69)
		Draw.apply(mHalo, Q.Halo, cx, if compact then 146 else 164, hw, hh)
		local drec = Q[b.Die] or Q.DieFire
		local dw, dh = Draw.fitIn(drec, if compact then 88 else 125, if compact then 90 else 127)
		Draw.apply(mDie, drec, cx, if compact then 104 else 129, dw, dh)
		local reach = math.min(112, W / 2 - 24)
		local sp = {
			{ Q.Sparkle1, -reach, -50, 36 },
			{ Q.Sparkle2, reach, -20, 40 },
			{ Q.Sparkle3, -reach + 14, 36, 18 },
			{ Q.Sparkle4, reach - 26, 44, 22 },
		}
		for i, s in sp do
			local sw, sh = Draw.fitIn(s[1], s[4], s[4])
			Draw.apply(mSparkles[i], s[1], cx + s[2], 129 + s[3], sw, sh)
			mSparkles[i].Visible = not compact
		end
		at(mName, cx, 206)
		mName.Size = UDim2.fromOffset(W - 10, 40)
		mName.Text = string.upper(m.Name or "")
		Parts.fit(mName, W - 10, 32, 18)
		mPill:Set(b.Level)
		at(mPill.Frame, cx, 248)
		if mBarW ~= math.min(321, W - 20) then
			mBarW = math.min(321, W - 20)
			if mBar then
				mBar.Frame:Destroy()
			end
			mBar = Mastery.bar(mastery, "XpBar", mBarW, 32, mz + 4, 20) -- ref digits cap ~14
		end
		at(mBar.Frame, cx, 291)
		mBar:Set(b.Xp, b.XpGoal)
		at(mDesc, cx, 342)
		mDesc.Size = UDim2.fromOffset(300, 48)
		mDesc.Text = b.Desc or ""
		mDesc.TextSize = Parts.fitSize(mDesc.Text, 300 * 2, 20, 13)
		sized(mDiv, Bag.DividerGold, 379, math.min(330, W))
		local nw = math.min(210, W)
		sized(mNext, Q.NextRewards, 412, nw)
		at(mNextText, cx, 412)
		mNextText.Size = UDim2.fromOffset(nw * 0.6, 30)
		Parts.fit(mNextText, nw * 0.6, 18, 12)
		local rewards = QuestLogic.nextRewards(b)
		local bxw = math.min(170, math.floor((W + 4) / 2))
		local bxh = bxw * Q.RewardBoxPlain.Ink.Height / Q.RewardBoxPlain.Ink.Width -- plain: the baked sparkles of RewardBox sat over the text
		local cy = 497
		for i, r in mRewards do
			local entry = rewards[i]
			for _, obj in r do
				obj.Visible = entry ~= nil
			end
			if entry then
				local rx = cx + (i - 1 - (#rewards - 1) / 2) * (bxw + 5)
				Draw.apply(r.box, Q.RewardBoxPlain, rx, cy, bxw, bxh)
				local irec = Q[entry.Icon] or Q.Crystals
				local iw, ih = Draw.fitIn(irec, 80, 80)
				Draw.apply(r.icon, irec, rx, cy - bxh * 0.2, iw, ih)
				r.name.Text = entry.Name
				r.name.Size = UDim2.fromOffset(bxw - 30, 22)
				at(r.name, rx, cy + bxh * 0.2)
				Parts.fit(r.name, bxw - 30, 20, 12)
				local lw, lh = Draw.fitIn(Bag.Lock, 18, 18)
				local gx = rx - (18 + 4 + 40) / 2 -- lock + "Lv. N" group centred in the box
				Draw.apply(r.pill, Bag.Search, rx, cy + bxh * 0.4, math.min(bxw - 24, 130), 28) -- ref: dark pill behind lock + Lv.
				Draw.apply(r.lock, Bag.Lock, gx + 9, cy + bxh * 0.4, lw, lh)
				r.lv.Text = "Lv. " .. entry.Lv
				r.lv.TextXAlignment = Enum.TextXAlignment.Left
				r.lv.TextSize = 19
				r.lv.Size = UDim2.fromOffset(44, 22)
				at(r.lv, gx + 18 + 4 + 22, cy + bxh * 0.4)
			end
		end
		for _, v in { mFlagL, mFlagR, mRays, mHalo, mDie, mDesc, mDiv } do
			v.Visible = not compact
		end
		if compact then -- stack: ribbon, name, level pill, XP bar, NEXT REWARDS and two small cards
			at(mName, cx, 70)
			mName.Size = UDim2.fromOffset(W - 10, 34)
			Parts.fit(mName, W - 10, 28, 16)
			at(mPill.Frame, cx, 104)
			at(mBar.Frame, cx, 140)
			sized(mNext, Q.NextRewards, 172, nw)
			at(mNextText, cx, 172)
			local cw = math.min(88, math.floor((W - 8) / 2))
			local ch = cw * Q.RewardBoxPlain.Ink.Height / Q.RewardBoxPlain.Ink.Width
			local cyc = 188 + ch / 2
			for i, r in mRewards do
				local entry = rewards[i]
				if entry then
					local rx = cx + (i - 1 - (#rewards - 1) / 2) * (cw + 5)
					Draw.apply(r.box, Q.RewardBoxPlain, rx, cyc, cw, ch)
					local irec = Q[entry.Icon] or Q.Crystals
					local iw, ih = Draw.fitIn(irec, 36, 34)
					Draw.apply(r.icon, irec, rx, cyc - 19, iw, ih)
					r.name.Size = UDim2.fromOffset(cw - 10, 18)
					at(r.name, rx, cyc + 8)
					Parts.fit(r.name, cw - 10, 14, 11)
					Draw.apply(r.pill, Bag.Search, rx, cyc + 27, cw - 12, 20)
					local lw, lh = Draw.fitIn(Bag.Lock, 14, 14)
					Draw.apply(r.lock, Bag.Lock, rx - 17, cyc + 27, lw, lh)
					r.lv.TextSize = 13
					r.lv.Size = UDim2.fromOffset(36, 18)
					at(r.lv, rx + 10, cyc + 27)
				end
			end
		end
	end

	function api:Show(model)
		current = model
		local kind = model and model.Kind
		placeholder.Visible = model == nil
		scroll.Visible = model ~= nil
		actions.Visible = model ~= nil
		quest.Visible, achievement.Visible, mastery.Visible = kind == "Quest", kind == "Achievement", kind == "Mastery"
		local ach = kind == "Achievement"
		local tall = ach or kind == "Mastery" -- no bottom action strip
		fitScroll()
		scroll.CanvasSize = UDim2.fromOffset(0, bodyH(kind))
		body.Size = UDim2.fromOffset(body.Size.X.Offset, bodyH(kind))
		if not ach then -- back in the bottom strip (the Achievement branch moves it into its reward row)
			hit.Parent = actions
			hit.ZIndex = actions.ZIndex + 1
			hit.Position = UDim2.fromScale(0.5, 0.5)
			placeAction()
		end
		if not model then
			return
		end
		scroll.CanvasPosition = Vector2.new(0, 0)
		if kind == "Quest" then
			showQuest(model)
		elseif ach then
			showAchievement(model)
		else
			showMastery(model)
		end
		local a = model.Action
		actions.Visible = a ~= nil and not tall
		hit.Visible = a ~= nil
		if a then
			Parts.setButton(visual, { Label = a.Label, Enabled = a.Enabled ~= false })
			local sparkOn = a.State == "Claim" and a.Enabled ~= false
			local aw, ah = Draw.fitIn(Q.Sparkle1, 30, 30)
			local mid = parent.Size.X.Offset / 2
			Draw.apply(sparkL, Q.Sparkle1, mid - (if compact then 116 else 140), actionH() / 2 - 12, aw, ah)
			Draw.apply(sparkR, Q.Sparkle2, mid + (if compact then 116 else 140), actionH() / 2 - 14, aw, ah)
			sparkL.Visible, sparkR.Visible = sparkOn, sparkOn
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
