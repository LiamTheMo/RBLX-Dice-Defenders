-- Codes popup controller: one free Shell (CODES banner, close) hosting the Codes View, wired to RedeemCode.
-- Codes.new(parent, { hud = LobbyHud, toast = (string) -> () }) -> :Open() :Close() :Toggle() :IsOpen() :Destroy()
-- Owns the field's sanitising, the button state machine, result messages and the phone keyboard lift. The client holds no
-- codes or rewards: the server checks everything, and the Gold reward arrives through the usual Meta push.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CodesLogic = require(script.Parent.CodesLogic)
local NetClient = require(script.Parent.Parent.NetClient)
local SettingsLogic = require(script.Parent.Parent.Settings.SettingsLogic)
local Shell = require(script.Parent.Parent.Bag.Shell)
local Sprites = require(script.Parent.Parent.Sprites)
local UiKit = require(script.Parent.Parent.UiKit)
local View = require(script.Parent.View)

local ACTION = "CodesClose"
local HINT = "Letters, numbers, - and _ only"
local EMPTY = "Enter a code first!"
local CODES_ICON = { Image = Sprites.Icon.Codes, Size = Vector2.new(256, 217), Ink = Rect.new(4, 5, 251, 213) }
local FIELD_TONE = { Success = "Success", Error = "Error" } -- anything else = "Default"

local Codes = {}
Codes.__index = Codes

