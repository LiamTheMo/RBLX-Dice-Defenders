-- Client-only world (ground, path, cell pads) and the dice on the board, plus tap
-- to merge. Pure presentation: the server validates every Merge.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Display = require(ReplicatedStorage.Shared.Display)
local Layout = require(ReplicatedStorage.Shared.Layout)
local NetClient = require(script.Parent.NetClient)

local BoardView = {}

local CELLS = Layout.COLS * Layout.ROWS
local PAD_COLOR = Color3.fromRGB(70, 74, 84)
local SELECT_COLOR = Color3.fromRGB(255, 220, 60)
local PARTNER_COLOR = Color3.fromRGB(80, 220, 230)
local PARTNER_OUTLINE = Color3.new(1, 1, 1) -- distinct from every type colour
local LIFT = 0.8

local pads = {} -- cell -> Part
local dice = {} -- cell -> { model, part, base, accent, pips, star, highlight, lifted, key }
local board = {} -- latest Board from State
local playing = false
local selected: number? = nil
local boardKey = ""
local padsFolder: Folder, diceFolder: Folder
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
	local root = world()
	local center = Layout.Camera.LookAt
	part(root, "Ground", Vector3.new(170, 1, 120), CFrame.new(center.X, -0.5, 0), Color3.fromRGB(88, 122, 78))

	local strips = Instance.new("Folder")
	strips.Name = "Path"
	strips.Parent = root
	local points = Layout.Waypoints
	for i = 1, #points - 1 do
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
	part(
		strips,
		"End",
		Vector3.new(5, 0.4, 5),
		CFrame.new(points[#points].X, 0.3, points[#points].Z),
		Color3.fromRGB(220, 70, 70)
	)

	padsFolder = Instance.new("Folder")
	padsFolder.Name = "Pads"
	padsFolder.Parent = root
	diceFolder = Instance.new("Folder")
	diceFolder.Name = "Dice"
	diceFolder.Parent = root
	for i = 1, CELLS do
		local c = Layout.CellPosition(i)
		local pad = part(padsFolder, "Pad" .. i, Vector3.new(5.4, 0.4, 5.4), CFrame.new(c.X, 0.2, c.Z), PAD_COLOR)
		pad:SetAttribute("Cell", i)
		pads[i] = pad
	end
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { padsFolder, diceFolder }
end

local DIE = 4.4 -- pads are 5.4 studs, cell spacing 6
local HALF = DIE / 2
local PIP_D = 1.2
local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- lays a Cylinder's axis along Y
local PIP_COLOR = Color3.fromRGB(25, 25, 30)
-- Standard die faces on the top: offsets (right, back) in studs, up to 6 slots.
local G = 1.3 -- pip edge 1.9 of 2.2, margin .3
local PIP_LAYOUTS = {
	{ { 0, 0 } },
	{ { -G, -G }, { G, G } },
	{ { -G, -G }, { 0, 0 }, { G, G } },
	{ { -G, -G }, { G, -G }, { -G, G }, { G, G } },
	{ { -G, -G }, { G, -G }, { 0, 0 }, { -G, G }, { G, G } },
	{ { -G, -G }, { G, -G }, { -G, 0 }, { G, 0 }, { -G, G }, { G, G } },
}

local function makeDie(cell: number)
	local c = Layout.CellPosition(cell)
	local model = Instance.new("Model")
	model.Name = "Die" .. cell
	local body =
		part(model, "Body", Vector3.new(DIE, DIE, DIE), CFrame.new(c.X, 0.4 + HALF, c.Z), Color3.fromRGB(245, 245, 245))
	body.CanQuery = true
	body:SetAttribute("Cell", cell)
	model.PrimaryPart = body
	-- Type colour: a band around the lower sides, so the top face stays white.
	local band = part(
		body,
		"Band",
		Vector3.new(DIE + 0.1, HALF, DIE + 0.1),
		body.CFrame * CFrame.new(0, -HALF / 2, 0),
		Color3.new(1, 1, 1)
	)
	band.CanQuery = false
	local pips = {}
	for i = 1, 6 do
		local pip = part(body, "Pip" .. i, Vector3.new(0.1, PIP_D, PIP_D), body.CFrame, PIP_COLOR)
		pip.Shape = Enum.PartType.Cylinder
		pip.Material = Enum.Material.Neon -- unlit flat colour; SmoothPlastic glare washed pips out
		pip.CanQuery = false
		pip.Parent = nil
		pips[i] = pip
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.Enabled = false
	gui.Parent = body
	local star = Instance.new("TextLabel")
	star.Size = UDim2.fromScale(1, 1)
	star.BackgroundTransparency = 1
	star.Font = Enum.Font.GothamBlack
	star.Text = "\u{2605}"
	star.TextScaled = true
	star.TextColor3 = Color3.fromRGB(255, 190, 30)
	star.Parent = gui
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
		base = body.CFrame,
		accent = band,
		pips = pips,
		star = gui,
		highlight = highlight,
		lifted = false,
		key = "",
	}
end

-- Pip 1-6: dark discs on the top face; pip 7: one large gold star.
local function setPips(die, pip: number, color: Color3)
	local layout = PIP_LAYOUTS[pip]
	die.star.Enabled = layout == nil
	for i, disc in die.pips do
		local slot = layout and layout[i]
		if slot then
			disc.Color = color
			disc.CFrame = die.part.CFrame * CFrame.new(slot[1], HALF + 0.05, slot[2]) * FLAT
			disc.Parent = die.part
		else
			disc.Parent = nil
		end
	end
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
				die.model:PivotTo(die.base * CFrame.new(0, if isSelected then LIFT else 0, 0))
			end
		end
	end
end

local function render(snapshot)
	playing = snapshot.Phase == "Playing"
	board = snapshot.Board or {}
	local parts = {}
	for i = 1, CELLS do
		local entry = board[i]
		parts[i] = if entry then entry.T .. entry.P else "-"
		local die = dice[i]
		if entry then
			if die == nil then
				die = makeDie(i)
				dice[i] = die
			end
			if die.key ~= parts[i] then
				die.key = parts[i]
				local style = Display.Dice[entry.T]
				local color = if style then style.Color else Color3.new(1, 1, 1)
				die.accent.Color = color
				setPips(die, entry.P, color:Lerp(Color3.new(0, 0, 0), 0.6)) -- dark saturated type shade
			end
			die.model.Parent = diceFolder
		elseif die then
			die.model.Parent = nil -- reused when the cell fills again
			die.key = ""
		end
	end
	local key = table.concat(parts, ",")
	if key ~= boardKey or not playing then
		selected = nil -- never merge from a stale selection
	end
	boardKey = key
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
	UserInputService.InputBegan:Connect(onInput)
	NetClient.State:Connect(render)
	if NetClient.Last then
		render(NetClient.Last)
	end
end

return BoardView
