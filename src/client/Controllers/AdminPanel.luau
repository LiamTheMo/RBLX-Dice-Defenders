local Players = game:GetService("Players")
local NetClient = require(script.Parent.NetClient)

local AdminPanel = {}
local INK = Color3.fromRGB(231, 237, 249)
local MUTED = Color3.fromRGB(166, 182, 208)
local SURFACE = Color3.fromRGB(32, 44, 66)
local ACCENT = Color3.fromRGB(50, 101, 166)
local DANGER = Color3.fromRGB(148, 48, 66)
local KINDS = { "Gold", "Gems", "Xp", "MP", "Dice", "Materials", "Items", "Cosmetics" }
local BY_ID = { Dice = true, Materials = true, Items = true, Cosmetics = true }
local MESSAGES = {
	AdminBusy = "An earlier edit is still running.",
	Forbidden = "This account has no admin access.",
	Insufficient = "The player has fewer than that amount.",
	LeaseHeld = "Another server has this profile open. Retry after the player leaves it.",
	NoLiveMatch = "MP can only be edited for the active match in this server.",
	NoProfile = "This ID has no saved profile.",
	NotOwned = "The player does not own that entry.",
	Overflow = "That edit exceeds the game's count limit.",
	ProfileBusy = "The profile is loading or closing. Try again shortly.",
	SavePending = "Applied in this server. Persistence is pending. Avoid repeating the edit.",
	SaveUncertain = "Save could not be confirmed. Check the profile before repeating the edit.",
	StarterDie = "Starter ownership is required for a valid deck. You can take spare copies.",
	Throttled = "Wait a moment before sending the next edit.",
	UnknownItem = "No catalog entry matches that ID.",
}

local function make(className, parent, props)
	local instance = Instance.new(className)
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function round(instance, radius)
	make("UICorner", instance, { CornerRadius = UDim.new(0, radius) })
end

local function button(parent, text, size, color)
	local control = make("TextButton", parent, {
		Size = size,
		Text = text,
		TextColor3 = INK,
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		BackgroundColor3 = color or SURFACE,
		BorderSizePixel = 0,
	})
	round(control, 8)
	return control
end

local function field(parent, hint, size)
	local box = make("TextBox", parent, {
		Size = size,
		Text = "",
		PlaceholderText = hint,
		TextColor3 = INK,
		PlaceholderColor3 = MUTED,
		BackgroundColor3 = SURFACE,
		BorderSizePixel = 0,
		TextSize = 15,
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
	})
	round(box, 8)
	return box
end

