-- Quest Log, QUESTS tab: sections (DAILY / WEEKLY / STORY) of quest rows in one ScrollingFrame with the Bag's styled scrollbar.
-- Quests.new(Slots.Grid) -> :SetRows(rows) :SetResetText(daily, weekly) :SetSelected(id) :OnSelect(cb(id)) :OnClaim(cb(id, row))
-- :SetEmptyText(s) :GetScroll() :SetScroll(n) :Destroy(). Visual only; rows come from QuestLogic.questRows (already filtered).
-- Design px. Row layout keys on the content width: full (>= 700), mid (360-700: desc hidden, rewards stacked), tiny (< 360: no rewards).

local UiKit = require(script.Parent.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parent.Parent.Bag.Parts)
local HudSprites = require(script.Parent.Parent.Parent.Sprites)
local QuestLogic = require(script.Parent.Parent.QuestLogic)
local Draw = require(script.Parent.Parent.Draw)

local make = UiKit.make
local Bag, Q = Draw.Bag, Draw.Q

local PAD_L, PAD_R, PAD_T, PAD_B = 14, 34, 2, 16 -- left/top >= the selected glow; right = scrollbar gutter
local ROW_H, GAP, HEAD_H = 60, 5, 54 -- ref: rows ~60 tall on a 65 pitch; ribbon top -> first row top 61
local COIN_TEXT = Color3.fromRGB(251, 243, 137)
local GOLD_HEX = "#FCD51A"
local GREEN_TEXT = Color3.fromRGB(120, 235, 90)
local SECTIONS = {
	{ Id = "Daily", Title = "DAILY QUESTS", Icon = Q.IconCalendar, Reset = true },
	{ Id = "Weekly", Title = "WEEKLY QUESTS", Icon = Q.IconCalendarWeek, Reset = true },
	{ Id = "Story", Title = "STORY QUESTS", Icon = Q.IconQuestScroll, Reset = false },
}
local BAR = { ScrollTrack = Rect.new(19, 65, 22, 227) } -- narrow centre column: no horizontal stretch

local function barSkin(inst, name: string, w: number)
	local s = Bag[name]
	inst.Image = s.Image
	inst.ScaleType = Enum.ScaleType.Slice
	inst.SliceCenter = BAR[name]
	inst.SliceScale = w / s.Size.X
end

local Quests = {}

