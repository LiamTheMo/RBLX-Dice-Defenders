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

local pads = {} -- cell -> Part
local dice = {} -- cell -> { part, accent, label, key }
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

local function makeDie(cell: number)
	local c = Layout.CellPosition(cell)
	local body = part(
		diceFolder,
		"Die" .. cell,
		Vector3.new(3.4, 3.4, 3.4),
		CFrame.new(c.X, 2.1, c.Z),
		Color3.fromRGB(245, 245, 245)
	)
	body.CanQuery = true
	body:SetAttribute("Cell", cell)
	local accent =
		part(body, "Accent", Vector3.new(3.4, 0.4, 3.4), body.CFrame * CFrame.new(0, 1.7, 0), Color3.new(1, 1, 1))
	accent.CanQuery = false
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(72, 56)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = true
	gui.Parent = body
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(30, 30, 40)
	label.TextStrokeColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	return { part = body, accent = accent, label = label, key = "" }
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
				die.accent.Color = if style then style.Color else Color3.new(1, 1, 1)
				die.label.Text = Display.PipLabel(entry.P)
			end
			die.part.Parent = diceFolder
		elseif die then
			die.part.Parent = nil -- reused when the cell fills again
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