local function stack(parent, direction)
	return make("UIListLayout", parent, {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

local function row(parent, height, order)
	local frame = make("Frame", parent, {
		Size = UDim2.new(1, -2, 0, height),
		LayoutOrder = order,
		BackgroundTransparency = 1,
	})
	stack(frame, Enum.FillDirection.Horizontal)
	return frame
end

local function mount(player)
	local gui = make("ScreenGui", player:WaitForChild("PlayerGui"), {
		Name = "PlayerAdminPanel",
		ResetOnSpawn = false,
		DisplayOrder = 60,
	})
	local launch = button(gui, "Admin", UDim2.fromOffset(94, 40), ACCENT)
	launch.AnchorPoint = Vector2.one
	launch.Position = UDim2.new(1, -16, 1, -16)
	local panel = make("Frame", gui, {
		AnchorPoint = Vector2.one,
		Position = UDim2.new(1, -16, 1, -64),
		Size = UDim2.new(1, -32, 1, -78),
		BackgroundColor3 = Color3.fromRGB(18, 26, 43),
		BorderSizePixel = 0,
		Visible = false,
	})
	round(panel, 14)
	make("UISizeConstraint", panel, { MaxSize = Vector2.new(426, 570) })
	make("UIStroke", panel, { Color = Color3.fromRGB(64, 85, 123), Transparency = 0.25 })
	make("TextLabel", panel, {
		Text = "Player admin",
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -68, 0, 38),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold,
		TextSize = 21,
		TextColor3 = INK,
		BackgroundTransparency = 1,
	})
	local close = button(panel, "×", UDim2.fromOffset(34, 32))
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 11)
	local content = make("ScrollingFrame", panel, {
		Position = UDim2.fromOffset(14, 52),
		Size = UDim2.new(1, -28, 1, -65),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	stack(content)
	local targetRow = row(content, 40, 1)
	local target = field(targetRow, "Roblox user ID", UDim2.new(0.63, -6, 1, 0))
	local online = button(targetRow, "In this server", UDim2.fromScale(0.37, 1))
	local onlineList = row(content, 0, 2)
	onlineList:FindFirstChildOfClass("UIListLayout"):Destroy()
	onlineList.Visible = false
	stack(onlineList)

	local kindFrame = make("Frame", content, {
		Size = UDim2.new(1, -6, 0, 72),
		LayoutOrder = 3,
		BackgroundTransparency = 1,
	})
	make("UIGridLayout", kindFrame, {
		CellSize = UDim2.new(0.25, -4, 0, 32),
		CellPadding = UDim2.fromOffset(5, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	local editRow = row(content, 40, 4)
	local item = field(editRow, "Catalog ID", UDim2.new(0.47, -6, 1, 0))
	local browse = button(editRow, "Browse", UDim2.new(0.29, -6, 1, 0))
	local amount = field(editRow, "Amount", UDim2.fromScale(1, 1))
	amount.Text = "1"
	local items = make("ScrollingFrame", content, {
		Size = UDim2.new(1, -6, 0, 138),
		LayoutOrder = 5,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
	})
	stack(items)
	local controls = row(content, 38, 6)
	local give = button(controls, "Give", UDim2.new(0.5, -3, 1, 0), ACCENT)
	local take = button(controls, "Take", UDim2.new(0.5, -3, 1, 0))
	local revoke = button(controls, "Revoke die", UDim2.new(1 / 3, -4, 1, 0), DANGER)
	local resetRow = row(content, 38, 7)
	local reset = button(resetRow, "Reset profile…", UDim2.fromScale(1, 1), DANGER)
	local confirmRow = row(content, 38, 8)
	confirmRow.Visible = false
	local confirmText = field(confirmRow, "Type RESET", UDim2.new(0.58, -6, 1, 0))
	local confirm = button(confirmRow, "Confirm reset", UDim2.fromScale(0.42, 1), DANGER)
	local status = make("TextLabel", content, {
		Size = UDim2.new(1, -8, 0, 48),
		LayoutOrder = 9,
		BackgroundTransparency = 1,
		Text = "Enter a user ID or choose a player in this server.",
		TextColor3 = MUTED,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = 14,
		Font = Enum.Font.Gotham,
	})
	local kind = "Gold"
	local selected = {}
	local pending = false
	local resetTarget

	local function feedback(message, errorState)
		status.Text = message
		status.TextColor3 = if errorState then Color3.fromRGB(255, 169, 180) else MUTED
	end

	local function disarm()
		resetTarget = nil
		confirmText.Text = ""
		confirmRow.Visible = false
	end

	local function userId()
		local id = tonumber(target.Text:match("^%s*(%d+)%s*$") or "")
		return if id and id >= 1 and id < 2 ^ 53 then id else nil
	end

	local function activate(nextKind)
		kind = nextKind
		revoke.Visible = kind == "Dice"
		local actionWidth = if revoke.Visible then UDim2.new(1 / 3, -4, 1, 0) else UDim2.new(0.5, -3, 1, 0)
		give.Size, take.Size = actionWidth, actionWidth
		item.Visible = BY_ID[kind] == true
		browse.Visible = item.Visible
		items.Visible = false
		item.Text = ""
		amount.Visible = kind ~= "Cosmetics"
		amount.Size = if item.Visible then UDim2.fromScale(0.24, 1) else UDim2.fromScale(1, 1)
		disarm()
		for key, control in selected do
			control.BackgroundColor3 = if key == kind then ACCENT else SURFACE
		end
		if kind == "Dice" then
			feedback("The first copy unlocks a die. Revoke die takes ownership and all copies.")
		else
			feedback("")
		end
	end

	for i, key in KINDS do
		local control = button(kindFrame, if key == "Xp" then "XP" else key, UDim2.new())
		selected[key] = control
		control.LayoutOrder = i
		control.Activated:Connect(function()
			activate(key)
		end)
	end
	activate(kind)
	feedback("Enter a user ID or choose a player in this server.")

	local function removeChoices(container)
		for _, child in container:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
	end

	online.Activated:Connect(function()
		onlineList.Visible = not onlineList.Visible
		if not onlineList.Visible then
			return
		end
		removeChoices(onlineList)
		local connected = Players:GetPlayers()
		table.sort(connected, function(a, b)
			return a.Name < b.Name
		end)
		onlineList.Size = UDim2.new(1, -6, 0, #connected * 33 - 6)
		for i, candidate in connected do
			local choice =
				button(onlineList, ("%s · %d"):format(candidate.Name, candidate.UserId), UDim2.new(1, 0, 0, 27))
			choice.LayoutOrder = i
			choice.Activated:Connect(function()
				target.Text = tostring(candidate.UserId)
				onlineList.Visible = false
			end)
		end
	end)

	browse.Activated:Connect(function()
		items.Visible = not items.Visible
		if not items.Visible then
			return
		end
		removeChoices(items)
		items.CanvasPosition = Vector2.zero
		local catalog = NetClient.LastCatalog and NetClient.LastCatalog[kind]
		if not catalog then
			items.Visible = false
			feedback("Catalog is loading. You can enter an exact ID.", true)
			return
		end
		for i, entry in catalog do
			local choice = button(items, ("%s · %s"):format(entry.Name, entry.Id), UDim2.new(1, -5, 0, 30))
			choice.LayoutOrder = i
			choice.Activated:Connect(function()
				item.Text = entry.Id
				items.Visible = false
			end)
		end
	end)

	local function send(action, id, category, entryId, quantity)
		if pending then
			return
		end
		pending = true
		disarm()
		feedback("Applying edit…")
		local ok, code = NetClient.Request("AdminAction", action, id, category, entryId, quantity)
		pending = false
		if code then
			feedback(MESSAGES[code] or ("Request returned " .. code .. "."), not ok)
		elseif ok then
			feedback(("Applied to user %d."):format(id))
		else
			feedback("The edit could not be confirmed.", true)
		end
	end

	local function adjust(action)
		local id = userId()
		if not id then
			feedback("Enter a valid Roblox user ID.", true)
			return
		end
		local quantity = if kind == "Cosmetics" or action == "Revoke"
			then 1
			else tonumber(amount.Text:match("^%s*(%d+)%s*$") or "")
		if not quantity or quantity < 1 or quantity > 1_000_000_000 then
			feedback("Enter a whole amount from 1 to 1,000,000,000.", true)
			return
		end
		local entryId = if BY_ID[kind] then item.Text:match("^%s*(.-)%s*$") else ""
		if BY_ID[kind] and (#entryId == 0 or #entryId > 32) then
			feedback("Choose or enter a catalog ID.", true)
			return
		end
		send(action, id, kind, entryId, quantity)
	end

	give.Activated:Connect(function()
		adjust("Give")
	end)
	take.Activated:Connect(function()
		adjust("Take")
	end)
	revoke.Activated:Connect(function()
		adjust("Revoke")
	end)
	reset.Activated:Connect(function()
		if pending then
			return
		end
		if resetTarget then
			disarm()
			feedback("Reset canceled.")
			return
		end
		resetTarget = userId()
		confirmRow.Visible = resetTarget ~= nil
		feedback(
			if resetTarget
				then ("User %d will lose progress and inventory. Type RESET to confirm."):format(resetTarget)
				else "Enter a valid Roblox user ID.",
			true
		)
	end)
	confirm.Activated:Connect(function()
		if not resetTarget or userId() ~= resetTarget or confirmText.Text ~= "RESET" then
			feedback("Confirm the selected user and type RESET.", true)
			return
		end
		send("Reset", resetTarget, "", confirmText.Text, 0)
	end)
	target:GetPropertyChangedSignal("Text"):Connect(disarm)
	local function toggle()
		panel.Visible = not panel.Visible
		if not panel.Visible then
			disarm()
		end
	end
	launch.Activated:Connect(toggle)
	close.Activated:Connect(toggle)
end

function AdminPanel.Start()
	local player = Players.LocalPlayer
	if player:GetAttribute("AdminPanelAllowed") == true then
		mount(player)
		return
	end
	local connection
	connection = player:GetAttributeChangedSignal("AdminPanelAllowed"):Connect(function()
		if player:GetAttribute("AdminPanelAllowed") == true then
			connection:Disconnect()
			mount(player)
		end
	end)
end

return AdminPanel
