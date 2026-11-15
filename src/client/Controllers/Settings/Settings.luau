-- Settings menu controller: one Shell (banner with two dice, close, GAMEPLAY / GRAPHICS / AUDIO / MISC tabs, a gear pair behind the banner)
-- hosting the Settings View, wired to the SettingsLogic store: control input, the coming-soon toast, close at match start, and the
-- consumers (Shadows, Show FPS here; Reduced Motion and UI Scale in the Shell). Session only: nothing is saved.
-- Settings.new(parent, { hud = LobbyHud, toast = (string) -> () }) -> :Open(tab?) :Close() :Toggle(tab?) :IsOpen() :Destroy(); tab = a tab id or index.

local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Fps = require(script.Parent.Fps)
local NetClient = require(script.Parent.Parent.NetClient)
local PlaySprites = require(script.Parent.Parent.Play.PlaySprites)
local SettingsLogic = require(script.Parent.SettingsLogic)
local SettingsSprites = require(script.Parent.SettingsSprites)
local Shell = require(script.Parent.Parent.Bag.Shell)
local UiKit = require(script.Parent.Parent.UiKit)
local View = require(script.Parent.View)

local ACTION = "SettingsClose"
local STEP = "SettingsSliderStep"
local SLOP = 10 -- real px a touch must move before it is a drag (sideways) or a list scroll (up / down)
local SB = PlaySprites.ScrollBase
local TABS = {
	GAMEPLAY = { label = "GAMEPLAY", icon = SettingsSprites.TabGameplay, scale = 1.08 },
	GRAPHICS = { label = "GRAPHICS", icon = SettingsSprites.TabGraphics, scale = 0.87 }, -- scale: the sprite inside the Shell's icon box (reference 46 x 42)
	AUDIO = { label = "AUDIO", icon = SettingsSprites.Music },
	MISC = { label = "MISC", icon = SettingsSprites.TabMisc, scale = 1.15 },
}
-- Banner dice (scroll-ink fractions x, y, w, h; the sprite is drawn by its ink): the right one mirrors the left about the scroll centre,
-- so the pair stays symmetric about the centred title. Compact sits closer because the title shrinks there.
local DIE = {
	full = { 0.1206, 0.284, 0.091, 0.4345 },
	compact = { 0.182, 0.252, 0.109, 0.52 },
}
local function mirrored(b)
	return { 1 - b[1] - b[3], b[2], b[3], b[4] }
end
-- Gear pair behind the banner, as fractions of the scroll's ink width Wr (measured on the reference): ink height, ink centre x offset from the
-- banner centre, ink bottom below the scroll's ink top, parchment top below the scroll's ink top. Shrinks (g >= 0.70) to keep its top on screen.
local GEAR = { h = 0.1828, dx = 0.0127, below = 0.0684, parchment = 0.0463, minG = 0.70, minVisible = 0.40 }
local GEAR_Z = 26 -- Window child: above the chrome, content and tabs (21-23), behind the banner (30)

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function preloadIds(): { string }
	local seen, ids = {}, {}
	for _, rec in SettingsSprites do
		if rec.Image and not seen[rec.Image] then
			seen[rec.Image] = true
			table.insert(ids, rec.Image)
		end
	end
	return ids
end

local Settings = {}
Settings.__index = Settings

