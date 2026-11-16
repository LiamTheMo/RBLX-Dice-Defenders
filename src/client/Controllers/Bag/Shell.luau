-- Bag shell: the one window every tab shares (banner, close, tab bar, panel slots) plus Fit(). Visual only.
-- Design px under one UIScale. Switching tabs never touches anything here except the tab sprites.
-- Shell.new(parent, { fit = () -> { leftReal, bottomTopReal } }) -> shell (see :methods below).
-- Optional deps for other menus (defaults = the Bag): name, banner { text, textW, emblems = { { sprite = record or id, box = {x, y, w, h}, side = true } } } (x/y/w/h = fractions of the scroll ink; the scroll and the
-- gem pin and the title size/height (TITLE) are the same for every menu; a title that does not fit the parchment's flat band
-- (with its side emblem) shrinks to fit; textW = the label's minimum width as a scroll-ink fraction; the title is centred on the parchment's height; the emblem flagged side (at most one)
-- sits left of the title at the title's centre height and the pair is centred on the scroll, its box x/y are ignored), detail (sprite key or record), fullDetail (detail panel as tall as the left one),
-- free (no tabs or panels: one Slots.Content box from freeTop; window, banner and close run the same code as the Bag),
-- tabIconScale (tab icon box multiplier, default 1), tabW (tabs keep this design-px width instead of stretching (compact: scaled with the tab height, and shrunk to leave deps.tabReserve design px free in the row);
-- the tab bar keeps the Bag's span so another child with a high LayoutOrder shares the row; a tab without Icon centres its label;
-- free mode with tabs puts Content under the tab bar).
-- Opt-in banner options (default = unchanged): banner.noGem = true skips the gem pin; an emblem box (also the side emblem's) may be { full = box, compact = box } to size the emblem per tier.
-- Opt-in popup (free mode): size = Vector2 visible window ink at the Full tier (design px); the scroll-to-window-bottom group is centred on the screen
-- inside the free region; phones keep the Compact banner / X / rim and shrink the window and Content uniformly (Content = the Full free box x k); the chrome is two crossfaded 1:1 copies of the Window art.
-- Opt-in popupScale (number, default 1; popup + Full tier only, ignored on phones): multiplies the real scale of the whole popup group (banner, X, rim, window, content) so it shrinks in proportion.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UiKit = require(script.Parent.Parent.UiKit)
local Parts = require(script.Parent.Parts)
local SettingsLogic = require(script.Parent.Parent.Settings.SettingsLogic)
local PlaySprites = require(script.Parent.Parent.Play.PlaySprites) -- the shared banner art (ScrollBase, GemPin) is cut by slice_play.py

local make = UiKit.make
local Z = 20 -- Bag root; Sibling ZIndex (descendants always >= their parent)

-- Window frame (excluding the banner overhang). Full tier = the 1672x941 reference: rim box 1248x761 (x 212, y 97)
-- plus the sprite's transparent margin mx/my. Compact (phones) shrinks to the space. mx/my double as offsets.
-- rim = Window SliceScale (1.0: orange band ~16 px as in the reference; corner radius ~38 vs 45, the art's limit).
local TIER = {
	Full = {
		mx = 6,
		my = 5,
		rim = 1.0,
		over = 86, -- layout only: banner top to window frame top
		inkW = 488.5, -- banner scroll ink width, and its centre y below the window box top
		inkCy = -0.8,
		tabTop = 41.8, -- from the rim box top (all Full values below are rim-box relative)
		tabH = 75.5, -- visible tab body 64 tall (sprite margin + shadow ~13% of the box)
		tabGap = -0.8, -- box gap (the tab sprite shows ~20 px less than its box in width): visible gap 17-18
		icon = 54.5, -- visible 52x52
		iconGap = 17, -- 19 px visible icon to label
		tabText = 34,
		side = 28.5, -- window box edge to panels (visible panel rim 11 px from the band)
		gap = 3, -- panel boxes overlap their transparent margins: visible rim gap 11
		detailCut = -6, -- both panels reach the window's content bottom on every tab (Dice: level with the footer strip's bottom rim, 830)
		detailInset = 35, -- detail slot ends above the panel bottom: action row top ~688
		contentTop = 119.5,
		freeTop = 59, -- free mode (no tab bar): content top, the Play reference's columns at y 156
		bottomPad = 32, -- + my: content bottom to window box bottom (rim inner edge 10 px below the content)
		pitch = 142,
	},
	Compact = {
		mx = 0,
		my = 1,
		rim = 0.78,
		over = 46,
		inkW = 220,
		inkCy = -5.6,
		tabText = 24,
		tabTop = 30,
		tabH = 56,
		tabGap = 8,
		icon = 30,
		iconGap = 6,
		side = 27,
		gap = 10,
		detailCut = 0,
		detailInset = 8,
		contentTop = 92,
		freeTop = 38,
		bottomPad = 16,
		pitch = 120,
	},
}
local SB, GEM = PlaySprites.ScrollBase, PlaySprites.GemPin
local TITLE = { -- banner title: font size and outline per tier
	Full = { size = 64, stroke = 5 },
	Compact = { size = 19, stroke = 2 }, -- 2: the counters of O / R / A stay open at 15 real px
}
local TITLE_Y = 0.512 -- title centre height (scroll-ink fraction) = the centre of the scroll's visible parchment
-- Banner group = the side emblem's ink + SIDE_GAP + the title's outline (fill + stroke), centred on the scroll; design px.
local SIDE_GAP = { Full = 12, Compact = 10 } -- side emblem ink to title outline (the Bag's crowned die stays >= 3 px off the gem pin wing)
local FLAT_L, FLAT_R, FLAT_MARGIN = 99, 700, 8 -- the parchment's cream (ScrollBase sprite px, between the rolled ends); the group keeps FLAT_MARGIN design px off its ends
-- Fredoka One side bearings (x the real text size R) of the first / last letter of the titles in use: the white fill's ink edge to the
-- text box edge, MEASURED on native captures (no QA scale) of every menu at several viewport sizes (mean over the sizes; the hinted
-- glyph edges move by up to 0.5 px with R, which is the model's accuracy). FILL_EDGE = real px by which the fill's thresholded edge
-- sits inside the outline's stroke (stroke edge - fill edge minus the stroke thickness, measured the same way).
local FILL_EDGE = 0.35
local BEARING = 0.035
local BEARING_L = { B = 0.042, Q = 0.028, P = 0.037, R = 0.042, S = 0.024 }
local BEARING_R = { G = 0.0315, Y = 0.020, L = 0.034, P = 0.029 }
local GEM_BOX = { 0.4261, 0.787, 0.1488, 0.3167 } -- >= 2 REAL px under the title's outline (UIScale 0.8: 2.5 design px)
local GAP = 10 -- vertical gap left panel to footer
local FULL_INK = Vector2.new(1251, 770) -- window box minus the transparent mx/my margin: visible rim 213-1459 x 98-861
local TAB_W = { 278.3, 299.3, 280.3, 314.3 } -- full-tier box widths for 4 tabs: visible 265 / 286 / 267 / 301 as in the ref
local TOOLBAR_H, FOOTER_H = 68, 97
local FOOTER_BOX = Vector2.new(786, 111) -- footer strip box: visible 242-1018 x 734-832 (slice-scale-0.69 margins: 4 left, 6 right, 3 top, 10 bottom)
local GRID_INSET = 12 -- GridScroll stops this far above the panel bottom so peeking cards clip inside the rim
local DETAIL_MAX, DETAIL_MIN = 420, 310
local MIN_SCALE, MAX_SCALE = 0.8, 1.5
local WINDOW_ART = require(script.Parent.BagSprites).Window -- popups draw it as two edge halves (popupChrome)

local Shell = {}
Shell.__index = Shell

function Shell.new(parent, deps)
	local self = setmetatable({}, Shell)
	local conns = {}
	self._conns, self._deps = conns, deps
	self._tab, self._tabs, self._tabButtons = 0, {}, {}
	self._onTab, self._onClose = {}, {}

	local rootName = deps.name or "Bag"
	local bn = deps.banner or {}
	local bag = make("Frame", {
		Name = rootName,
		BackgroundTransparency = 1,
		Active = false,
		Visible = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z,
	}, parent)
	local scaled = make("Frame", { Name = "Scaled", BackgroundTransparency = 1, ZIndex = Z }, bag)
	local uiScale = make("UIScale", { Name = rootName .. "Scale" }, scaled)
	local window = make("Frame", {
		Name = "Window",
		BackgroundTransparency = 1,
		Active = true, -- sinks clicks on the window only
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = Z + 1,
	}, scaled)
	local pop = make("UIScale", { Name = "Pop" }, window)
	self.Bag, self.Scaled, self.Window, self._uiScale, self._pop = bag, scaled, window, uiScale, pop

	local function frame(name, par, z)
		return make("Frame", { Name = name, BackgroundTransparency = 1, ZIndex = z }, par)
	end

	local chrome = make("ImageLabel", {
		Name = "Chrome",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z + 1,
	}, window)
	Parts.skin(chrome, "Window", TIER.Full.rim)
	self.Chrome = chrome

	-- Popup chrome: the Window art is wider than a popup, and a squeezed 9-slice centre samples a blurrier mip than the 1:1 corners
	-- (a step on the rim where they meet). Instead the whole art twice at the rim scale (every column 1:1, sliced vertically only),
	-- the left copy anchored left, the right copy right, crossfaded in two steps around the middle c: the right copy fades in over
	-- [c - BLEND, c] above the opaque left copy, then the left copy fades out under the opaque right copy over [c, c + BLEND]. Opaque
	-- rows never thin and the anti-aliased outer edge changes smoothly (a hard clip or one shared band steps or double-counts it).
	-- ImageRectOffset + Slice and 0-width slice caps both draw wrongly.
	local BLEND = 48
	local artL, artR
	local function band(u0: number, u1: number, from: number, to: number)
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, from),
			NumberSequenceKeypoint.new(u0, from),
			NumberSequenceKeypoint.new(u1, to),
			NumberSequenceKeypoint.new(1, to),
		})
	end
	local function popupChrome(w: number, rim: number)
		local aw = math.max(WINDOW_ART.Size.X * rim, w / 2 + 2 * BLEND)
		if not artL then
			chrome.ImageTransparency = 1
			local function copy(name, z)
				local img = make("ImageLabel", {
					Name = name,
					BackgroundTransparency = 1,
					Image = WINDOW_ART.Image,
					ScaleType = Enum.ScaleType.Slice,
					SliceCenter = WINDOW_ART.Slice,
					ZIndex = z,
				}, chrome)
				make("UIGradient", {}, img)
				return img
			end
			artL = copy("ChromeL", Z + 1)
			artR = copy("ChromeR", Z + 2) -- above the left copy, below the content (Z + 3 and up)
			artR.AnchorPoint, artR.Position = Vector2.new(1, 0), UDim2.fromScale(1, 0)
		end
		for _, half in { artL, artR } do
			half.Size = UDim2.new(0, aw, 1, 0)
			half.SliceScale = rim
		end
		local c, o = w / 2, w - aw -- the joint, and the right copy's left edge (window design px)
		artL.UIGradient.Transparency = band(c / aw, (c + BLEND) / aw, 0, 1)
		artR.UIGradient.Transparency = band((c - BLEND - o) / aw, (c - o) / aw, 1, 0)
	end

	-- Content: left column (toolbar, grid, footer) + detail; free mode: the bare content box only.
	local free = deps.free
	local content = frame("Content", window, Z + 2)
	self.Content, self.Slots = content, { Content = content }
	local left, leftPanel, toolbar, grid, footer, detail, detailSlot
	if not free then
		left = frame("Left", content, Z + 3)
		leftPanel = make("ImageLabel", {
			Name = "LeftPanel",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = Z + 2,
		}, left)
		Parts.skin(leftPanel, "LeftPanel", 0.5)
		toolbar = frame("Toolbar", left, Z + 5)
		grid = frame("Grid", left, Z + 3)
		footer = frame("Footer", left, Z + 14) -- above grid and detail (Global ZIndex gui); below popups (45)
		detail = make("ImageLabel", {
			Name = "Detail",
			BackgroundTransparency = 1,
			ZIndex = Z + 2,
		}, content)
		Parts.skin(detail, deps.detail or "Detail", 0.5)
		detailSlot = frame("Slot", detail, Z + 3)
		detailSlot.Size = UDim2.fromScale(1, 1)
		self.LeftPanel, self.Left = leftPanel, left
		self.Slots = { Toolbar = toolbar, Grid = grid, Footer = footer, Detail = detailSlot }
		self._detail = detail
	end

	-- Tab bar.
	local tabBar = frame("TabBar", window, Z + 3)
	tabBar.AnchorPoint = Vector2.new(0.5, 0)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tabBar)
	self.TabBar = tabBar

	-- Banner: the shared blank scroll + gem pin, the menu's emblems on top, then its title text (all children, Scale-placed).
	local banner = make("ImageLabel", {
		Name = "Banner",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = Z + 10,
	}, window)
	Parts.skin(banner, SB)
	local sbInk =
		{ SB.Ink.Min.X / SB.Size.X, SB.Ink.Min.Y / SB.Size.Y, SB.Ink.Width / SB.Size.X, SB.Ink.Height / SB.Size.Y }
	local placers, sideEmblem = {}, nil
	local function addEmblem(sprite, box, isSide)
		local tiered = box.full ~= nil
		local e = make("ImageLabel", { Name = "Emblem", BackgroundTransparency = 1, ZIndex = Z + 11 }, banner)
		Parts.image(e, sprite)
		local function place(b, ovX, cy) -- ovX / cy (banner fractions of the ink box's left edge and centre height) override the box
			local x, y, w, h = b[1], b[2], b[3], b[4] -- scroll-ink fractions
			x, y, w, h = sbInk[1] + x * sbInk[3], sbInk[2] + y * sbInk[4], w * sbInk[3], h * sbInk[4] -- banner fractions
			x, y = ovX or x, if cy then cy - h / 2 else y
			if type(sprite) == "table" then -- draw by ink: the sprite's transparent margin extends the box
				local r = sprite
				local ix, iy, iw, ih =
					r.Ink.Min.X / r.Size.X, r.Ink.Min.Y / r.Size.Y, r.Ink.Width / r.Size.X, r.Ink.Height / r.Size.Y
				x, y, w, h = x - ix / iw * w, y - iy / ih * h, w / iw, h / ih
			end
			e.Position, e.Size = UDim2.fromScale(x, y), UDim2.fromScale(w, h)
		end
		if isSide then
			sideEmblem = { place = place, box = box }
		elseif tiered then
			table.insert(placers, function(compact)
				place(if compact then box.compact else box.full)
			end)
		else
			place(box)
		end
	end
	if not bn.noGem then
		addEmblem(GEM, GEM_BOX)
	end
	for _, e in bn.emblems or {} do
		addEmblem(e.sprite, e.box, e.side)
	end
	local bannerText = Parts.text(banner, {
		Name = "Text",
		Text = bn.text or "BAG",
		TextTruncate = Enum.TextTruncate.None,
		AnchorPoint = Vector2.new(0, 0.5), -- left-aligned: the ink starts at the box edge + the letter's bearing at the rendered (fractional) size
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = Z + 12,
	}, 5)
	local bannerStroke = bannerText:FindFirstChildOfClass("UIStroke")
	self.Banner = banner

	local close = make("ImageButton", {
		Name = "Close",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(72, 68),
		ZIndex = Z + 11,
	}, window)
	Parts.skin(close, "Close")
	Parts.interact(close)
	table.insert(
		conns,
		close.Activated:Connect(function()
			self:Close()
		end)
	)
	self.CloseButton = close
	local closeHit -- popupScale only: a transparent child that keeps the X >= 44 real px when the popup is drawn smaller
	if deps.popupScale then
		closeHit = make("TextButton", {
			Name = "Hit",
			BackgroundTransparency = 1,
			Text = "",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = Z + 12,
			Selectable = false, -- the X stays the one gamepad stop
		}, close)
		-- Hit covers the X, so its hover/press drives the X's own feedback (Parts.interact reads DebugState)
		UiKit.wire(closeHit, function(state)
			close:SetAttribute("DebugState", if state == "Normal" then nil else state)
		end)
		table.insert(
			conns,
			closeHit.Activated:Connect(function()
				self:Close()
			end)
		)
	end

	-- Fit ------------------------------------------------------------------------------------------------
	local function fit()
		local size = UiKit.screenSize(parent)
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local ins = deps.fit()
		local phone = size.Y < UiKit.PHONE_H
		local availW = size.X - 2 * (ins.leftReal + if phone then 8 else 6)
		local vpad = if phone then 0 else 4 -- the window box may reach the bag row: its bottom margin is transparent
		local availH = ins.bottomTopReal - 10 + vpad -- region [4, bottomTop - 6 + vpad]
		local full = TIER.Full
		local fullW, fullH = FULL_INK.X + 2 * full.mx, FULL_INK.Y + 2 * full.my
		local bs = math.clamp(math.min(availW / fullW, availH / (fullH + full.over)), MIN_SCALE, MAX_SCALE)
		-- Settings UI Scale: Full tier only, es = bs at 100% (design layout below still uses bs)
		local es = if size.Y < UiKit.PHONE_H then bs else bs * (SettingsLogic.get("uiScale") / 100)
		-- Opt-in popupScale (popup, Full tier only): the whole group is drawn at es x ps; the layout (pk, fit test) still uses es
		local ps = if deps.popupScale and deps.size and size.Y >= UiKit.PHONE_H then deps.popupScale else 1
		local eff = es * ps -- real px per design px (= es when the option is absent)
		uiScale.Scale = eff
		scaled.Size = UDim2.fromScale(1 / eff, 1 / eff)
		local dw, dh = availW / bs, availH / bs -- design px that remain

		-- Tier: compact only for phone-class heights (as the HUD's 500 px rule); desktops stay full and the
		-- grid shows fewer rows (min about one row plus a peek) instead.
		local compact = size.Y < UiKit.PHONE_H
		local t = if compact then TIER.Compact else TIER.Full
		local hf = if compact then math.clamp(dh - t.over, 250, 725) else math.clamp(dh - t.over, 440, fullH)
		local winW = math.min(if compact then 1160 else fullW, dw)
		local side = t.side
		local inner = winW - 2 * side
		local gap = t.gap
		local cols = math.clamp(math.floor((inner - gap - DETAIL_MIN - 10) / t.pitch), 2, 5)
		local leftW = cols * t.pitch + 10
		local detailW = math.min(DETAIL_MAX, inner - gap - leftW)
		if detailW == DETAIL_MAX then
			leftW = inner - gap - detailW -- spare width goes to the grid panel (the grid centres its cards)
		else
			winW = 2 * side + gap + leftW + detailW
		end
		local contentTop = (if free and #self._tabs == 0 then t.freeTop else t.contentTop) + t.my
		local bottomPad = t.bottomPad + (if compact then 0 else t.my)
		local contentH = hf - contentTop - bottomPad
		-- Left column is one box on every tab: the panel fills it, minus the footer strip when the Dice footer shows
		-- (compact: the footer overlays the panel bottom).
		local cut = if deps.fullDetail then 0 else t.detailCut
		local bump = if not compact and self._footerOn then 8 else 0 -- dice: panel bottom rim reaches the ref (gap to the footer 6)
		local leftH = if compact
			then contentH
			elseif self._footerOn then contentH - FOOTER_H - GAP + bump
			else contentH - cut

		local box = deps.size and Vector2.new(deps.size.X + 2 * full.mx, deps.size.Y + 2 * full.my)
		local pk, gTop = 1, 0 -- popup: window scale, and the scroll's ink top above the window box (design px)
		if box then
			-- headroom above the window box: the scroll's ink top; phones reserve the other menus' banner room (their banner top)
			gTop = if compact then t.over else SB.Ink.Height / 2 * t.inkW / SB.Ink.Width - t.inkCy
			-- shrink uniformly whenever the group does not fit the free region (phones, and short desktop windows at the 0.8 floor)
			pk = math.min(1, ((ins.bottomTopReal - 12 + vpad) / es - gTop) / (box.Y - full.my), availW / es / box.X)
			winW, hf, side = box.X * pk, box.Y * pk, full.side * pk
			contentTop = (full.freeTop + full.my) * pk
			contentH = (box.Y - full.freeTop - full.bottomPad - 2 * full.my) * pk
		end

		-- Window centred in the free region.
		local compH = (t.over + hf) * bs
		-- Free height sits above the window (the bag row is anchored to the screen bottom): the window stays under it
		local spare = (ins.bottomTopReal - 8 + vpad) - 4 - compH
		local top = 4 + (if compact or spare < 0 then spare / 2 else spare)
		window.Size = UDim2.fromOffset(winW, hf)
		if box then -- popup: the group (scroll ink top .. window ink bottom) centred on the screen, kept inside [4, bottomTop - 8 + vpad]
			local lo, hi = 4, ins.bottomTopReal - 8 + vpad
			local up, down = (hf / 2 + gTop) * eff, (hf / 2 - full.my * pk) * eff
			-- phones fill the region exactly (pk), so the bounds can cross by a rounding error: max/min, not math.clamp
			local cy = if up + down > hi - lo
				then lo + (hi - lo - up - down) / 2 + up
				else math.max(lo + up, math.min(size.Y / 2 + (up - down) / 2, hi - down))
			window.Position = UDim2.fromScale(0.5, cy / size.Y) -- a scale: offsets snap to whole design px (0.8 real px at the floor)
			popupChrome(window.Size.X.Offset, t.rim)
		else
			window.Position = UDim2.new(0.5, 0, 0, (top + t.over * bs + hf * bs / 2) / es)
		end
		chrome.SliceScale = t.rim

		content.Position = UDim2.fromOffset(side, contentTop)
		content.Size = UDim2.fromOffset(winW - 2 * side, contentH)
		if not free then -- the Bag / Quest Log panels (free mode has only the content box)
			left.Size = UDim2.fromOffset(leftW, contentH)
			-- Full: the panel rim shows 1 px in from its box on the left and 3 px on the right (visible 239-1012)
			leftPanel.Position = UDim2.fromOffset(if compact then 0 else 1, 0)
			leftPanel.Size = UDim2.fromOffset(if compact then leftW else leftW + 2, leftH)
			toolbar.Size = UDim2.fromOffset(leftW, TOOLBAR_H)
			grid:SetAttribute("FooterInset", FOOTER_H + GAP - cut) -- Cosmetics sizes its cards as if the Dice footer were shown
			grid.Position = UDim2.fromOffset(3, TOOLBAR_H)
			grid.Size = UDim2.fromOffset(leftW - 6, leftH - bump - TOOLBAR_H - GRID_INSET)
			-- Compact: an overlay (own strip background) over the panel bottom, wide enough for 5 slots + button;
			-- the controller decides when it is visible (Footer:SetVisible).
			if compact then
				footer.Position = UDim2.fromOffset(0, contentH - FOOTER_H)
				footer.Size = UDim2.fromOffset(leftW, FOOTER_H)
			else
				-- FOOTER_BOX is the reference-frame size; a narrower window narrows the left column, so the strip
				-- loses the same width (else it runs over the detail panel).
				local fullLeftW = fullW - 2 * side - gap - DETAIL_MAX
				-- Strip rim lines up with the left panel's (its box margins are 4 left / 6 right) and ends level with the
				-- detail panel's bottom rim.
				footer.Position = UDim2.fromOffset(-1, contentH + 8 - (FOOTER_BOX.Y - 2))
				footer.Size = UDim2.fromOffset(FOOTER_BOX.X - math.max(0, fullLeftW - leftW) + 2.5, FOOTER_BOX.Y - 2)
			end
			local detailH = contentH - cut
			detail.Position = UDim2.fromOffset(leftW + gap, 0)
			detail.Size = UDim2.fromOffset(detailW, detailH)
			detailSlot.Size = UDim2.fromOffset(detailW, detailH - t.detailInset) -- offsets: Parts read slot widths in design px
		end
		for _, slotFrame in self.Slots do
			slotFrame:SetAttribute("Compact", compact)
		end
		self.Compact = compact

		local k = t.inkW / SB.Ink.Width -- sprite px -> design px
		banner.Position = UDim2.new(0.5, 0, 0, t.inkCy - (SB.Ink.Min.Y + SB.Ink.Max.Y) / 2 * k)
		banner.Size = UDim2.fromOffset(SB.Size.X * k, SB.Size.Y * k)
		local title = if compact then TITLE.Compact else TITLE.Full
		for _, place in placers do
			place(compact)
		end
		bannerStroke.Thickness = title.stroke
		local bannerW = banner.Size.X.Offset
		local cy = sbInk[2] + TITLE_Y * sbInk[4]
		-- the group (side emblem ink .. title outline) is centred on the scroll; the title takes the largest size
		-- (<= title.size) at which the group stays inside the parchment's flat band
		local str = bannerText.Text
		local lead = 0 -- emblem ink + gap in front of the title outline
		local sideBox = sideEmblem
			and (
				if sideEmblem.box.full
					then (if compact then sideEmblem.box.compact else sideEmblem.box.full)
					else sideEmblem.box
			)
		if sideEmblem then
			lead = sideBox[3] * sbInk[3] * bannerW + SIDE_GAP[if compact then "Compact" else "Full"]
		end
		local flatW = (FLAT_R - FLAT_L) * k - 2 * FLAT_MARGIN
		-- The engine draws text at the integer size floor(TextSize x UIScale) (measured: ink widths step at integer logical sizes, and the
		-- TextBounds equal the layout at that size), so the model works in real px at R and divides by the scale
		local bl0, br0 = BEARING_L[str:sub(1, 1)] or BEARING, BEARING_R[str:sub(-1)] or BEARING
		local function realSize(sz)
			return math.floor(sz * eff)
		end
		local function strokeReal() -- the stroke's real thickness plus the white fill's visible edge sitting inside the glyph edge
			return title.stroke * eff + FILL_EDGE
		end
		local function outWidth(sz) -- design px
			local r = realSize(sz)
			return (Parts.measure(str, r) - (bl0 + br0) * r + 2 * strokeReal()) / eff
		end
		local ts = title.size
		while ts > 12 and lead + outWidth(ts) > flatW do
			ts -= 1
		end
		bannerText.TextSize = ts
		local outW = outWidth(ts)
		local rs = realSize(ts)
		local groupLeft = (sbInk[1] + sbInk[3] / 2) * bannerW - (lead + outW) / 2
		if sideEmblem then
			sideEmblem.place(sideBox, groupLeft / bannerW, cy)
		end
		bannerText.Position = UDim2.fromScale((groupLeft + lead + (strokeReal() - bl0 * rs) / eff) / bannerW, cy)
		bannerText.Size = UDim2.new(
			0,
			math.max((bn.textW or 0.5) * sbInk[3] * bannerW, Parts.measure(str, rs) / eff + 2 * title.stroke + 4),
			0,
			math.ceil(ts * 1.2)
		)
		-- ~85% of the reference X (visible 74x72 at full): same centre, so it still sits on the window's corner
		close.Size = if compact then UDim2.fromOffset(61, 58) else UDim2.fromOffset(72, 68) -- visible ~63x61 (the sprite shows ~0.87 of its box)
		close.Position = if compact
			then UDim2.fromOffset(winW - t.mx - 27, t.my + 5)
			else UDim2.fromOffset(winW - t.mx - 29, t.my + 8.5) -- centre 1432.5, 101.5
		if closeHit then
			local minD = 44 / eff -- design px
			closeHit.Size = UDim2.fromOffset(math.max(close.Size.X.Offset, minD), math.max(close.Size.Y.Offset, minD))
		end

		-- Tabs: equal widths; label shrinks (>=15) and the icon drops when very narrow.
		local barW = winW - 2 * (t.mx + 47)
		local n = math.max(1, #self._tabs)
		local fixedW = not compact and n == #TAB_W
		local equalW = not compact and not fixedW and #self._tabs > 0 -- other tab counts fill the Bag's tab-row span (or keep deps.tabW)
		local tabW = math.floor((barW - (n - 1) * t.tabGap) / n)
		local tabK = 1
		if fixedW or equalW then
			barW = t.tabGap * (#TAB_W - 1)
			for _, w in TAB_W do
				barW += w
			end
			-- a narrower window shrinks the tabs with it (1 at the reference width: 40.6 px of rim each side)
			tabK = math.min(1, (winW - 2 * t.mx - 81.2) / barW)
			barW *= tabK
			if equalW then
				tabW = (barW - (n - 1) * t.tabGap) / n
			end
		end
		tabBar.Position = UDim2.new(0.5, 0, 0, t.tabTop + t.my)
		tabBar.Size = UDim2.fromOffset(barW, t.tabH)
		tabBar.UIListLayout.Padding = UDim.new(0, t.tabGap)
		local icon = t.icon * (if compact then 1 else deps.tabIconScale or 1) -- phones: the label gets the width, not a bigger icon
		local labelSize = math.huge -- one text size for the whole bar: the largest every label fits at
		for i, tab in self._tabButtons do
			local w = if fixedW
				then TAB_W[i] * tabK
				elseif equalW and deps.tabW then math.min(deps.tabW * tabK, tabW)
				elseif compact and deps.tabW then math.min(
					deps.tabW * t.tabH / TIER.Full.tabH,
					(barW - (deps.tabReserve or 0) - (n - 1) * t.tabGap) / n
				) -- phones: scaled with the tab height, leaving tabReserve for other row children
				else tabW
			local hasIcon = self._tabs[i].Icon ~= nil
			tab.Size = UDim2.fromOffset(w, t.tabH)
			tab.Row.Position = UDim2.fromOffset(0, if compact then 0 else -4) -- ref label y 159-178: above the tab centre
			tab.Row.UIListLayout.Padding = UDim.new(0, t.iconGap)
			tab.Row.Icon.Size = UDim2.fromOffset(icon, icon)
			tab.Row.Icon.Visible = hasIcon and w >= 150
			local avail = w - (if compact then 16 else 24) - (if hasIcon and w >= 150 then icon + t.iconGap else 0)
			tab.Row.Label.UISizeConstraint.MaxSize = Vector2.new(avail, t.tabH)
			labelSize =
				math.min(labelSize, Parts.fitSize(tab.Row.Label.Text, avail, if w < 170 then 18 else t.tabText, 15))
		end
		for _, tab in self._tabButtons do
			tab.Row.Label.TextSize = labelSize
		end
		self:_skinTabs()
	end
	self._fit = fit
	table.insert(conns, {
		Disconnect = SettingsLogic.onChanged(function(id)
			if id == "uiScale" and bag.Visible then
				fit()
			end
		end),
	})
	table.insert(conns, parent:GetAttributeChangedSignal("EmulateSize"):Connect(fit))
	table.insert(
		conns,
		bag:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:Fit()
		end)
	)
	return self
end

-- The Dice footer strip shows/hides: the left panel gives it room (full tier) or fills the column again.
function Shell:SetFooter(on: boolean)
	if self._footerOn ~= on then
		self._footerOn = on
		self:Fit()
	end
end

function Shell:Fit()
	self._fit()
end

function Shell:_skinTabs()
	local h = TIER[if self.Compact then "Compact" else "Full"].tabH
	for i, tab in self._tabButtons do
		Parts.skinH(tab, if i == self._tab then "TabGold" else "TabPurple", h)
	end
end

-- tabs: { {Id, Label, Icon (BagSprites key or id)} }
function Shell:SetTabs(tabs)
	for _, b in self._tabButtons do
		b:Destroy()
	end
	table.clear(self._tabButtons)
	self._tabs = tabs
	for i, tab in tabs do
		local btn = make("ImageButton", {
			Name = "Tab" .. i,
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Size = UDim2.fromOffset(254, 60),
			ZIndex = Z + 4,
		}, self.TabBar)
		Parts.interact(btn)
		local row = make(
			"Frame",
			{ Name = "Row", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = Z + 5 },
			btn
		)
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}, row)
		local icon = make("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(36, 36),
			LayoutOrder = 1,
			ZIndex = Z + 6,
		}, row)
		if tab.Icon then
			Parts.image(icon, tab.Icon)
		end
		local label = Parts.text(row, {
			Name = "Label",
			Text = tab.Label,
			TextSize = 24,
			LayoutOrder = 2,
			ZIndex = Z + 6,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 40),
		}, 4)
		make("UISizeConstraint", {}, label) -- caps the width so long labels truncate; the icon+label group stays centred
		table.insert(
			self._conns,
			btn.Activated:Connect(function()
				self:SetTab(i)
			end)
		)
		self._tabButtons[i] = btn
	end
	self._tab = 0
	self:Fit()
