-- Shared placeholder UI helpers and palette (moved out of Hud; no Init/Start).

local UserInputService = game:GetService("UserInputService")

local NAVY = Color3.fromRGB(27, 22, 54)
local NAVY_LIGHT = Color3.fromRGB(52, 44, 96)
local WHITE = Color3.new(1, 1, 1)
local ORANGE = Color3.fromRGB(245, 160, 50)
local GREEN = Color3.fromRGB(90, 205, 125)
local GREY = Color3.fromRGB(110, 106, 140)
local FONT = Enum.Font.FredokaOne

local UiKit = {
	PHONE_H = 500, -- screens shorter than this (px) use the phone layouts
	NAVY = NAVY,
	NAVY_LIGHT = NAVY_LIGHT,
	WHITE = WHITE,
	ORANGE = ORANGE,
	GREEN = GREEN,
	GREY = GREY,
}

-- Screen size a container lays out against: the EmulateSize attribute (Vector2, for captures) else its AbsoluteSize.
function UiKit.screenSize(container: GuiObject): Vector2
	local emulated = container:GetAttribute("EmulateSize")
	return if typeof(emulated) == "Vector2" then emulated else container.AbsoluteSize
end

function UiKit.make(class: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(class)
	for key, value in props do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

function UiKit.panel(props: { [string]: any }, parent: Instance): any
	props.BackgroundColor3 = props.BackgroundColor3 or NAVY
	props.BorderSizePixel = 0
	local frame = UiKit.make("Frame", props, parent)
	UiKit.make("UICorner", { CornerRadius = UDim.new(0, 12) }, frame)
	UiKit.make("UIStroke", { Color = NAVY_LIGHT, Thickness = 2 }, frame)
	return frame
end

-- Text that scales with its box but never drops below 14 px.
function UiKit.label(props: { [string]: any }, parent: Instance, maxSize: number): any
	props.BackgroundTransparency = 1
	props.Font = FONT
	props.TextColor3 = props.TextColor3 or WHITE
	props.TextScaled = true
	local text = UiKit.make("TextLabel", props, parent)
	UiKit.make("UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = maxSize }, text)
	return text
end

function UiKit.button(props: { [string]: any }, parent: Instance, color: Color3, onClick: () -> ()): any
	props.BackgroundColor3 = color
	props.BorderSizePixel = 0
	props.AutoButtonColor = false
	props.Font = FONT
	props.TextColor3 = NAVY
	props.TextScaled = true
	local btn = UiKit.make("TextButton", props, parent)
	UiKit.make("UICorner", { CornerRadius = UDim.new(0, 14) }, btn)
	UiKit.make("UIStroke", { Color = WHITE, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, btn)
	UiKit.make("UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = 30 }, btn)
	UiKit.make("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
	}, btn)
	local scale = UiKit.make("UIScale", { Scale = 1 }, btn)
	local hover = false
	btn.MouseEnter:Connect(function()
		hover = true
		scale.Scale = 1.04
	end)
	btn.MouseLeave:Connect(function()
		hover = false
		scale.Scale = 1
	end)
	btn.MouseButton1Down:Connect(function()
		scale.Scale = 0.94
	end)
	btn.MouseButton1Up:Connect(function()
		scale.Scale = hover and 1.04 or 1
	end)
	btn.Activated:Connect(onClick)
	return btn
end

-- Hover (mouse only), press (mouse and touch) and the DebugState attribute ("Hover" | "Pressed", for
-- captures) call apply("Normal" | "Hover" | "Pressed"). Returns refresh for callers with extra state.
function UiKit.wire(btn, apply)
	local hover, down = false, false
	local function refresh()
		local forced = btn:GetAttribute("DebugState")
		apply(
			if forced == "Pressed" or down then "Pressed" elseif forced == "Hover" or hover then "Hover" else "Normal"
		)
	end
	local mouseOnly = not UserInputService.TouchEnabled or UserInputService.MouseEnabled
	btn.MouseEnter:Connect(function()
		hover = mouseOnly
		refresh()
	end)
	btn.MouseLeave:Connect(function()
		hover, down = false, false
		refresh()
	end)
	btn.MouseButton1Down:Connect(function()
		down = true
		refresh()
	end)
	btn.MouseButton1Up:Connect(function()
		down = false
		refresh()
	end)
	btn:GetAttributeChangedSignal("DebugState"):Connect(refresh)
	btn:GetPropertyChangedSignal("Interactable"):Connect(refresh)
	refresh()
	return refresh
end

return UiKit