function Settings.new(parent, deps)
	local self = setmetatable({}, Settings)
	local hud = deps.hud
	local conns = {}
	local die = SettingsSprites.Die
	local shell = Shell.new(parent, {
		fit = function()
			return hud:GetBagInsets()
		end,
		name = "Settings",
		free = true,
		banner = {
			text = "SETTINGS",
			noGem = true,
			emblems = {
				{ sprite = die, box = { full = DIE.full, compact = DIE.compact } },
				{ sprite = die, box = { full = mirrored(DIE.full), compact = mirrored(DIE.compact) } },
			},
		},
	})
	local tabs = {}
	for i, id in SettingsLogic.TABS do
		tabs[i] = { Id = id, Label = TABS[id].label, Icon = TABS[id].icon }
	end
	shell:SetTabs(tabs)
	for i, id in SettingsLogic.TABS do -- Parts.image has no crop: the Graphics icon is a crop of the ScreenShake image
		local rect = TABS[id].icon.ImageRect
		local icon = shell.TabBar["Tab" .. i].Row.Icon
		if rect then
			icon.ImageRectOffset, icon.ImageRectSize = rect.Min, Vector2.new(rect.Width, rect.Height)
		end
		local k = TABS[id].scale
		if k then -- move the picture into a centred child so the Shell's own icon sizing still applies
			local art = icon:Clone()
			art.Name, art.AnchorPoint, art.Position, art.Size =
				"Art", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(k, k)
			art.Parent = icon
			icon.Image = ""
		end
	end
	local view = View.new(shell.Slots.Content, {})

	-- Consumers: applied now and on every change.
	local fps -- created on first use, when PlayerGui surely exists
	local function apply(id: string, value: any)
		if id == "shadows" then
			Lighting.GlobalShadows = value
		elseif id == "showFps" and (value or fps) then
			fps = fps or Fps.new(Players.LocalPlayer:WaitForChild("PlayerGui"))
			fps:SetVisible(value)
		end
	end
	-- Roblox's own Reduced Motion setting starts ours ON (the toggle then shows and controls it).
	local okRm, platformRm = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	if okRm and platformRm then
		SettingsLogic.set("reducedMotion", true)
	end
	apply("shadows", SettingsLogic.get("shadows"))
	apply("showFps", SettingsLogic.get("showFps"))
	table.insert(conns, {
		Disconnect = SettingsLogic.onChanged(function(id, value)
			apply(id, value)
			view:SetValue(id, value)
		end),
	})

	-- Input. A user change of a def nothing reads yet says so once per session.
	local told = {}
	local function user(id: string, change: () -> ())
		local before = SettingsLogic.get(id)
		change()
		local def = SettingsLogic.byId[id]
		if
			def.noEffectYet
			and not told[id]
			and (SettingsLogic.get(id) ~= before or (def.options and #def.options < 2))
		then
			told[id] = true
			deps.toast(def.name .. ": coming soon")
		end
	end
	-- A slider press: { id, fraction(screenX), input, value, x, y, list, canvas } while undecided (a touch not yet decided) or dragging.
	local drag, undecided, held, restoreSel = nil, nil, nil, nil
	local function release()
		if held then
			if held.Parent then
				held.ScrollingEnabled = true
			end
			held = nil
		end
	end
	local function slide(d, x: number)
		local v = SettingsLogic.fromFraction(d.id, d.fraction(x))
		if v == nil then
			return
		end
		d.value = v
		if d.id == "uiScale" then
			view:SetValue(d.id, v) -- preview only: the store (and the window scale) changes on release
		else
			user(d.id, function()
				SettingsLogic.set(d.id, v)
			end)
		end
	end
	local function phoneScaleNote() -- phones keep the touch-size floor, so UI Scale only changes desktop
		if not told.uiScale and UiKit.screenSize(parent).Y < UiKit.PHONE_H then
			told.uiScale = true
			deps.toast("UI Scale: desktop only")
		end
	end
	local function commit(d)
		if d.id == "uiScale" and d.value then
			SettingsLogic.set(d.id, d.value)
			phoneScaleNote()
		end
	end
	local function cancel() -- close, tab change, rebuild, reset: drop the press and undo an uncommitted preview
		release()
		undecided = nil
		local d = drag
		drag = nil
		if d and d.id == "uiScale" then
			view:SetValue(d.id, SettingsLogic.get(d.id))
		end
	end
	local stepId -- the slider whose D-pad step is bound (SelectionLost of the old one may come after SelectionGained of the new)
	local function unbindStep(id: string?)
		if id == nil or id == stepId then
			stepId = nil
			ContextActionService:UnbindAction(STEP)
		end
	end
	local function isPress(input, d): boolean
		return input == d.input
			or (
				input.UserInputType == Enum.UserInputType.MouseButton1
				and d.input.UserInputType == Enum.UserInputType.MouseButton1
			)
	end
	table.insert(
		conns,
		UserInputService.InputChanged:Connect(function(input)
			local p = undecided
			if p and input == p.input then
				local dx, dy = math.abs(input.Position.X - p.x), math.abs(input.Position.Y - p.y)
				if dx < SLOP and dy < SLOP then
					return
				end
				undecided = nil
				if dx > dy then -- sideways: the slider takes the drag and the list holds still
					release()
					held = p.list
					p.list.ScrollingEnabled = false
					p.list.CanvasPosition = p.canvas
					drag = p
					slide(p, input.Position.X)
				end -- up / down: the list scrolls, the value stays
				return
			end
			local d = drag
			if
				d
				and (
					input == d.input
					or (
						input.UserInputType == Enum.UserInputType.MouseMovement
						and d.input.UserInputType == Enum.UserInputType.MouseButton1
					)
				)
			then
				slide(d, input.Position.X)
			end
		end)
	)
	table.insert(
		conns,
		UserInputService.InputEnded:Connect(function(input)
			local p = undecided
			if p and input == p.input then -- a tap
				undecided = nil
				slide(p, input.Position.X)
				commit(p)
				return
			end
			local d = drag
			if d and isPress(input, d) then
				drag = nil
				release()
				commit(d)
			end
		end)
	)
	local buildConns = {}
	local function nudge(id: string, dir: number) -- gamepad step of the selected slider
		local before = SettingsLogic.get(id)
		user(id, function()
			SettingsLogic.set(id, before + dir * (SettingsLogic.byId[id].step or 1))
		end)
		if id == "uiScale" and SettingsLogic.get(id) ~= before then
			phoneScaleNote()
			restoreSel = id -- the window rescales and the View rebuilds: take the selection back afterwards
		end
	end
	local function bindStep(id: string)
		stepId = id
		local armed = true
		ContextActionService:BindActionAtPriority(
			STEP,
			function(_, state, input)
				local key, dir = input.KeyCode, 0
				if key == Enum.KeyCode.Thumbstick1 then
					local p = input.Position
					if math.abs(p.X) < 0.6 or math.abs(p.X) < math.abs(p.Y) then
						armed = true
						return Enum.ContextActionResult.Pass -- a vertical stick still moves the selection
					end
					if armed then
						armed, dir = false, if p.X < 0 then -1 else 1
					end
				elseif state == Enum.UserInputState.Begin then
					dir = if key == Enum.KeyCode.DPadLeft then -1 else 1
				end
				if dir ~= 0 then
					nudge(id, dir)
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			Enum.ContextActionPriority.High.Value + 50,
			Enum.KeyCode.DPadLeft,
			Enum.KeyCode.DPadRight,
			Enum.KeyCode.Thumbstick1
		)
	end
	view:OnBuilt(function(rows)
		cancel()
		unbindStep()
		for _, c in buildConns do
			c:Disconnect()
		end
		table.clear(buildConns)
		local function on(signal, fn)
			table.insert(buildConns, signal:Connect(fn))
		end
		for id, r in rows do
			local def = SettingsLogic.byId[id]
			if def.kind == "toggle" then
				on(r.Hit.Activated, function()
					user(id, function()
						SettingsLogic.set(id, not SettingsLogic.get(id))
					end)
				end)
			elseif def.kind == "select" then
				for dir, hit in { [-1] = r.Left, [1] = r.Right } do
					on(hit.Activated, function()
						user(id, function()
							SettingsLogic.cycle(id, dir)
						end)
					end)
				end
			else
				local hit = r.Hit
				on(hit.InputBegan, function(input)
					local kind = input.UserInputType
					if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
						return
					end
					cancel()
					local d = { id = id, fraction = r.Fraction, input = input }
					local list = hit:FindFirstAncestorWhichIsA("ScrollingFrame")
					if kind == Enum.UserInputType.Touch and list and list.ScrollingEnabled then
						d.x, d.y, d.list, d.canvas = input.Position.X, input.Position.Y, list, list.CanvasPosition
						undecided = d -- wait to see whether this is a drag or a list scroll
						return
					end
					drag = d
					slide(d, input.Position.X)
				end)
				on(hit.SelectionGained, function()
					bindStep(id)
				end)
				on(hit.SelectionLost, function()
					unbindStep(id)
				end)
			end
		end
		on(view.ResetButton.Activated, function()
			local tab = SettingsLogic.TABS[shell:GetTab()]
			if tab then
				cancel()
				SettingsLogic.resetTab(tab)
			end
		end)
		if restoreSel and rows[restoreSel] then
			GuiService.SelectedObject = rows[restoreSel].Hit
		end
		restoreSel = nil
	end)
	shell:OnTab(function(i)
		cancel()
		view:SetTab(SettingsLogic.TABS[i])
	end)
	table.insert(
		conns,
		NetClient.State:Connect(function(snap)
			if shell:IsOpen() and snap.Phase ~= "Lobby" and snap.Phase ~= "Ended" then
				shell:Close() -- a match started
			end
		end)
	)

	-- Gear pair: a Window child behind the banner, placed from the banner's real-px rect (recomputed whenever that moves or resizes).
	local window, banner = shell.Window, shell.Banner
	local gears = Instance.new("ImageLabel")
	gears.Name, gears.BackgroundTransparency, gears.ZIndex = "Gears", 1, GEAR_Z
	gears.Image, gears.ScaleType = SettingsSprites.GearPair.Image, Enum.ScaleType.Stretch
	gears.Visible = false
	gears.Parent = window
	local function placeGears()
		local rec = SettingsSprites.GearPair
		local ink, winW = rec.Ink, window.Size.X.Offset
		local bs = banner.AbsoluteSize
		local wr = bs.X * SB.Ink.Width / SB.Size.X -- the scroll's ink width, real px
		if winW <= 0 or wr <= 0 then
			return
		end
		local ps = window.AbsoluteSize.X / winW -- real px per Window design px (shell scale x pop)
		local inkTop = banner.AbsolutePosition.Y + bs.Y * SB.Ink.Min.Y / SB.Size.Y
		local cx = banner.AbsolutePosition.X + bs.X * (SB.Ink.Min.X + SB.Ink.Max.X) / 2 / SB.Size.X + GEAR.dx * wr
		local g = math.clamp((inkTop + GEAR.below * wr) / (GEAR.h * wr), GEAR.minG, 1)
		local h = GEAR.h * wr * g
		local top = math.max(0, inkTop + GEAR.below * wr - h) -- real px, ink top
		gears.Visible = (inkTop + GEAR.parchment * wr - top) / h >= GEAR.minVisible
		local s = h / ink.Height -- real px per sprite px
		local o = window.AbsolutePosition
		gears.Position = UDim2.fromOffset(
			round((cx - (ink.Min.X + ink.Max.X) / 2 * s - o.X) / ps),
			round((top - ink.Min.Y * s - o.Y) / ps)
		)
		gears.Size = UDim2.fromOffset(round(rec.Size.X * s / ps), round(rec.Size.Y * s / ps))
	end
	local pending = false
	local function schedule()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			if gears.Parent then
				placeGears()
			end
		end)
	end
	table.insert(conns, banner:GetPropertyChangedSignal("AbsolutePosition"):Connect(schedule))
	table.insert(conns, banner:GetPropertyChangedSignal("AbsoluteSize"):Connect(schedule))
	table.insert(conns, window:GetPropertyChangedSignal("AbsoluteSize"):Connect(schedule))
	schedule()

	table.insert(
		conns,
		GuiService.MenuOpened:Connect(function()
			shell:Close()
		end)
	)
	shell:OnClose(function()
		cancel()
		unbindStep()
		ContextActionService:UnbindAction(ACTION)
		hud:SetBagMode(false)
	end)

	local preloaded = false
	self.Shell, self.View, self._conns, self._gears = shell, view, conns, gears
	self._teardown = function()
		cancel()
		unbindStep()
		for _, c in buildConns do
			c:Disconnect()
		end
		table.clear(buildConns)
		if fps then
			fps:Destroy()
		end
	end
	self._open = function(tab)
		local index = if type(tab) == "string" then table.find(SettingsLogic.TABS, tab) else tab
		if not preloaded then
			preloaded = true
			task.spawn(pcall, ContentProvider.PreloadAsync, ContentProvider, preloadIds()) -- stream the art so the first frame is not blank
			shell:SetTab(index or 1) -- GAMEPLAY on first open
		elseif index then
			shell:SetTab(index)
		end
		if shell:IsOpen() then
			return
		end
		shell:Open()
		hud:SetBagMode(true, "Settings")
		ContextActionService:BindActionAtPriority(ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				shell:Close()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
	end
	return self
end

function Settings:Open(tab: (string | number)?)
	self._open(tab)
end

function Settings:Close()
	self.Shell:Close()
end

function Settings:Toggle(tab: (string | number)?)
	if self.Shell:IsOpen() then
		self.Shell:Close()
	else
		self._open(tab)
	end
end

function Settings:IsOpen(): boolean
	return self.Shell:IsOpen()
end

function Settings:Destroy()
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)
	if self.Shell:IsOpen() then
		self.Shell:Close() -- unbinds ButtonB and restores the HUD
	end
	self._teardown()
	self.View:Destroy()
	self._gears:Destroy()
	self.Shell:Destroy()
end

return Settings
