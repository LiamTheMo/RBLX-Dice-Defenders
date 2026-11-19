-- Client-only world (ground, path, cell pads) and the dice on the board, plus tap
-- to merge. Pure presentation: the server validates every Merge. The arena is only
-- in the workspace while a run is playing; between runs players walk the lobby map.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Display = require(ReplicatedStorage.Shared.Display)
local Layout = require(ReplicatedStorage.Shared.Layout)
local NetClient = require(script.Parent.NetClient)
local DiceVisuals = require(script.Parent.Dice.Visuals)
local SettingsLogic = require(script.Parent.Settings.SettingsLogic)

local BoardView = {}

local CELLS = Layout.COLS * Layout.ROWS
local PAD_COLOR = Color3.fromRGB(70, 74, 84)
local SELECT_COLOR = Color3.fromRGB(255, 220, 60)
local PARTNER_COLOR = Color3.fromRGB(80, 220, 230)
local PARTNER_OUTLINE = Color3.new(1, 1, 1) -- distinct from every type colour
local LIFT = 0.8
local MIN_DIE_SCALE = 0.001
local SHRINK_TIME = 0.1
local EXPAND_TIME = 0.25

local pads = {} -- cell -> Part
local dice = {} -- cell -> { model, part, pad, highlight, lifted, key }
local allyDice = {}
local seat, playerCount = 1, 1
local animations = {} -- die -> current transition
local board = {} -- latest Board from State
local playing = false
local selected: number? = nil
local boardKey = ""
local padsFolder: Folder, diceFolder: Folder
local root: Folder, arena: Folder
local rayParams = RaycastParams.new()

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function world(): Folder
	local folder = workspace:FindFirstChild("ClientWorld")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "ClientWorld"
		folder.Parent = workspace
	end
	return folder
end

