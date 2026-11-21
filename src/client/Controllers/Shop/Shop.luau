-- Shop menu controller: one scrollable page of offers, gem packs and upcoming sections.
-- Shop.new(parent, { hud = LobbyHud, toast = (string) -> () }) -> :Open() :Close() :Toggle() :IsOpen() :Destroy()
-- Renders the server's Catalog.Shop offers with the Gems (Meta) and Gold (State) balances. A Gold or Gems offer sends Buy(id);
-- an available Robux offer only prompts the developer product (the server grants it from the Marketplace receipt); an
-- offer without a ProductId shows "Not available yet". GAMEPASSES shows the VIP pass card (PromptGamePassPurchase; "Coming soon" while the
-- server offers no pass); SHARDS shows the "Coming soon" card.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local NetClient = require(script.Parent.Parent.NetClient)
local Shell = require(script.Parent.Parent.Bag.Shell)
local ShopLogic = require(script.Parent.ShopLogic)
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
		banner = { text = "SHOP" },
	})
	local view = View.new(shell.Slots.Content)

	local shown -- ShopLogic.key of the last render
	local function data()
		return ShopLogic.data(NetClient.LastCatalog, NetClient.LastMeta, NetClient.Last)
	end
	local function render(keepScroll: boolean)
		local d = data()
		shown = ShopLogic.key(d)
		view:SetSections(ShopLogic.sections(d), keepScroll)
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
		if offerId == ShopLogic.VIP_ID then -- the VIP game pass: the server learns of the purchase from PromptGamePassPurchaseFinished
			task.delay(PRESS_COOLDOWN, flight.finish)
			local vip = d and d.Vip
			if vip and vip.Offer then
				pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, Players.LocalPlayer, vip.Offer.PassId)
			else
				deps.toast("Already owned")
			end
			return
		end
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

	self.Shell, self.View, self._conns = shell, view, conns
	self._open = function()
		if shell:IsOpen() then
			return
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