function Codes.new(parent, deps)
	local self = setmetatable({}, Codes)
	local hud = deps.hud
	local shell = Shell.new(parent, {
		fit = function()
			return hud:GetBagInsets()
		end,
		name = "Codes",
		free = true,
		size = Vector2.new(623, 532),
		banner = {
			text = "CODES",
			emblems = { { sprite = CODES_ICON, box = { 0, 0, 0.25, 1.006 }, side = true } },
		},
	})
	local view = View.new(shell.Slots.Content)
	local box, root, scaled = view.Box, shell.Bag, shell.Scaled
	local field = box.Parent
	local conns = {}
	local alive = true

	-- Result line: a token so an old timer never clears a newer message. seconds nil = stays until replaced.
	local msgToken = 0
	local function show(text: string?, tone: string?, seconds: number?)
		msgToken += 1
		local token = msgToken
		view:SetMessage(text, tone)
		view:SetField(FIELD_TONE[tone or ""] or "Default")
		if seconds then
			task.delay(seconds, function()
				if alive and token == msgToken then
					view:SetMessage(nil)
					view:SetField("Default")
				end
			end)
		end
	end

	-- Button: Disabled (empty field) keeps the Ready look, but its press only points at the field.
	-- failures / streak mirror the server's guessing lock (counted failures; RateLimited replies in a row as a fallback)
	local waiting, cooldownUntil, failures, streak = false, 0, 0, 0
	local function mode()
		return CodesLogic.buttonMode(box.Text, waiting, os.clock(), cooldownUntil)
	end
	local function refresh()
		if alive then
			local m = mode()
			view:SetButton(if m == "Disabled" then "Ready" else m)
		end
	end
	local function submit(fromEnter: boolean?)
		local m = mode()
		if m == "Disabled" then
			-- Done on a phone keyboard must close it, so only a press or a hardware Enter keeps typing.
			if not fromEnter or UserInputService:GetLastInputType() == Enum.UserInputType.Keyboard then
				box:CaptureFocus()
			end
			show(EMPTY, "Info", CodesLogic.MESSAGE_SECONDS)
			return
		elseif m ~= "Ready" then
			return
		end
		local code = CodesLogic.sanitize(box.Text) -- the field is always clean; never send anything the server's guard rejects
		waiting = true
		show(nil) -- a new try drops the previous answer (and its timer) so "REDEEMING..." never sits beside an old error
		refresh()
		task.spawn(function()
			local ok, err = NetClient.Request("RedeemCode", code)
			waiting = false
			failures = CodesLogic.nextFailures(failures, ok, err)
			streak = CodesLogic.nextStreak(streak, ok, err)
			local r = CodesLogic.result(ok, err, streak, failures)
			if alive and r then
				cooldownUntil = os.clock() + r.cooldown
				if r.clear and box.Text == code then
					box.Text = ""
				end
				show(r.text, r.tone, r.seconds)
				task.delay(r.cooldown + 0.05, refresh)
			end
			refresh()
		end)
	end
	table.insert(
		conns,
		view.Button.Activated:Connect(function()
			submit()
		end)
	)

	-- Sanitise every change (typing and paste; a full field refuses inserts). Writing the kept text back re-fires this,
	-- which then finds nothing to do.
	local lastText = box.Text
	table.insert(
		conns,
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local text = box.Text
			local kept, cursor, changed = CodesLogic.edit(lastText, text, box.CursorPosition)
			lastText = kept
			if kept ~= text then
				box.Text = kept
				if box:IsFocused() then
					box.CursorPosition = cursor
				end
			end
			if changed then
				show(HINT, "Info", CodesLogic.MESSAGE_SECONDS)
			end
			refresh()
		end)
	)

	-- Keyboard lift (phones): raise the popup so the field clears the on-screen keyboard. Real px in the root's space;
	-- Scaled has no ancestor scale, so its Position offset is real px.
	local liftTween
	local function keyboardTop(): number?
		if RunService:IsStudio() then -- Studio simulation: KeyboardInset = a keyboard that covers this many real px of the screen's bottom
			local inset = root:GetAttribute("KeyboardInset")
			if type(inset) == "number" and inset > 0 then
				return UiKit.screenSize(parent).Y - inset
			end
		end
		if box:IsFocused() and UserInputService.OnScreenKeyboardVisible then
			local pos, size = UserInputService.OnScreenKeyboardPosition, UserInputService.OnScreenKeyboardSize
			if pos.Y > 0 then -- screen px; GUI space starts below the top inset
				return pos.Y - GuiService:GetGuiInset().Y - parent.AbsolutePosition.Y
			elseif size.Y > 0 then -- no position reported: it sits on the screen's bottom edge
				return parent.AbsoluteSize.Y - size.Y
			end
		end
		return nil
	end
	local function setLift(px: number)
		if liftTween then
			liftTween:Cancel()
			liftTween = nil
		end
		local goal = UDim2.fromOffset(0, -px)
		if scaled.Position == goal then
			return
		end
		if SettingsLogic.get("reducedMotion") or not root.Visible then
			scaled.Position = goal
		else
			liftTween = TweenService:Create(scaled, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Position = goal })
			liftTween:Play()
		end
	end
	local function updateLift()
		local kb = if root.Visible then keyboardTop() else nil
		if kb == nil then
			setLift(0)
			return
		end
		local top = field.AbsolutePosition.Y - scaled.AbsolutePosition.Y -- where it sits unlifted (Scaled's unlifted top = the root's)
		setLift(CodesLogic.lift(top, top + field.AbsoluteSize.Y, kb))
	end
	for _, prop in { "OnScreenKeyboardVisible", "OnScreenKeyboardPosition", "OnScreenKeyboardSize" } do
		table.insert(conns, UserInputService:GetPropertyChangedSignal(prop):Connect(updateLift))
	end
	table.insert(conns, box.Focused:Connect(updateLift))
	-- Return / Done submits (REDEEM sits under the keyboard on phones); Escape releases the field and closes in one press.
	table.insert(
		conns,
		box.FocusLost:Connect(function(enterPressed, input)
			if enterPressed then
				submit(true)
			elseif input and input.KeyCode == Enum.KeyCode.Escape then
				shell:Close()
			end
			updateLift()
		end)
	)

	if RunService:IsStudio() then
		-- Studio only (never connected in live servers): KeyboardInset simulates the keyboard; PreviewState shows a
		-- result state through the View setters alone (no request, Gold, codes or profile state). "" = live.
		table.insert(conns, root:GetAttributeChangedSignal("KeyboardInset"):Connect(updateLift))
		table.insert(
			conns,
			root:GetAttributeChangedSignal("PreviewState"):Connect(function()
				local s = root:GetAttribute("PreviewState")
				show(nil) -- each preview starts from the live look (no caption or button left over from the last one)
				refresh()
				if s == "Waiting" or s == "Cooldown" then
					view:SetButton(s)
				elseif type(s) == "string" and s ~= "" then
					local r = CodesLogic.result(s == "Success", s)
					if r then
						show(r.text, r.tone)
					end
				end
			end)
		)
	end

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
		ContextActionService:UnbindAction(ACTION)
		hud:SetBagMode(false)
		show(nil)
		setLift(0)
	end)

	self.Shell, self.View, self._conns = shell, view, conns
	self._kill = function()
		alive = false
		msgToken += 1
		if liftTween then
			liftTween:Cancel()
		end
	end
	self._open = function()
		if shell:IsOpen() then
			return
		end
		refresh()
		shell:Open()
		hud:SetBagMode(true, "Codes")
		ContextActionService:BindActionAtPriority(ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				shell:Close()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		-- Keyboard / mouse players can type at once; touch and gamepad never get an on-screen keyboard they did not ask for.
		local last = UserInputService:GetLastInputType()
		if last == Enum.UserInputType.Keyboard or string.find(last.Name, "^Mouse") then
			box:CaptureFocus()
		end
	end
	return self
end

function Codes:Open()
	self._open()
end

function Codes:Close()
	self.Shell:Close()
end

function Codes:Toggle()
	if self.Shell:IsOpen() then
		self.Shell:Close()
	else
		self._open()
	end
end

function Codes:IsOpen(): boolean
	return self.Shell:IsOpen()
end

function Codes:Destroy()
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)
	if self.Shell:IsOpen() then
		self.Shell:Close() -- unbinds ButtonB and restores the HUD
	end
	self._kill()
	self.View:Destroy()
	self.Shell:Destroy()
end

return Codes
