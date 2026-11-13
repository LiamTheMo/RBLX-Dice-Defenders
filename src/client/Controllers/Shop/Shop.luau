-- Shop menu controller: one Shell (banner, close, FEATURED / GAMEPASSES / GEMS / SHARDS tabs) hosting the Shop View.
-- Shop.new(parent, { hud = LobbyHud, toast = (string) -> () }) -> :Open() :Close() :Toggle() :IsOpen() :Destroy()
-- Display only from the client-only SampleData: a price press just toasts; nothing is bought, spent or sent.

local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local NetClient = require(script.Parent.Parent.NetClient)
local PlaySprites = require(script.Parent.Parent.Play.PlaySprites)
local QuestSprites = require(script.Parent.Parent.QuestLog.QuestSprites)
local SampleData = require(script.Parent.SampleData)
local Shell = require(script.Parent.Parent.Bag.Shell)
local ShopLogic = require(script.Parent.ShopLogic)
local ShopSprites = require(script.Parent.ShopSprites)
local Sprites = require(script.Parent.Parent.Sprites)
local View = require(script.Parent.View)

local ACTION = "ShopClose"
local PRESS_COOLDOWN = 0.5 -- UX throttle only
local TAB_ICONS = {
	FEATURED = ShopSprites.IconStar,
	GAMEPASSES = QuestSprites.Crown,
	GEMS = Sprites.Gem,
	SHARDS = ShopSprites.IconShards,
}
-- Banner emblems (scroll-ink fractions). The chest is the side emblem: height 0.765 and top -0.077 as the Play swords; width from its ink
-- aspect (278 x 246 src px) on the 774 x 162 scroll ink: 0.765 * 162 * (278 / 246) / 774 = 0.181. Laurels: the Play pair.
local CHEST = { 0, -0.11, 0.208, 0.88 }

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

	local flight = ShopLogic.guard()
	view:OnAction(function(_productId)
		if not flight.begin() then
			return
		end
		task.delay(PRESS_COOLDOWN, flight.finish)
		deps.toast("Shop: coming soon")
	end)
	shell:OnTab(function(i)
		view:SetSections(ShopLogic.sectionsFor(ShopLogic.TABS[i].Id, SampleData))
	end)

	table.insert(
		conns,
		NetClient.State:Connect(function(snap)
			if shell:IsOpen() and snap.Phase ~= "Lobby" and snap.Phase ~= "Ended" then
				shell:Close() -- a match started
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

	local preloaded = false
	self.Shell, self.View, self._conns = shell, view, conns
	self._open = function()
		if shell:IsOpen() then
			return
		end
		if not preloaded then
			preloaded = true
			task.spawn(pcall, ContentProvider.PreloadAsync, ContentProvider, { shell.Bag }) -- stream the art so the first frame is not blank
			shell:SetTab(1) -- FEATURED on first open
		end
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
