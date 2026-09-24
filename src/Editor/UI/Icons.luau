local UI = require(script.Parent)

local Icons = {}

local TRIANGLE = "rbxasset://textures/triangle.png"
local CHEVRON_DOWN = "rbxasset://textures/collapsibleArrowDown.png"
local CHEVRON_RIGHT = "rbxasset://textures/collapsibleArrowRight.png"
local CAMERA = "rbxasset://textures/ui/Camera/CameraToastIcon.png"

local function box(parent, color, x, y, w, h, extra)
	local props = {
		Parent = parent,
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, x, 0.5, y),
		Size = UDim2.fromOffset(w, h),
	}
	for key, value in extra or {} do
		props[key] = value
	end
	return UI.Create("Frame", props)
end

local function image(parent, color, source, w, h, x, y, rotation)
	return UI.Create("ImageLabel", {
		Parent = parent,
		Image = source,
		ImageColor3 = color,
		ScaleType = Enum.ScaleType.Stretch,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, x or 0, 0.5, y or 0),
		Size = UDim2.fromOffset(w, h),
		Rotation = rotation or 0,
	})
end

local function ring(parent, color, x, y, w, h, thickness, radius)
	return UI.Create("Frame", {
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, x, 0.5, y),
		Size = UDim2.fromOffset(w, h),
		Corner = radius or UDim.new(1, 0),
		Stroke = { Color = color, Thickness = thickness or 1.5 },
	})
end

local DRAW = {}

function DRAW.Play(frame, color)
	image(frame, color, TRIANGLE, 12, 10, 1, 0, 90)
end

function DRAW.Pause(frame, color)
	box(frame, color, -3, 0, 3, 11, { Corner = 1 })
	box(frame, color, 3, 0, 3, 11, { Corner = 1 })
end

function DRAW.Stop(frame, color)
	box(frame, color, 0, 0, 10, 10, { Corner = 2 })
end

function DRAW.SkipStart(frame, color)
	box(frame, color, -5, 0, 2, 11, { Corner = 1 })
	image(frame, color, TRIANGLE, 11, 9, 1, 0, -90)
end

function DRAW.SkipEnd(frame, color)
	box(frame, color, 5, 0, 2, 11, { Corner = 1 })
	image(frame, color, TRIANGLE, 11, 9, -1, 0, 90)
end

function DRAW.Eye(frame, color)
	ring(frame, color, 0, 0, 15, 9, 1.5)
	box(frame, color, 0, 0, 5, 5, { Corner = UDim.new(1, 0) })
end

function DRAW.EyeOff(frame, color)
	DRAW.Eye(frame, color)
	box(frame, color, 0, 0, 2, 18, { Rotation = -45, Corner = 1 })
end

function DRAW.Plus(frame, color)
	box(frame, color, 0, 0, 10, 2, { Corner = 1 })
	box(frame, color, 0, 0, 2, 10, { Corner = 1 })
end

function DRAW.Minus(frame, color)
	box(frame, color, 0, 0, 10, 2, { Corner = 1 })
end

function DRAW.Close(frame, color)
	box(frame, color, 0, 0, 12, 2, { Rotation = 45, Corner = 1 })
	box(frame, color, 0, 0, 12, 2, { Rotation = -45, Corner = 1 })
end

function DRAW.Check(frame, color)
	box(frame, color, -3, 2, 6, 2, { Rotation = 45, Corner = 1 })
	box(frame, color, 2, 0, 11, 2, { Rotation = -50, Corner = 1 })
end

function DRAW.ChevronDown(frame, color)
	image(frame, color, CHEVRON_DOWN, 16, 16)
end

function DRAW.ChevronRight(frame, color)
	image(frame, color, CHEVRON_RIGHT, 16, 16)
end

function DRAW.ChevronUp(frame, color)
	image(frame, color, CHEVRON_DOWN, 16, 16, 0, 0, 180)
end

function DRAW.Lock(frame, color)
	ring(frame, color, 0, -2.5, 6, 8, 1.5, UDim.new(1, 0))
	box(frame, color, 0, 2.5, 10, 7, { Corner = 2, ZIndex = 2 })
