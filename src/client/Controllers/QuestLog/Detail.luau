-- Quest Log detail panel, one template for all three tabs: a scrolling body (kind-specific widgets) over one bottom action button.
-- Detail.new(Slots.Detail) -> :Show(model|nil) :OnAction(cb(state, model)) :Destroy
-- model = { Kind = "Quest" | "Achievement" | "Mastery", Title, Name, Icon (QuestSprites key), Action = { Label, State, Enabled }, Body }
--   Quest Body = { Desc, Progress, Goal, Gold, Gems? } (Gems nil hides the gems box). State = Claim | Claimed | Soon | Progress.
-- Only the Quest kind is built; the Achievement and Mastery frames below are empty, hidden branches to fill later.

local UiKit = require(script.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Bag.Parts)
local HudSprites = require(script.Parent.Parent.Sprites)
local QuestLogic = require(script.Parent.QuestLogic)
local Draw = require(script.Parent.Draw)

local make = UiKit.make
local Bag, Q = Draw.Bag, Draw.Q

local ACTION_H = 76 -- bottom strip: the button (64 box, ink ~61) stays put while the body scrolls
local BODY_H = 500
local BOX_H, BOX_K = 54, 0.55 -- StatRow boxes: visible height and rim scale
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
		Size = UDim2.new(1, 0, 1, -ACTION_H),
		CanvasSize = UDim2.fromOffset(0, BODY_H),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Color3.fromRGB(249, 199, 53),
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

	local function at(inst, x: number, y: number)
		inst.AnchorPoint = Vector2.new(0.5, 0.5)
		inst.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	end

	-- Quest kind --------------------------------------------------------------------------------------------
	local quest = Draw.img(body, { Name = "Quest", Size = UDim2.fromScale(1, 1) }, "Frame")
	local z = quest.ZIndex
	local rays = Draw.img(quest, { Name = "Rays", ImageTransparency = 0.3, ZIndex = z })
	local glow = Draw.img(quest, { Name = "Glow", ImageTransparency = 0.25, ZIndex = z + 1 })
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
			Size = UDim2.fromOffset(42, 42),
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
	local mastery = Draw.img(body, { Name = "Mastery", Size = UDim2.fromScale(1, 1), Visible = false }, "Frame")

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
		Size = UDim2.fromOffset(240, 64),
		ZIndex = actions.ZIndex + 1,
	}, "ImageButton")
	Parts.interact(hit)
	local visual = Parts.button(hit, {
		Name = "Claim",
		Style = "Green",
		Label = "CLAIM",
		TextSize = 32,
		Size = UDim2.fromOffset(228, 64),
	})
	visual.AnchorPoint = Vector2.new(0.5, 0.5)
	visual.Position = UDim2.fromScale(0.5, 0.5)
	visual.Active = false
	visual.Selectable = false
	table.insert(
		conns,
		hit.Activated:Connect(function()
			if onAction and current and current.Action then
				onAction(current.Action.State, current)
			end
		end)
	)

	local function layout()
		local slotW = parent.Size.X.Offset
		if slotW <= 0 then
			return
		end
		local W = slotW - 2 * (if slotW >= 380 then 40 else 14)
		body.Size = UDim2.fromOffset(W, BODY_H)
		body.Position = UDim2.fromOffset((slotW - W) / 2, 0)
		local cx = W / 2
		local rw = math.min(300, W)
		Draw.apply(ribbon, Q.DetailRibbon, cx, 36, rw, rw * Q.DetailRibbon.Ink.Height / Q.DetailRibbon.Ink.Width)
		at(ribbonText, cx, 33)
		ribbonText.Size = UDim2.fromOffset(rw * 0.62, 40)
		local rayW = math.min(260, W)
		Draw.apply(rays, Q.Rays, cx, 150, rayW, rayW * Q.Rays.Ink.Height / Q.Rays.Ink.Width)
		local gw, gh = Draw.fitIn(Bag.GlowLegendary, 190, 190)
		Draw.apply(glow, Bag.GlowLegendary, cx, 136, gw, gh)
		local function spark(i: number, rec, dx: number, dy: number, size: number)
			local sw, sh = Draw.fitIn(rec, size, size)
			Draw.apply(sparkles[i], rec, cx + dx, 136 + dy, sw, sh)
		end
		local reach = math.min(112, W / 2 - 24)
		spark(1, Q.Sparkle1, -reach, -52, 38)
		spark(2, Q.Sparkle2, reach, -14, 42)
		spark(3, Q.Sparkle3, -reach + 20, 30, 18)
		spark(4, Q.Sparkle4, reach - 34, 38, 22)
		at(name, cx, 216)
		name.Size = UDim2.fromOffset(W - 10, 46)
		Draw.apply(divider, Bag.DividerGold, cx, 252, rw, rw * Bag.DividerGold.Ink.Height / Bag.DividerGold.Ink.Width)

		local function box(inst, x: number, y: number, w: number, h: number)
			Draw.apply(inst, Bag.StatRow, x, y, w, h, BOX_K)
		end
		box(objBox, cx, 276 + BOX_H / 2, W, BOX_H)
		at(objPill, cx, 276)
		at(objText, cx, 276 + BOX_H / 2 + 2)
		objText.Size = UDim2.fromOffset(W - 28, BOX_H - 10)
		box(progBox, cx, 352 + BOX_H / 2, W, BOX_H)
		at(progPill, cx, 352)
		at(rewPill, cx, 428)
		if barW ~= W - 24 then
			barW = W - 24
			if bar then
				bar.Frame:Destroy()
			end
			bar = Draw.bar(quest, "ProgressBar", barW, 30, z + 4)
			at(bar.Frame, cx, 352 + BOX_H / 2 + 2)
		end
		if current and current.Kind == "Quest" then
			showQuest(current)
		end
	end
	table.insert(conns, parent:GetPropertyChangedSignal("Size"):Connect(layout))
	layout()

	function showQuest(m)
		local b = m.Body
		ribbonText.Text = m.Title or "QUEST DETAILS"
		Parts.fit(ribbonText, ribbonText.Size.X.Offset, 26, 16)
		name.Text = m.Name or ""
		Parts.fit(name, name.Size.X.Offset, 38, 22)
		local rec = Q[m.Icon] or Q.IconQuestScroll
		local iw, ih = Draw.fitIn(rec, 130, 112)
		Draw.apply(icon, rec, body.Size.X.Offset / 2, 136, iw, ih)
		objText.Text = b.Desc or ""
		objText.TextSize = Parts.fitSize(objText.Text, objText.Size.X.Offset * 1.8, 22, 15)
		local pct = QuestLogic.percent(b.Progress, b.Goal)
		bar:Set(pct, QuestLogic.progressText(b.Progress, b.Goal), b.Goal > 0 and b.Progress >= b.Goal)
		-- Rewards: two boxes; the gems box is hidden for real rows and the gold box then centres.
		local W = body.Size.X.Offset
		local cellW = math.floor((W - 8) / 2)
		local hasGems = b.Gems ~= nil
		local cy = 428 + 33
		local function cell(boxInst, ic, text, label: string, cx: number, w: number)
			Draw.apply(boxInst, Bag.StatRow, cx, cy, w, 66, BOX_K)
			local iconRight = cx - w / 2 + 14 + 42
			local textW = (cx + w / 2 - 12) - (iconRight + 6)
			text.Text = label
			text.Size = UDim2.fromOffset(textW, 40)
			Parts.fit(text, textW, 26, 14)
			at(ic, iconRight - 21, cy)
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

	function api:Show(model)
		current = model
		local kind = model and model.Kind
		placeholder.Visible = model == nil
		scroll.Visible = model ~= nil
		actions.Visible = model ~= nil
		quest.Visible, achievement.Visible, mastery.Visible = kind == "Quest", kind == "Achievement", kind == "Mastery"
		if not model then
			return
		end
		scroll.CanvasPosition = Vector2.new(0, 0)
		if kind == "Quest" then
			showQuest(model)
		else
			-- TODO(achievements, mastery tabs): build and fill the `achievement` / `mastery` frames, one branch per kind.
			placeholder.Visible = false
		end
		local a = model.Action
		actions.Visible = a ~= nil
		if a then
			Parts.setButton(visual, { Label = a.Label, Enabled = a.Enabled ~= false })
			local sparkOn = a.State == "Claim" and a.Enabled ~= false
			local aw, ah = Draw.fitIn(Q.Sparkle1, 30, 30)
			local mid = parent.Size.X.Offset / 2
			Draw.apply(sparkL, Q.Sparkle1, mid - 140, ACTION_H / 2 - 12, aw, ah)
			Draw.apply(sparkR, Q.Sparkle2, mid + 140, ACTION_H / 2 - 14, aw, ah)
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
