-- Settings menu controller: one Shell (title, close, AUDIO / GAMEPLAY / GRAPHICS / MISC tabs as in the mockups)
-- hosting the Settings View, wired to the SettingsLogic store: control input, the coming-soon toast, close at match start, and the
-- consumers (Shadows, Show FPS here; Reduced Motion and UI Scale in the Shell). Saved in the profile: the first Meta loads the
-- values, and later changes go to the server as one SaveSettings patch 2 s after the last change or at once on close.
-- Settings.new(parent, { hud = LobbyHud, toast = (string) -> () }) -> :Open(tab?) :Close() :Toggle(tab?) :IsOpen() :Destroy(); tab = a tab id or index.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Fps = require(script.Parent.Fps)
local NetClient = require(script.Parent.Parent.NetClient)
local SettingsLogic = require(script.Parent.SettingsLogic)
local Shell = require(script.Parent.Parent.Bag.Shell)
local UiKit = require(script.Parent.Parent.UiKit)
local View = require(script.Parent.View)

local ACTION = "SettingsClose"
local STEP = "SettingsSliderStep"
local SLOP = 10 -- real px a touch must move before it is a drag (sideways) or a list scroll (up / down)
local SAVE_DELAY = 2 -- seconds after the last change before the SaveSettings patch goes (also the retry delay)
local TAB_ORDER = { "AUDIO", "GAMEPLAY", "GRAPHICS", "MISC" } -- shell tab order (the mockups'); SettingsLogic.TABS keeps the registry order
local Settings = {}
Settings.__index = Settings

function Settings.new(parent, deps)
	local self = setmetatable({}, Settings)
	local hud = deps.hud
	local conns = {}
	local shell = Shell.new(parent, {
		fit = function()
			return hud:GetBagInsets()
		end,
		name = "Settings",
		free = true,
		banner = { text = "SETTINGS" },
	})
	local tabs = {}
	for i, id in TAB_ORDER do
		tabs[i] = { Id = id, Label = id }
	end
	shell:SetTabs(tabs)
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

	-- Saving. Player changes collect in `dirty` (id -> value) and go out as one patch once the saved values have loaded;
	-- a send NetClient refuses locally (throttle, in flight, no remote yet) is merged back under newer values and retried.
	local dirty, loaded, loading, destroyed = {}, false, false, false
	local timer: thread? -- the pending delayed save; a newer saveLater or any saveNow cancels it
	local saveNow
	local function stopTimer()
		if timer then
			task.cancel(timer)
			timer = nil
		end
	end
	local function saveLater()
		stopTimer()
		timer = task.delay(SAVE_DELAY, function()
			timer = nil -- running now: nothing to cancel
			saveNow()
		end)
	end
	function saveNow()
		stopTimer()
		if not loaded or next(dirty) == nil then
			return
		end
		local patch = dirty
		dirty = {}
		task.spawn(function()
			local ok, code = NetClient.Request("SaveSettings", patch)
			if not ok and (code == "Throttled" or code == "Network") then
				for id, value in patch do
					if dirty[id] == nil then
						dirty[id] = value
					end
				end
				if not destroyed then
					saveLater()
				end
			end
		end)
	end
	-- The first Meta carrying Settings loads them (no toast, not sent back); later Metas never overwrite the store.
	local function load(meta)
		local saved = if type(meta) == "table" then meta.Settings else nil
		if loaded or type(saved) ~= "table" then
			return
		end
		loaded, loading = true, true
		for _, def in SettingsLogic.DEFS do
			if saved[def.id] ~= nil and dirty[def.id] == nil then -- a change made before the load wins
				SettingsLogic.set(def.id, saved[def.id])
			end
		end
		if okRm and platformRm and dirty.reducedMotion == nil then
			SettingsLogic.set("reducedMotion", true)
		end
		loading = false
		if next(dirty) ~= nil then
			saveLater()
		end
	end
	table.insert(conns, {
		Disconnect = SettingsLogic.onChanged(function(id, value)
			if not loading then -- recorded first, so a failing consumer below cannot lose the change
				dirty[id] = value
				saveLater()
			end
			apply(id, value)
			view:SetValue(id, value)
		end),
	})
	table.insert(conns, NetClient.Meta:Connect(load))
	load(NetClient.LastMeta)

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
			local tab = TAB_ORDER[shell:GetTab()]
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
		view:SetTab(TAB_ORDER[i])
	end)
	table.insert(
		conns,
		NetClient.State:Connect(function(snap)
			if shell:IsOpen() and snap.Phase ~= "Lobby" and snap.Phase ~= "Ended" then
				shell:Close() -- a match started
			end
		end)
	)

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
		saveNow()
	end)

	local opened = false
	self.Shell, self.View, self._conns = shell, view, conns
	self._teardown = function()
		destroyed = true
		saveNow() -- last chance for unsent changes; no retry after this
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
		local index = if type(tab) == "string" then table.find(TAB_ORDER, tab) else tab
		if not opened then
			opened = true
			shell:SetTab(index or 1) -- AUDIO on first open (the first tab)
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
	self.Shell:Destroy()
end

return Settings