end

function DRAW.Unlock(frame, color)
	ring(frame, color, 2, -4, 6, 8, 1.5, UDim.new(1, 0))
	box(frame, color, 0, 2.5, 10, 7, { Corner = 2, ZIndex = 2 })
end

function DRAW.Snap(frame, color)
	box(frame, color, -4, -1, 3, 10, { Corner = 1 })
	box(frame, color, 4, -1, 3, 10, { Corner = 1 })
	box(frame, color, 0, 4, 11, 3, { Corner = 1 })
	box(frame, color, -4, -5, 3, 2, { BackgroundTransparency = 0.55 })
	box(frame, color, 4, -5, 3, 2, { BackgroundTransparency = 0.55 })
end

function DRAW.Dots(frame, color)
	for _, x in { -5, 0, 5 } do
		box(frame, color, x, 0, 3, 3, { Corner = UDim.new(1, 0) })
	end
end

function DRAW.Search(frame, color)
	ring(frame, color, -1.5, -1.5, 9, 9, 1.5)
	box(frame, color, 4, 4, 5, 2, { Rotation = 45, Corner = 1 })
end

function DRAW.Camera(frame, color)
	image(frame, color, CAMERA, 18, 18)
end

function DRAW.Export(frame, color)
	image(frame, color, TRIANGLE, 8, 6, 0, -4)
	box(frame, color, 0, 0, 2, 7)
	box(frame, color, 0, 5, 12, 2, { Corner = 1 })
end

function DRAW.Diamond(frame, color)
	box(frame, color, 0, 0, 8, 8, { Rotation = 45, Corner = 1 })
end

function DRAW.Dot(frame, color)
	box(frame, color, 0, 0, 6, 6, { Corner = UDim.new(1, 0) })
end

function DRAW.Warning(frame, color)
	image(frame, color, TRIANGLE, 14, 12, 0, 0)
	UI.Create("TextLabel", {
		Parent = frame,
		Text = "!",
		Font = "Bold",
		TextSize = 10,
		TextColor3 = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 1),
		Size = UDim2.fromOffset(6, 10),
	})
end

function DRAW.Film(frame, color)
	ring(frame, color, 0, 0, 14, 11, 1.5, UDim.new(0, 2))
	box(frame, color, -3, 0, 2, 11)
	box(frame, color, 3, 0, 2, 11)
end

function DRAW.Runtime(frame, color)
	ring(frame, color, 0, 0, 13, 13, 1.5, UDim.new(0, 3))
	box(frame, color, 0, 0, 5, 5, { Corner = 1 })
end

function DRAW.Chat(frame, color)
	ring(frame, color, 0, -1, 14, 10, 1.5, UDim.new(0, 3))
	box(frame, color, -3, 5, 4, 4, { Rotation = 45 })
end

function DRAW.Actor(frame, color)
	box(frame, color, 0, -3, 6, 6, { Corner = UDim.new(1, 0) })
	box(frame, color, 0, 4, 11, 5, { Corner = UDim.new(0, 3) })
end

function DRAW.Panel(frame, color)
	ring(frame, color, 0, 0, 14, 12, 1.5, UDim.new(0, 2))
	box(frame, color, 3, 0, 4, 10, { Corner = 1 })
end

Icons.Names = {}
for name in DRAW do
	table.insert(Icons.Names, name)
end
table.sort(Icons.Names)

function Icons.Draw(name, parent, color, size)
	local frame = UI.Create("Frame", {
		Name = "Icon",
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size or 16, size or 16),
	})
	local draw = DRAW[name]
	if draw then
		draw(frame, color or "Text")
	end
	return frame
end

function Icons.Recolor(frame, color)
	for _, child in frame:GetDescendants() do
		if child:IsA("ImageLabel") then
			UI.Set(child, "ImageColor3", color)
		elseif child:IsA("UIStroke") then
			UI.Set(child, "Color", color)
		elseif child:IsA("Frame") and child.BackgroundTransparency < 1 then
			UI.Set(child, "BackgroundColor3", color)
		end
	end
end

return Icons