end

-- Cheap and idempotent: only the two tab sprites change; callbacks fire when the index changes.
function Shell:SetTab(i: number)
	if i == self._tab or not self._tabButtons[i] then
		return
	end
	self._tab = i
	self:_skinTabs()
	for _, cb in self._onTab do
		cb(i)
	end
end

function Shell:GetTab(): number
	return self._tab
end

function Shell:OnTab(cb)
	table.insert(self._onTab, cb)
end

function Shell:OnClose(cb)
	table.insert(self._onClose, cb)
end

function Shell:IsOpen(): boolean
	return self.Bag.Visible
end

function Shell:Open()
	if self.Bag.Visible then
		return
	end
	self:Fit()
	if SettingsLogic.get("reducedMotion") then
		self._pop.Scale = 1
		self.Bag.Visible = true
		return
	end
	self._pop.Scale = 0.94
	self.Bag.Visible = true
	self._popTween = TweenService:Create(self._pop, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1 })
	self._popTween:Play()
end

function Shell:Close()
	if not self.Bag.Visible then
		return
	end
	if self._popTween then
		self._popTween:Cancel()
	end
	self._pop.Scale = 1
	local focused = UserInputService:GetFocusedTextBox()
	if focused and focused:IsDescendantOf(self.Bag) then
		focused:ReleaseFocus()
	end
	self.Bag.Visible = false
	for _, cb in self._onClose do
		cb()
	end
end

function Shell:Destroy()
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)
	if self._popTween then
		self._popTween:Cancel()
	end
	self.Bag:Destroy()
end

return Shell
