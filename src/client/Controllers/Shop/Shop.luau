-- Shop menu controller: one Shell (banner, close, FEATURED / GAMEPASSES / GEMS / SHARDS tabs) hosting the Shop View.
-- Shop.new(parent, { hud = LobbyHud, toast = (string) -> () }) -> :Open() :Close() :Toggle() :IsOpen() :Destroy()
-- Renders the server's Catalog.Shop offers with the Gems (Meta) and Gold (State) balances. A Gold or Gems offer sends Buy(id);
-- an available Robux offer only prompts the developer product (the server grants it from the Marketplace receipt); an
-- offer without a ProductId shows "Not available yet". GAMEPASSES and SHARDS show the "Coming soon" card.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local NetClient = require(script.Parent.Parent.NetClient)
local PlaySprites = require(script.Parent.Parent.Play.PlaySprites)
local QuestSprites = require(script.Parent.Parent.QuestLog.QuestSprites)
local Shell = require(script.Parent.Parent.Bag.Shell)
local ShopLogic = require(script.Parent.ShopLogic)
local ShopSprites = require(script.Parent.ShopSprites)
local Sprites = require(script.Parent.Parent.Sprites)
local View = require(script.Parent.View)

local ACTION = "ShopClose"
local PRESS_COOLDOWN = 0.5 -- UX throttle only
local REPLIES = {
	Insufficient = "Not enough currency",
	SoldOut = "Already owned",
	UnknownOffer = "Not available yet",
	NotAvailable = "Not available yet",
	Overflow = "You can't hold that much",
	NotLoaded = "Still loading",
	NotOwner = "This server is in use",
	Throttled = "Slow down",
	RateLimited = "Slow down",
	Network = "Connection problem",
	Error = "Something went wrong",
}
local TAB_ICONS = {
	FEATURED = ShopSprites.IconStar,
	GAMEPASSES = QuestSprites.Crown,
	GEMS = Sprites.Gem,
	SHARDS = ShopSprites.IconShards,
}
-- Banner side emblem (scroll-ink fractions; y is overridden by the title centring): the chest at 0.89x the first cut so its ink stays >= 4 px off
-- the Play laurel, 0.81x on Compact (as the Play swords) so it clears the gem pin. Width from the ink aspect (278 x 246): 0.782 * 162 * 1.13 / 774.
local CHEST = { full = { 0, -0.07, 0.181, 0.766 }, compact = { 0, 0.01, 0.15, 0.633 } }

local Shop = {}
Shop.__index = Shop

function Shop.new(parent, deps)
	local self = setmetatable({}, Shop)
	local hud = deps.hud
	local conns = {}
	local shell = Shell.new(parent, {
		fit = function()
			return hud:GetBagInsets()
		end,
		name = "Shop",
		free = true,
		banner = {
			text = "SHOP",
			emblems = {
				{ sprite = PlaySprites.LaurelL, box = { 0.1379, 0.157, 0.1061, 0.645 } },
				{ sprite = PlaySprites.LaurelR, box = { 0.7560, 0.157, 0.1061, 0.645 } },
				{ sprite = ShopSprites.Emblem, box = CHEST, side = true },
			},
		},
	})
	local tabs = {}
	for i, tab in ShopLogic.TABS do
		tabs[i] = { Id = tab.Id, Label = tab.Label, Icon = TAB_ICONS[tab.Id] }
	end
	shell:SetTabs(tabs)
	local view = View.new(shell.Slots.Content)

	local tab = 1
	local shown -- ShopLogic.key of the last render
	local function data()
		return ShopLogic.data(NetClient.LastCatalog, NetClient.LastMeta, NetClient.Last)
	end
	local function render(keepScroll: boolean)
		local d = data()
		shown = ShopLogic.key(d)
		local everyTab = {}
		for _, t in ShopLogic.TABS do
			for _, sec in ShopLogic.sectionsFor(t.Id, d) do
				table.insert(everyTab, sec)
			end
		end
		view:SetRoleSample(everyTab)
		view:SetSections(ShopLogic.sectionsFor(ShopLogic.TABS[tab].Id, d), keepScroll)
	end
	local function refresh()
		if shell:IsOpen() and ShopLogic.key(data()) ~= shown then -- redraw only on a visible change
			render(true)
		end
	end

	local flight = ShopLogic.guard()
	view:OnAction(function(offerId)
		if not flight.begin() then
			return
		end
		local d = data()
		local offer = ShopLogic.offer(d, offerId)
		local action, arg = ShopLogic.press(offer, d)
		if action == "Buy" then
			task.spawn(function()
				local ok, code = NetClient.Request("Buy", offerId)
				deps.toast(if ok then `Bought {(offer :: any).Name}` else REPLIES[code] or tostring(code))
				task.delay(PRESS_COOLDOWN, flight.finish)
			end)
			return
		end
		task.delay(PRESS_COOLDOWN, flight.finish)
		if action == "Prompt" then
			pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, Players.LocalPlayer, arg) -- the server grants on the receipt
		else
			deps.toast(arg)
		end
	end)
	shell:OnTab(function(i)
		tab = i
		render(false)
	end)
	table.insert(conns, NetClient.Meta:Connect(refresh))
	table.insert(conns, NetClient.Catalog:Connect(refresh))

	table.insert(
		conns,
		NetClient.State:Connect(function(snap)
			if shell:IsOpen() and snap.Phase ~= "Lobby" and snap.Phase ~= "Ended" then
				shell:Close() -- a match started
			else
				refresh() -- Gold lives in State
			end
		end)
	)
	shell:OnClose(function()
		ContextActionService:UnbindAction(ACTION)
		hud:SetBagMode(false)
	end)
	table.insert(
		conns,
		GuiService.MenuOpened:Connect(function()
			shell:Close()
		end)
	)

	local opened = false
	self.Shell, self.View, self._conns = shell, view, conns
	self._open = function()
		if shell:IsOpen() then
			return
		end
		if not opened then
			opened = true
			shell:SetTab(1) -- FEATURED on first open
		end
		render(false) -- the balances and offers as of now
		shell:Open()
		hud:SetBagMode(true, "Shop")
		ContextActionService:BindActionAtPriority(ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				shell:Close()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
	end
	return self
end

function Shop:Open()
	self._open()
end

function Shop:Close()
	self.Shell:Close()
end

function Shop:Toggle()
	if self.Shell:IsOpen() then
		self.Shell:Close()
	else
		self._open()
	end
end

function Shop:IsOpen(): boolean
	return self.Shell:IsOpen()
end

function Shop:Destroy()
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

return Shop
