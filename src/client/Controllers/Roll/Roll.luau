-- Roll menu controller: one Shell (banner, close, STANDARD / EVENT tabs) hosting the Roll View.
-- Roll.new(parent, { hud = LobbyHud, toast = (string) -> () }) -> :Open() :Close() :Toggle() :IsOpen() :Destroy()
-- Renders the server's numbers only: odds, prices, pity max and featured dice from Catalog.Roll, Gems / pity count /
-- RollAllowed from Meta. ROLL 1 / ROLL 10 send Roll(pool, count); the draw arrives as RollResult (shown in the featured
-- panel as "YOUR ROLL" until the menu closes, plus a toast). Not allowed (paid random items policy): buttons off and
-- "Not available in your region". The EVENT tab shows "No event right now"; there is no rotation timer yet.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local NetClient = require(script.Parent.Parent.NetClient)
local Draw = require(script.Parent.Parent.QuestLog.Draw)
local PlaySprites = require(script.Parent.Parent.Play.PlaySprites)
local RollFlow = require(script.Parent.RollFlow)
local RollLogic = require(script.Parent.RollLogic)
local SettingsLogic = require(script.Parent.Parent.Settings.SettingsLogic)
local Shell = require(script.Parent.Parent.Bag.Shell)
local RollSprites = require(script.Parent.RollSprites)
local View = require(script.Parent.View)

local ACTION = "RollClose"
local POOLS = { "Standard", "Event" }
local POOL = "Standard" -- the Catalog pool the STANDARD tab shows and rolls
local REPLIES = RollFlow.REPLIES
-- Banner emblems (Roll only, no gem pin): Roll_BannerRing (ink 476 x 182 src px) behind Roll_BannerDieSolo (ink 203 x 220), the ring ~2.9x the die width centred on the die.
-- Boxes = scroll-ink fractions per tier. The die's top is >= 2 screen px down; the ring's bottom is >= 4 px above the ROLL caps.
local INK = PlaySprites.ScrollBase.Ink.Height / PlaySprites.ScrollBase.Ink.Width
local function dieBoxes(h, top, inkW, ringUp)
	local scrollH = inkW * INK
	local w = h * 203 / 220
	local rw = 2.8 * w
	local rh = rw * 182 / 476
	local ring = { 0.5 - rw / 2 / inkW, (top + h / 2 - rh / 2 - ringUp) / scrollH, rw / inkW, rh / scrollH }
	local die = { 0.5 - w / 2 / inkW, top / scrollH, w / inkW, h / scrollH }
	return ring, die
end
local RING_FULL, DIE_FULL = dieBoxes(57, -34.6, 488.5, 0)
local RING_COMPACT, DIE_COMPACT = dieBoxes(28, -18.1, 220, 0)
local TIMER_W, SEP_W = 223, 30 -- the Quest Log pill width (full tier)
local PRESS_COOLDOWN = 0.5 -- UX throttle only

local Roll = {}
Roll.__index = Roll

