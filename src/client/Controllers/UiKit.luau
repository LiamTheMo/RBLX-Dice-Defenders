-- Shared placeholder UI helpers and palette (moved out of Hud; no Init/Start).

local NAVY = Color3.fromRGB(27, 22, 54)
local NAVY_LIGHT = Color3.fromRGB(52, 44, 96)
local WHITE = Color3.new(1, 1, 1)
local ORANGE = Color3.fromRGB(245, 160, 50)
local GREEN = Color3.fromRGB(90, 205, 125)
local GREY = Color3.fromRGB(110, 106, 140)
local FONT = Enum.Font.FredokaOne

local UiKit = {
	NAVY = NAVY,
	NAVY_LIGHT = NAVY_LIGHT,
	WHITE = WHITE,
	ORANGE = ORANGE,
	GREEN = GREEN,
	GREY = GREY,
}

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

return UiKit