function Quests.new(parent)
	local api, conns = {}, {}
	local rows, selected, onSelect, onClaim = {}, nil, nil, nil
	local resetText = { Daily = nil, Weekly = nil }
	local recs, heads = {}, {} -- recs[id] = { skin, w, h }; heads[sectionId] = { pill, label }
	local barW, mode = 21, "full"

	local root = make("Frame", {
		Name = "QuestsTab",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = parent.ZIndex,
	}, parent)
	local scroll = make("ScrollingFrame", {
		Name = "QuestScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 0, -- the styled bar below replaces the native one; wheel, touch and drag still scroll
		ScrollBarImageTransparency = 1, -- a 0-thickness bar still draws a 1 px hairline
		ZIndex = root.ZIndex + 1,
	}, root)
	local pad = make("UIPadding", {
		PaddingLeft = UDim.new(0, PAD_L),
		PaddingRight = UDim.new(0, PAD_R),
		PaddingTop = UDim.new(0, PAD_T),
		PaddingBottom = UDim.new(0, PAD_B),
	}, scroll)
	make("UIListLayout", { Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	local empty = Parts.text(root, {
		Name = "EmptyLabel",
		Text = "No quests yet",
		TextSize = 24,
		TextWrapped = true,
		TextColor3 = Color3.fromRGB(205, 210, 235),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -60, 0, 80),
		Visible = false,
		ZIndex = scroll.ZIndex + 1,
	})
	local track = Draw.img(root, {
		Name = "ScrollTrack",
		AnchorPoint = Vector2.new(1, 0),
		Visible = false,
		ZIndex = scroll.ZIndex + 2,
	})
	local thumb = Draw.img(track, { Name = "Thumb", ZIndex = track.ZIndex + 1 })

	local function updateBar()
		local h = parent.Size.Y.Offset
		local y, maxY = scroll.CanvasPosition.Y, math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
		track.Visible = maxY > 1 and h > 0
		local win, canvas = scroll.AbsoluteWindowSize.Y, math.max(1, scroll.AbsoluteCanvasSize.Y)
		local thumbH = math.clamp(math.floor(h * win / canvas), 40, math.max(40, h))
		Draw.thumb(thumb, barW, thumbH, math.floor((h - thumbH) * (if maxY > 0 then y / maxY else 0)))
	end
	table.insert(conns, scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(updateBar))
	table.insert(conns, scroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(updateBar))

	local function setReset(head, text: string?)
		head.group.Visible = text ~= nil and text ~= "" and head.fits
		if text and text ~= "" then
			head.label.Text = `Resets in: <font color="{GOLD_HEX}">{text}</font>`
			head.label.TextSize = Parts.fitSize("Resets in: " .. text, head.avail, 18, 12)
		end
	end

	local function buildHeader(sec, order: number, first: boolean, cw: number)
		local pre = if first then 0 else 17 -- ref: last row -> next ribbon top ~20
		local f = Draw.img(scroll, {
			Name = "Head_" .. sec.Id,
			LayoutOrder = order,
			Size = UDim2.fromOffset(cw, HEAD_H + pre),
		}, "Frame")
		local cy = pre + HEAD_H / 2
		local small = mode ~= "full"
		local bw = math.min(if small then 230 else 300, cw - 6)
		local bh = bw * Q.SectionBanner.Ink.Height / Q.SectionBanner.Ink.Width
		local banner = Draw.img(f, { Name = "Banner" })
		Draw.apply(banner, Q.SectionBanner, bw / 2, cy, bw, bh)
		local iconSize = if small then 44 else 56
		local icon = Draw.img(f, { Name = "Icon", ZIndex = banner.ZIndex + 2 })
		local iw, ih = Draw.fitIn(sec.Icon, iconSize, iconSize)
		Draw.apply(icon, sec.Icon, bw * 0.15, cy, iw, ih)
		local textL = bw * 0.15 + iconSize / 2 + 6
		local textW = bw - 0.1 * bw - textL
		local title = Parts.text(f, {
			Name = "Title",
			Text = sec.Title,
			TextSize = if small then 22 else 29, -- ref label cap ~19
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(math.floor(textL + textW / 2), math.floor(cy - 2)),
			Size = UDim2.fromOffset(textW, 40),
			ZIndex = banner.ZIndex + 1,
		}, 3)
		Parts.fit(title, textW, title.TextSize, 14)
		if sec.Reset then
			local pw = if small then 170 else 223 -- ref pill ~223 wide
			local group = Draw.img(f, { Name = "Reset", Size = UDim2.fromScale(1, 1), ZIndex = banner.ZIndex }, "Frame")
			local pill = Draw.img(group, { Name = "Pill" })
			Draw.apply(pill, Bag.Search, cw - pw / 2, cy, pw, 40)
			local sw = Draw.img(group, { Name = "Stopwatch", ZIndex = pill.ZIndex + 1 })
			local sww, swh = Draw.fitIn(Q.Stopwatch, 28, 28)
			Draw.apply(sw, Q.Stopwatch, cw - pw + 22, cy, sww, swh)
			local avail = pw - 56
			local label = Parts.text(group, {
				Name = "Resets",
				RichText = true,
				TextSize = 18,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(math.floor(cw - pw + 40 + avail / 2), cy),
				Size = UDim2.fromOffset(avail, 40),
				ZIndex = pill.ZIndex + 1,
			}, 2)
			-- the pill and the banner must not collide on narrow slots
			local head = { group = group, label = label, avail = avail, fits = cw - pw - bw >= 6 }
			heads[sec.Id] = head
			setReset(head, resetText[sec.Id])
		end
	end

	-- Row ----------------------------------------------------------------------------------------------------
	local function skinRow(rec, on: boolean)
		local ex = if on then 8 else 0
		Draw.apply(rec.skin, if on then Q.RowSelected else Q.Row, rec.w / 2, rec.h / 2, rec.w + ex, rec.h + ex)
	end

	local function buildRow(row, order: number, cw: number)
		local full, tiny = mode == "full", mode == "tiny"
		local state = QuestLogic.claimState(row)
		local btn = Draw.img(scroll, {
			Name = "Row_" .. row.Id,
			LayoutOrder = order,
			Size = UDim2.fromOffset(cw, ROW_H),
		}, "ImageButton")
		Parts.interact(btn)
		local skin = Draw.img(btn, { Name = "Skin" })
		local rec = { skin = skin, w = cw, h = ROW_H }
		recs[row.Id] = rec
		skinRow(rec, row.Id == selected)
		if state == "Claimed" then
			skin.ImageColor3 = Color3.fromRGB(200, 200, 200)
		end
		local z = skin.ZIndex + 1
		local cy = ROW_H / 2

		-- Right to left: claim, gem, coin, bar; the left column keeps the rest.
		local claimW, claimH = (if full then 97 elseif tiny then 48 else 72), (if full then 48 else 42)
		local right = cw - (if full then 5 else 6)
		local claimLeft = right - claimW
		local regionCx = claimLeft + claimW / 2
		if state == "Claim" or state == "Soon" then
			local hit = Draw.img(btn, {
				Name = "ClaimHit",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(regionCx, cy),
				Size = UDim2.fromOffset(claimW + 14, 56),
				ZIndex = z + 4,
			}, "ImageButton")
			Parts.interact(hit)
			local visual = Parts.button(hit, {
				Name = "Claim",
				Style = "Green",
				Label = if state == "Soon" then "SOON" else "CLAIM",
				TextSize = if full then 22 elseif tiny then 15 else 18,
				Enabled = state == "Claim",
				Size = UDim2.fromOffset(claimW + 3, claimH + 2),
			})
			visual.AnchorPoint = Vector2.new(0.5, 0.5)
			visual.Position = UDim2.fromScale(0.5, 0.5)
			visual.Interactable = false -- the transparent hit button above takes the tap (Active=false still swallows clicks)
			visual.Selectable = false
			hit.Activated:Connect(function()
				if onClaim then
					onClaim(row.Id, row)
				end
			end)
		elseif state == "Claimed" then
			local g = Draw.img(btn, { Name = "ClaimedCheck", ZIndex = z + 1 })
			local cw2, ch2 = Draw.fitIn(Bag.Check, 26, 26)
			local labelW = claimW - 26
			Draw.apply(g, Bag.Check, claimLeft + 13, cy, cw2, ch2)
			local l = Parts.text(btn, {
				Name = "ClaimedText",
				Text = "CLAIMED",
				TextSize = if full then 18 else 14,
				TextColor3 = GREEN_TEXT,
				TextXAlignment = Enum.TextXAlignment.Left,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(claimLeft + 30, cy),
				Size = UDim2.fromOffset(math.max(10, labelW + 18), 28),
				ZIndex = z + 1,
			}, 2)
			Parts.fit(l, l.Size.X.Offset, l.TextSize, 10)
		end

		local function reward(
			icon,
			text: string,
			color: Color3,
			cx: number,
			y: number,
			size: number,
			iconSize: number,
			tw: number?
		)
			local ic = Draw.img(btn, {
				Name = "RewardIcon",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(cx + iconSize / 2, y),
				Size = UDim2.fromOffset(iconSize, iconSize),
				Image = icon,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = z + 1,
			})
			local t = Parts.text(btn, {
				Name = "RewardText",
				Text = text,
				TextSize = size,
				TextColor3 = color,
				TextXAlignment = Enum.TextXAlignment.Left,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(cx + iconSize + 4, y),
				Size = UDim2.fromOffset(tw or (if full then 54 else 64), 28),
				ZIndex = z + 1,
			}, 2)
			Parts.fit(t, t.Size.X.Offset, size, 12)
			return ic
		end
		local gold = "+" .. QuestLogic.format(row.Gold or 0)
		local gems = if row.Gems then "+" .. QuestLogic.format(row.Gems) else nil
		local rewardLeft = claimLeft - 10
		local wide = row.Section ~= "Daily" and state ~= "Claim" and state ~= "Soon" and state ~= "Claimed"
		if full then
			-- ref: daily gem icon 79 left of CLAIM, coin 91 left of the gem; weekly rows (no button) gem at -96 from the edge, coin 118 left
			local gemL = if wide then cw - 96 else claimLeft - 79
			if gems then
				reward(HudSprites.Gem, gems, Color3.new(1, 1, 1), gemL, cy, 20, 32)
			end
			rewardLeft = gemL - (if wide then 118 else 91)
			reward(HudSprites.Coin, gold, COIN_TEXT, rewardLeft, cy, 20, 32)
			rewardLeft -= if wide then 17 else 10
		elseif not tiny then
			rewardLeft = claimLeft - 10 - 86
			reward(HudSprites.Coin, gold, COIN_TEXT, rewardLeft, cy - 14, 15, 24)
			if gems then
				reward(HudSprites.Gem, gems, Color3.new(1, 1, 1), rewardLeft, cy + 14, 15, 24)
			end
			rewardLeft -= 8
		else
			-- phone: the coin reward ends every row's bar line; the button column exists only when there is a button
			rewardLeft = if state == "Progress" then cw - 8 else claimLeft - 6
			reward(HudSprites.Coin, gold, COIN_TEXT, rewardLeft - 62, cy + 14, 13, 16, 40)
		end

		-- Left column: icon, name (+ desc), progress bar.
		local iconBox = if full then 56 elseif tiny then 24 else 44
		local icon = Draw.img(btn, { Name = "Icon", ZIndex = z + 1 })
		local iw, ih = Draw.fitIn(Q[row.Icon] or Q.IconQuestScroll, iconBox, math.min(52, iconBox))
		Draw.apply(
			icon,
			Q[row.Icon] or Q.IconQuestScroll,
			(if full then 18 else if tiny then 6 else 8) + iconBox / 2,
			cy,
			iw,
			ih
		)
		local textL = (if full then 18 else if tiny then 6 else 8) + iconBox + (if full then 19 else 8)
		local pct = QuestLogic.percent(row.Progress, row.Goal)
		local complete = row.Goal > 0 and row.Progress >= row.Goal
		local nameY, barW2, barH
		local colR
		if full then
			barW2, barH = if wide then 178 else 163, 27
			colR = rewardLeft - barW2 - 4
			local bar = Draw.bar(btn, "Progress", barW2, barH, z + 1)
			bar.Frame.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Frame.Position = UDim2.fromOffset(rewardLeft - 4 - barW2 / 2, cy + 1)
			bar:Set(pct, QuestLogic.progressText(row.Progress, row.Goal), complete)
			nameY = 19
		else
			barH = 18
			colR = rewardLeft
			barW2 = math.max(if tiny then 48 else 60, colR - textL - (if tiny then 64 else 0))
			local bar = Draw.bar(btn, "Progress", barW2, barH, z + 1)
			bar.Frame.AnchorPoint = Vector2.new(0, 0.5)
			bar.Frame.Position = UDim2.fromOffset(textL, cy + 14)
			bar:Set(
				pct,
				(
					if tiny
						then string.gsub(QuestLogic.progressText(row.Progress, row.Goal), " ", "")
						else QuestLogic.progressText(row.Progress, row.Goal)
				),
				complete
			)
			nameY = 17
		end
		local colW = math.max(40, colR - textL - 8)
		local name = Parts.text(btn, {
			Name = "Name",
			Text = row.Name,
			TextSize = if full then 24 else if tiny then 15 else 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(textL, nameY),
			Size = UDim2.fromOffset(colW, 26),
			ZIndex = z + 1,
		}, 2)
		Parts.fit(name, colW, name.TextSize, 12)
		if full then
			local desc = Parts.text(btn, {
				Name = "Desc",
				Text = row.Desc,
				TextSize = 18,
				TextXAlignment = Enum.TextXAlignment.Left,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(textL + 2, 43),
				Size = UDim2.fromOffset(colW, 22),
				ZIndex = z + 1,
			}, 2)
			Parts.fit(desc, colW, 18, 12)
		end
		btn.Activated:Connect(function()
			if onSelect then
				onSelect(row.Id, row)
			end
		end)
	end

	-- Rebuilds every section and row (counts are tiny); scroll offset is the controller's to keep.
	local function rebuild()
		for _, c in scroll:GetChildren() do
			if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
				c:Destroy()
			end
		end
		table.clear(recs)
		table.clear(heads)
		local W = parent.Size.X.Offset
		if W <= 0 then
			return
		end
		local padR = if W - PAD_L - PAD_R < 360 then 22 else PAD_R -- phone: a slimmer scrollbar gutter
		pad.PaddingRight = UDim.new(0, padR)
		local cw = W - PAD_L - padR
		mode = if cw >= 700 then "full" elseif cw >= 360 then "mid" else "tiny"
		barW = if cw >= 360 then 21 else 12
		track.Size = UDim2.fromOffset(barW, parent.Size.Y.Offset)
		track.Position = UDim2.new(1, if cw >= 360 then -7 else -6, 0, 0)
		scroll.Position = UDim2.fromOffset(0, if cw >= 360 then 0 else -10) -- phone: the list starts under the toolbar's free strip
		scroll.Size = UDim2.new(1, 0, 1, if cw >= 360 then 0 else 10)
		barSkin(track, "ScrollTrack", barW)
		local order, shown = 0, 0
		for _, sec in SECTIONS do
			local list = {}
			for _, row in rows do
				if row.Section == sec.Id then
					table.insert(list, row)
				end
			end
			if #list > 0 then
				order += 1
				buildHeader(sec, order, shown == 0, cw)
				shown += 1
				for _, row in list do
					order += 1
					buildRow(row, order, cw)
				end
			end
		end
		empty.Visible = #rows == 0
		updateBar()
	end
	table.insert(conns, parent:GetPropertyChangedSignal("Size"):Connect(rebuild))

	function api:SetRows(list)
		rows = list or {}
		rebuild()
	end
	function api:SetResetText(daily: string?, weekly: string?)
		resetText.Daily, resetText.Weekly = daily, weekly
		for id, head in heads do
			setReset(head, resetText[id])
		end
	end
	function api:SetSelected(id: string?)
		selected = id
		for rid, rec in recs do
			skinRow(rec, rid == id)
		end
	end
	function api:OnSelect(cb)
		onSelect = cb
	end
	function api:OnClaim(cb)
		onClaim = cb
	end
	function api:SetEmptyText(s: string)
		empty.Text = s
	end
	function api:GetScroll(): number
		return scroll.CanvasPosition.Y
	end
	function api:SetScroll(n: number)
		scroll.CanvasPosition = Vector2.new(0, n)
	end
	function api:SetVisible(on: boolean)
		root.Visible = on
	end
	function api:Destroy()
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
		root:Destroy()
	end
	return api
end

return Quests
