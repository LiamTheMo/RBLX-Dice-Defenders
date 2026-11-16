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
local RollLogic = require(script.Parent.RollLogic)
local Shell = require(script.Parent.Parent.Bag.Shell)
local RollSprites = require(script.Parent.RollSprites)
local View = require(script.Parent.View)

local ACTION = "RollClose"
local POOLS = { "Standard", "Event" }
local POOL = "Standard" -- the Catalog pool the STANDARD tab shows and rolls
local REPLIES = {
	Restricted = "Not available in your region",
	Insufficient = "Not enough Gems",
	UnknownPool = "Roll unavailable",
	UnknownPrice = "Roll unavailable",
	Overflow = "You can't hold that much",
	NotLoaded = "Still loading",
	NotOwner = "This server is in use",
	Throttled = "Slow down",
	RateLimited = "Slow down",
	Network = "Connection problem",
	Error = "Something went wrong",
}
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

	-- ROLL 1 / ROLL 10: one request in flight plus a short cooldown (UX only; the server checks everything again).
	local inFlight, cooling = false, false
	view:OnRoll(function(count)
		if inFlight or cooling then
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
		inFlight, cooling = true, true
		task.delay(PRESS_COOLDOWN, function()
			cooling = false
		end)
		task.spawn(function()
			local ok, code = NetClient.Request("Roll", POOL, count)
			inFlight = false
			if not ok then
				deps.toast(REPLIES[code] or tostring(code))
			end
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
		if shell:IsOpen() and select(5, inputs()) ~= shown then -- rebuild only on a visible change
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
			deps.toast(RollLogic.resultToast(r.Results))
			if shell:IsOpen() then
				result = r
				render()
			end
		end)
	)
	shell:OnClose(function()
		ContextActionService:UnbindAction(ACTION)
		hud:SetBagMode(false)
		result = nil -- the next opening shows the featured dice again
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
