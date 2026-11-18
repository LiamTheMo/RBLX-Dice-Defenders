-- Roll menu controller: one Shell (banner, close, STANDARD / EVENT tabs) hosting the Roll View.
-- Roll.new(parent, { hud = LobbyHud, toast = (string) -> () }) -> :Open() :Close() :Toggle() :IsOpen() :Destroy()
-- Renders the server's numbers only: odds, prices, pity max and featured dice from Catalog.Roll, Gems / pity count /
-- RollAllowed from Meta. ROLL 1 / ROLL 10 send Roll(pool, count); the draw arrives as RollResult (shown in the featured
-- panel as "YOUR ROLL" until the menu closes, plus a toast). Not allowed (paid random items policy): buttons off and
-- "Not available in your region". The EVENT tab shows "No event right now"; no rotation timer exists (plan A8), so none is drawn and the tab row has no gap for one.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local NetClient = require(script.Parent.Parent.NetClient)
local RollFlow = require(script.Parent.RollFlow)
local RollLogic = require(script.Parent.RollLogic)
local SettingsLogic = require(script.Parent.Parent.Settings.SettingsLogic)
local Shell = require(script.Parent.Parent.Bag.Shell)
local View = require(script.Parent.View)

local ACTION = "RollClose"
local POOLS = { "Standard", "Event" }
local POOL = "Standard" -- the Catalog pool the STANDARD tab shows and rolls
local REPLIES = RollFlow.REPLIES
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
		tabW = 296, -- mockup STANDARD 296 / EVENT 284 (mean)
		banner = { text = "ROLL" },
	})
	shell:SetTabs({ { Id = "Standard", Label = "STANDARD" }, { Id = "Event", Label = "EVENT" } })
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
		view:SetNotice(if not allowed then "region" elseif gems ~= nil then "gems" else nil) -- why a disabled button is off (its chip says so)
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