local function buildWorld()
	if arena then
		for _, collection in { dice, allyDice } do
			for _, die in collection do
				die.model:Destroy()
			end
			table.clear(collection)
		end
		table.clear(animations)
		table.clear(pads)
		arena:Destroy()
	end
	root = world()
	arena = Instance.new("Folder") -- parented by render() only while playing
	arena.Name = "Arena"
	local center = Layout.Camera.LookAt
	part(
		arena,
		"Ground",
		Vector3.new(170, 1, 120),
		CFrame.new(center.X, -0.5, Layout.ORIGIN.Z),
		Color3.fromRGB(88, 122, 78)
	)

	local strips = Instance.new("Folder")
	strips.Name = "Path"
	strips.Parent = arena
	for lane = 1, playerCount do
		local points = Layout.Path(lane, playerCount)
		for i = 1, #points - 1 do
			if lane == 2 and i == #points - 1 then
				break -- shared exit stretch already built by lane one
			end
			local a, b = points[i], points[i + 1]
			local length = (b - a).Magnitude
			part(
				strips,
				"Strip",
				Vector3.new(7, 0.2, length + 7),
				CFrame.lookAt(Vector3.new((a.X + b.X) / 2, 0.1, (a.Z + b.Z) / 2), Vector3.new(b.X, 0.1, b.Z)),
				Color3.fromRGB(150, 120, 80)
			)
		end
		part(
			strips,
			"Start",
			Vector3.new(5, 0.4, 5),
			CFrame.new(points[1].X, 0.3, points[1].Z),
			Color3.fromRGB(60, 200, 90)
		)
		if lane == 1 then
			part(
				strips,
				"End",
				Vector3.new(5, 0.4, 5),
				CFrame.new(points[#points].X, 0.3, points[#points].Z),
				Color3.fromRGB(220, 70, 70)
			)
		end
	end

	padsFolder = Instance.new("Folder")
	padsFolder.Name = "Pads"
	padsFolder.Parent = arena
	diceFolder = Instance.new("Folder")
	diceFolder.Name = "Dice"
	diceFolder.Parent = arena
	for side = 1, playerCount do
		for i = 1, CELLS do
			local c = Layout.CellPosition(i, side, playerCount)
			local color = if side == seat then PAD_COLOR else Color3.fromRGB(63, 87, 98)
			local pad = part(padsFolder, "Pad" .. i, Vector3.new(5.4, 0.4, 5.4), CFrame.new(c.X, 0.2, c.Z), color)
			if side == seat then
				pad:SetAttribute("Cell", i)
				pads[i] = pad
			end
		end
	end
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { padsFolder, diceFolder }
end

local function positionDie(die)
	local height = die.part.Size.Y / 2 + (if die.lifted then LIFT else 0)
	die.model:PivotTo(die.pad * CFrame.new(0, height, 0))
end

local function scaleDie(die, scale: number)
	die.model:ScaleTo(scale)
	positionDie(die)
end

local function applyDie(die, entry)
	die.model:ScaleTo(1)
	die.part.Size = Vector3.one * DiceVisuals.Size(entry.T)
	positionDie(die)
	local style = Display.Dice[entry.T]
	DiceVisuals.Apply(die.part, entry.T, entry.P, if style then style.Color else Color3.new(1, 1, 1))
end

local function hideDie(die)
	animations[die] = nil
	die.model.Parent = nil
	die.lifted = false
end

local function animateDie(die, now: number, shrinking: boolean, result)
	animations[die] = {
		start = now,
		from = die.model:GetScale(),
		shrink = if shrinking then SHRINK_TIME else 0,
		swapped = not shrinking,
		result = result,
	}
	if not shrinking then
		scaleDie(die, MIN_DIE_SCALE)
	end
end

local function stepAnimations()
	if next(animations) == nil then
		return
	end
	local now = os.clock()
	local still = SettingsLogic.get("reducedMotion")
	for die, animation in animations do
		local elapsed = if still then math.huge else now - animation.start
		if elapsed < animation.shrink then
			local t = elapsed / animation.shrink
			scaleDie(die, animation.from + (MIN_DIE_SCALE - animation.from) * t * t)
		else
			if not animation.swapped then
				if not animation.result then
					hideDie(die)
					continue
				end
				applyDie(die, animation.result)
				animation.swapped = true
			end
			local t = math.min(1, (elapsed - animation.shrink) / EXPAND_TIME)
			scaleDie(die, 1 - (1 - MIN_DIE_SCALE) * (1 - t) ^ 2)
			if t == 1 then
				animations[die] = nil
			end
		end
	end
end

local function makeDie(cell: number, side: number)
	local c = Layout.CellPosition(cell, side, playerCount)
	local model = Instance.new("Model")
	model.Name = "Die" .. cell
	local body = part(model, "Body", Vector3.one, CFrame.identity, Color3.new(1, 1, 1))
	body.CanQuery = true
	if side == seat then
		body:SetAttribute("Cell", cell)
	end
	model.PrimaryPart = body
	local highlight = Instance.new("Highlight")
	highlight.Adornee = model
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = model
	return {
		model = model,
		part = body,
		pad = CFrame.new(c.X, 0.4, c.Z),
		highlight = highlight,
		lifted = false,
		key = "",
	}
end

local function canMerge(a: number, b: number): boolean
	local x, y = board[a], board[b]
	return a ~= b and x and y and x.T == y.T and x.P == y.P and x.P <= 6 or false
end

local function refreshPads()
	for i = 1, CELLS do
		local color = PAD_COLOR
		if selected == i then
			color = SELECT_COLOR
		elseif selected and canMerge(selected, i) then
			color = PARTNER_COLOR
		end
		pads[i].Color = color
		local die = dice[i]
		if die and board[i] then
			local isSelected = selected == i
			local isPartner = not isSelected and selected ~= nil and canMerge(selected, i)
			die.highlight.Enabled = isSelected or isPartner
			die.highlight.OutlineColor = if isSelected then SELECT_COLOR else PARTNER_OUTLINE
			if die.lifted ~= isSelected then
				die.lifted = isSelected
				positionDie(die)
			end
		end
	end
end

local function render(snapshot)
	local previous = board
	playing = snapshot.Phase == "Playing"
	if playing and ((snapshot.Seat or 1) ~= seat or (snapshot.PlayerCount or 1) ~= playerCount) then
		seat, playerCount = snapshot.Seat or 1, snapshot.PlayerCount or 1
		previous, selected, boardKey = {}, nil, ""
		buildWorld()
	end
	arena.Parent = if playing then root else nil
	board = if playing then snapshot.Board or {} else {}
	local still = SettingsLogic.get("reducedMotion")
	local now = os.clock()
	local parts = {}
	for i = 1, CELLS do
		local entry = board[i]
		local before = previous[i]
		parts[i] = if entry then entry.T .. entry.P else "-"
		local die = dice[i]
		if entry then
			if die == nil then
				die = makeDie(i, seat)
				dice[i] = die
			end
			if die.key ~= parts[i] then
				die.key = parts[i]
				if not still and before and entry.P > before.P then
					animateDie(die, now, true, entry)
				else
					animations[die] = nil
					applyDie(die, entry)
					if not still and not before then
						animateDie(die, now, false)
					end
				end
			end
			die.model.Parent = diceFolder
		elseif die and (die.key ~= "" or not playing) then
			die.key = ""
			die.highlight.Enabled = false
			die.lifted = false
			positionDie(die)
			if playing and before and not still then
				animateDie(die, now, true)
			else
				hideDie(die)
			end
		end
	end
	local key = table.concat(parts, ",")
	if key ~= boardKey or not playing then
		selected = nil -- never merge from a stale selection
	end
	boardKey = key
	local ally = if playing then snapshot.PartnerBoard else nil
	for i = 1, CELLS do
		local entry = if ally then ally[i] else nil
		local die = allyDice[i]
		if entry then
			if not die then
				die = makeDie(i, 3 - seat)
				allyDice[i] = die
			end
			local key = entry.T .. entry.P
			if die.key ~= key then
				die.key = key
				applyDie(die, entry)
			end
			die.model.Parent = diceFolder
		elseif die then
			die.model.Parent = nil
		end
	end
	refreshPads()
end

local function onTap(cell: number)
	if not playing then
		return
	end
	if selected == nil then
		if board[cell] then
			selected = cell
		end
	elseif canMerge(selected, cell) then
		task.spawn(NetClient.Request, "Merge", selected, cell)
		selected = nil
	elseif cell ~= selected and board[cell] then
		selected = cell
	else
		selected = nil -- tap A again, or empty: clear
	end
	refreshPads()
end

local function onInput(input: InputObject, processed: boolean)
	if processed then
		return
	end
	local kind = input.UserInputType
	if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
		return
	end
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local inset = GuiService:GetGuiInset()
	local ray = camera:ViewportPointToRay(input.Position.X + inset.X, input.Position.Y + inset.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
	local cell = hit and hit.Instance:GetAttribute("Cell")
	if type(cell) == "number" then
		onTap(cell)
	end
end

function BoardView.Start()
	buildWorld()
	RunService.RenderStepped:Connect(stepAnimations)
	UserInputService.InputBegan:Connect(onInput)
	NetClient.State:Connect(render)
	if NetClient.Last then
		render(NetClient.Last)
	end
end

return BoardView
