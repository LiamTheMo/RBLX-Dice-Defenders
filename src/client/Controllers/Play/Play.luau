-- Play menu controller: one Shell (banner, close; no tabs) hosting the Play View.
-- Play.new(parent, { hud = LobbyHud, toast = (string) -> () }) -> :Open() :Close() :Toggle() :IsOpen() :Destroy()
-- Exposes .View and .Shell so the behaviour layer (Start, State) can wire View:OnStart / OnSelect / OnLocked next.
-- Renders once on open from PlayLogic with NetClient.Last and the client-only SampleData (Studio shows the full reference).

local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local NetClient = require(script.Parent.Parent.NetClient)
local PlayLogic = require(script.Parent.PlayLogic)
local PlaySprites = require(script.Parent.PlaySprites)
local SampleData = require(script.Parent.SampleData)
local Shell = require(script.Parent.Parent.Bag.Shell)
local Sprites = require(script.Parent.Parent.Sprites)
local View = require(script.Parent.View)

local ACTION = "PlayClose"

-- Banner: the ScrollBase sprite scaled so its scroll ink is the Quest Log scroll's ink (Quest_Banner ink x 7-963, y 82-270 of
-- 970x279 drawn at 0.51 full / 0.2296 compact: 488.5 / 220 wide, centre y -0.8 full / -5.6 compact below the window top).
local SB = PlaySprites.ScrollBase
local K_FULL, K_COMPACT = 488.5 / SB.Ink.Width, 220 / SB.Ink.Width
local INK_CY = (SB.Ink.Min.Y + SB.Ink.Max.Y) / 2

-- Emblems: ink boxes measured on the reference as fractions of a 494.7x142.3 box whose scroll ink is (0.006, 0.257, 0.988, 0.720).
local R_INK = { 0.006, 0.257, 0.988, 0.720 }
local EMBLEMS = {
	{ sprite = PlaySprites.LaurelL, box = { 0.149, 0.362, 0.104, 0.480 } },
	{ sprite = PlaySprites.LaurelR, box = { 0.738, 0.362, 0.104, 0.480 } },
	{ sprite = PlaySprites.GemPin, box = { 0.427, 0.772, 0.147, 0.228 } },
	{ sprite = Sprites.Icon.Play, box = { 0.223, 0.216, 0.180, 0.585 } },
}

local function addEmblems(banner)
	local sb = SB.Size
	local inkX, inkY, inkW, inkH = SB.Ink.Min.X / sb.X, SB.Ink.Min.Y / sb.Y, SB.Ink.Width / sb.X, SB.Ink.Height / sb.Y
	for _, e in EMBLEMS do
		local fx, fy, fw, fh = table.unpack(e.box)
		-- reference box -> fractions of the scroll ink -> fractions of the banner sprite box
		local x = inkX + (fx - R_INK[1]) / R_INK[3] * inkW
		local y = inkY + (fy - R_INK[2]) / R_INK[4] * inkH
		local w, h = fw / R_INK[3] * inkW, fh / R_INK[4] * inkH
		local img = Instance.new("ImageLabel")
		img.Name = "Emblem"
		img.BackgroundTransparency = 1
		img.ZIndex = banner.ZIndex + 1
		img.ScaleType = Enum.ScaleType.Fit
		local r = e.sprite
		if type(r) == "table" then -- draw by ink: the sprite's transparent margin extends the box
			local ix, iy, iw, ih =
				r.Ink.Min.X / r.Size.X, r.Ink.Min.Y / r.Size.Y, r.Ink.Width / r.Size.X, r.Ink.Height / r.Size.Y
			img.Image = r.Image
			img.Position = UDim2.fromScale(x - ix / iw * w, y - iy / ih * h)
			img.Size = UDim2.fromScale(w / iw, h / ih)
		else
			img.Image = r
			img.Position = UDim2.fromScale(x, y)
			img.Size = UDim2.fromScale(w, h)
		end
		img.Parent = banner
	end
end

local Play = {}
Play.__index = Play

function Play.new(parent, deps)
	local self = setmetatable({}, Play)
	local hud = deps.hud
	local conns = {}
	local fullSize = Vector2.new(SB.Size.X * K_FULL, SB.Size.Y * K_FULL)
	local compactSize = Vector2.new(SB.Size.X * K_COMPACT, SB.Size.Y * K_COMPACT)
	local shell = Shell.new(parent, {
		fit = function()
			return hud:GetBagInsets()
		end,
		name = "Play",
		free = true,
		banner = {
			sprite = SB,
			full = fullSize,
			compact = compactSize,
			top = -0.8 - INK_CY * K_FULL, -- scroll ink centre level with the Quest Log's
			topCompact = -5.6 - INK_CY * K_COMPACT,
			text = "PLAY",
			textPos = UDim2.fromScale(0.57, 0.457), -- the reference text centre sits 42 ref px right of the scroll centre (swords left)
			textSize = UDim2.fromScale(0.36, 0.42),
			textFull = 46,
			textCompact = 22,
		},
	})
	addEmblems(shell.Banner)
	local view = View.new(shell.Slots.Content)

	local preloaded, busy = false, false
	local function preload() -- first open only: stream the art so the first frame is not blank
		if preloaded then
			return
		end
		preloaded = true
		task.spawn(pcall, ContentProvider.PreloadAsync, ContentProvider, { shell.Bag }) -- Bag draws every Play sprite
	end

	local function render()
		local snap = NetClient.Last
		local sample = SampleData.get(RunService:IsStudio())
		view:SetWorlds(PlayLogic.worlds(snap, sample))
		view:SetSelected(PlayLogic.WORLD.Id)
		view:SetMilestones(PlayLogic.milestones(snap, sample), PlayLogic.worldClear(snap))
		view:SetRepeat(sample.Tiles, sample.Odds)
		view:SetStartState(PlayLogic.startState(snap, busy))
	end

	view:OnSelect(function(id)
		view:SetSelected(id)
	end)
	view:OnLocked(function()
		deps.toast("Coming soon!")
	end)
	view:OnStart(function()
		if busy then
			return
		end
		busy = true
		render()
		task.spawn(function()
			local ok = NetClient.Request("Start") -- a rejection toast comes from Lobby
			busy = false
			if ok then
				shell:Close() -- the match is starting
			elseif shell:IsOpen() then
				render()
			end
		end)
	end)
	table.insert(
		conns,
		NetClient.State:Connect(function(snap)
			if not shell:IsOpen() then
				return
			end
			if snap.Phase ~= "Lobby" and snap.Phase ~= "Ended" then
				shell:Close()
			else
				render()
			end
		end)
	)

	shell:OnClose(function()
		ContextActionService:UnbindAction(ACTION)
		view:SetScroll(0)
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
		preload()
		render()
		shell:Open()
		hud:SetBagMode(true)
		ContextActionService:BindActionAtPriority(ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				shell:Close()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
	end
	return self
end

function Play:Open()
	self._open()
end

function Play:Close()
	self.Shell:Close()
end

function Play:Toggle()
	if self.Shell:IsOpen() then
		self.Shell:Close()
	else
		self._open()
	end
end

function Play:IsOpen(): boolean
	return self.Shell:IsOpen()
end

function Play:Destroy()
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

return Play