function Roll.new(parent, deps)
	local self = setmetatable({}, Roll)
	local hud = deps.hud
	local conns = {}
	local shell = Shell.new(parent, {
		fit = function()
			return hud:GetBagInsets()
		end,
		name = "Roll",
		free = true,
		tabW = 278.3, -- the Bag's mean tab width: two tabs keep its height, sprites and text role
		tabReserve = SEP_W + TIMER_W + 16, -- (+ the two layout gaps) phones: the tabs shrink to leave this much of the row for the divider and timer
		banner = {
			text = "ROLL",
			textW = 0.45,
			noGem = true,
			emblems = {
				{ sprite = RollSprites.BannerRing, box = { full = RING_FULL, compact = RING_COMPACT } },
				{ sprite = RollSprites.BannerDieSolo, box = { full = DIE_FULL, compact = DIE_COMPACT } },
			},
		},
	})
	shell:SetTabs({ { Id = "Standard", Label = "STANDARD" }, { Id = "Event", Label = "EVENT" } })
	-- rotation timer after the tabs: white divider, then the Quest Log's timer pill
	local bar = shell.TabBar
	local sep = Draw.img(
		bar,
		{ Name = "Sep", LayoutOrder = 5, Size = UDim2.fromOffset(SEP_W, 40), ZIndex = bar.ZIndex + 1 },
		"Frame"
	)
	local divider = Draw.img(sep, {
		Name = "Divider",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4, 31),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, "Frame")
	divider.BackgroundTransparency = 0 -- Draw.img makes frames clear
	local timer = Draw.timerPill(bar, 0, 0, TIMER_W, bar.ZIndex + 1)
	timer.Group.LayoutOrder = 10
	-- no rotation yet: the divider and timer keep their slot in the tab row (the tabs must not move), contents hidden
	divider.Visible = false
	for _, c in timer.Group:GetChildren() do
		if c:IsA("GuiObject") then
			c.Visible = false
		end
	end
	local view = View.new(shell.Slots.Content)

	local result -- the last RollResult of this opening (shown in the featured panel until the menu closes)
	local shown -- the Catalog / Meta fields the last render drew
	-- (pool, gems, allowed, pity count, key of those) from the latest Catalog and Meta
	local function inputs()
		local pool = RollLogic.pool(NetClient.LastCatalog, POOL)
		local meta = NetClient.LastMeta
		local gems = if meta and type(meta.Gems) == "number" then meta.Gems else nil
		local allowed = meta ~= nil and meta.RollAllowed == true
		local pity = RollLogic.pityCount(meta, POOL)
		return pool, gems, allowed, pity, `{pool ~= nil}|{gems}|{allowed}|{pity}`
	end
	local function render()
		local pool, gems, allowed, pity, key = inputs()
		shown = key
		if result then
			view:SetFeatured(RollLogic.resultTiles(result.Results), "YOUR ROLL")
		else
			view:SetFeatured(RollLogic.featured(pool))
		end
		view:SetOdds(RollLogic.oddsRows(pool))
		view:SetPity(if pool then { Count = pity, Max = pool.Pity.Max, Rarity = pool.Pity.Rarity } else nil)
		view:SetButtons(RollLogic.buttons(pool, gems, allowed))
	end

	-- ROLL 1 / ROLL 10: RollFlow gates (one request, 0.6 s spin, 10 s timeout); the server checks everything again.
	-- shortcut: placeholder roll animation, replace with real VFX later
	local flow = RollFlow.new()
	local cooling = false -- short press cooldown (UX only)
	local pressed = 1
	local wake -- the pending flow tick
	local apply
	local function schedule()
		if wake then
			task.cancel(wake)
			wake = nil
		end
		local t = flow:Next()
		if t then
			wake = task.delay(math.max(0, t - os.clock()), function()
				wake = nil
				apply(flow:Tick(os.clock()))
			end)
		end
	end
	function apply(a)
		if a then
			if a.toast then
				deps.toast(a.toast)
			end
			if a.late then -- paid for after the flow moved on: always toast, show it only in an open, idle menu
				deps.toast(RollLogic.resultToast(a.late.Results))
				if shell:IsOpen() and flow:IsIdle() then
					result = a.late
					render()
				end
			elseif a.show == "rolling" then
				view:SetRolling({ Count = pressed, Still = SettingsLogic.get("reducedMotion") == true })
			elseif a.show == "reveal" then
				deps.toast(RollLogic.resultToast(a.result.Results))
				result = a.result
				view:SetRolling(nil)
				view:SetPop(SettingsLogic.get("reducedMotion") ~= true)
				render()
			elseif a.show == "idle" then
				view:SetRolling(nil)
				view:SetPop(false)
				render() -- buttons back to the current Meta's state
			end
		end
		schedule()
	end
	view:OnRoll(function(count)
		local blocked = flow:Blocked()
		if blocked then
			apply(blocked)
			return
		elseif cooling then
			return
		end
		local meta = NetClient.LastMeta
		local pool = RollLogic.pool(NetClient.LastCatalog, POOL)
		if meta == nil or pool == nil then
			deps.toast(REPLIES.NotLoaded)
			return
		elseif meta.RollAllowed ~= true then
			deps.toast(REPLIES.Restricted)
			return
		elseif not RollLogic.canAfford(meta.Gems, RollLogic.price(pool, count)) then
			deps.toast(REPLIES.Insufficient)
			return
		end
		cooling = true
		task.delay(PRESS_COOLDOWN, function()
			cooling = false
		end)
		pressed = count
		local a = flow:Press(os.clock(), SettingsLogic.get("reducedMotion") == true)
		apply(a)
		task.spawn(function()
			local ok, code = NetClient.Request("Roll", POOL, count)
			apply(flow:Reply(a.gen, ok, code, os.clock()))
		end)
	end)
	view:OnInfo(function()
		local pool = RollLogic.pool(NetClient.LastCatalog, POOL)
		deps.toast(
			if pool
				then `Base odds per roll; a {pool.Pity.Rarity} is guaranteed by roll {pool.Pity.Max}`
				else REPLIES.NotLoaded
		)
	end)
	shell:OnTab(function(i)
		view:SetPool(POOLS[i])
	end)
	shell:SetTab(1)

	table.insert(
		conns,
		NetClient.State:Connect(function(snap)
			if not shell:IsOpen() then
				return
			end
			if snap.Phase ~= "Lobby" and snap.Phase ~= "Ended" then
				shell:Close()
			end
		end)
	)
	local function refresh()
		if shell:IsOpen() and flow:IsIdle() and select(5, inputs()) ~= shown then -- only on a visible change, never mid-roll (settle renders)
			render()
		end
	end
	table.insert(conns, NetClient.Meta:Connect(refresh))
	table.insert(conns, NetClient.Catalog:Connect(refresh))
	table.insert(
		conns,
		NetClient.RollResult:Connect(function(r)
			if type(r) ~= "table" or r.Pool ~= POOL or type(r.Results) ~= "table" or #r.Results == 0 then
				return
			end
			apply(flow:Result(r, os.clock()))
		end)
	)
	shell:OnClose(function()
		ContextActionService:UnbindAction(ACTION)
		hud:SetBagMode(false)
		local closed = flow:Close(os.clock())
		if wake then
			task.cancel(wake)
			wake = nil
		end
		view:SetRolling(nil)
		view:SetPop(false)
		result = nil -- the next opening shows the featured dice again
		if closed and closed.late then -- paid for but closed before the reveal: still tell the player
			deps.toast(RollLogic.resultToast(closed.late.Results))
		end
	end)
	table.insert(
		conns,
		GuiService.MenuOpened:Connect(function()
			shell:Close()
		end)
	)

	self.Shell, self.View, self._conns = shell, view, conns
	self._open = function()
		if shell:IsOpen() then
			return
		end
		render()
		shell:Open()
		hud:SetBagMode(true, "Roll")
		local meta = NetClient.LastMeta
		if meta and meta.RollAllowed ~= true then
			deps.toast(REPLIES.Restricted)
		end
		ContextActionService:BindActionAtPriority(ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				shell:Close()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
	end
	return self
end

function Roll:Open()
	self._open()
end

function Roll:Close()
	self.Shell:Close()
end

function Roll:Toggle()
	if self.Shell:IsOpen() then
		self.Shell:Close()
	else
		self._open()
	end
end

function Roll:IsOpen(): boolean
	return self.Shell:IsOpen()
end

function Roll:Destroy()
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)
	if self.Shell:IsOpen() then
		self.Shell:Close() -- unbinds ButtonB and restores the HUD
	end
	self.View:Destroy()
	self.Shell:Destroy()
end

return Roll
