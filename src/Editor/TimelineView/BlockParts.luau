local Parts = {}

Parts.RampShade = 0.55
Parts.RampLine = 0.45
Parts.RampThickness = 1.6

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

local function new(className, parent, props)
	local instance = Instance.new(className)
	if instance:IsA("GuiObject") then
		instance.BorderSizePixel = 0
		instance.BackgroundTransparency = 1
	end
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

function Parts.Put(block, instance, property, value)
	local cache = block.Cache[instance]
	if not cache then
		cache = {}
		block.Cache[instance] = cache
	end
	if cache[property] ~= value then
		cache[property] = value
		instance[property] = value
	end
end

local function ramp(frame, out)
	local shade = new("Frame", frame, {
		Name = if out then "FadeOutRamp" else "FadeInRamp",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		Visible = false,
		ZIndex = 2,
	})
	local gradient = Instance.new("UIGradient")
	gradient.Parent = shade
	return { Shade = shade, Gradient = gradient, Key = nil }
end

local function numbers(list)
	local points = {}
	for _, pair in list do
		table.insert(points, NumberSequenceKeypoint.new(pair[1], pair[2]))
	end
	return NumberSequence.new(points)
end

local function colors(list)
	local points = {}
	for _, pair in list do
		table.insert(points, ColorSequenceKeypoint.new(pair[1], pair[2]))
	end
	return ColorSequence.new(points)
end

local function handle(frame, name)
	local instance = new("Frame", frame, {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(7, 7),
		Visible = false,
		ZIndex = 6,
	})
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(30, 30, 34)
	stroke.Thickness = 1
	stroke.Parent = instance
	return instance
end

function Parts.Create(parent, view)
	local frame = new("Frame", parent, { Name = "Block", BackgroundTransparency = 0, Visible = false })
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 1
	stroke.Parent = frame
	local label = new("TextLabel", frame, {
		Name = "Label",
		FontFace = view.Fonts.Medium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	local badge = new("Frame", frame, {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 0,
		Visible = false,
		ZIndex = 4,
	})
	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(1, 0)
	badgeCorner.Parent = badge
	new("TextLabel", badge, {
		Name = "Mark",
		Text = "!",
		FontFace = view.Fonts.Bold,
		TextSize = 11,
		TextColor3 = WHITE,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	})
	local block = {
		Frame = frame,
		Stroke = stroke,
		Label = label,
		Badge = badge,
		FadeIn = ramp(frame, false),
		FadeOut = ramp(frame, true),
		HandleIn = handle(frame, "FadeInHandle"),
		HandleOut = handle(frame, "FadeOutHandle"),
		EdgeLeft = new("Frame", frame, { Name = "EdgeLeft", BackgroundTransparency = 0.25, Visible = false, ZIndex = 5 }),
		EdgeRight = new("Frame", frame, {
			Name = "EdgeRight",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			BackgroundTransparency = 0.25,
			Visible = false,
			ZIndex = 5,
		}),
		Stripe = new("Frame", frame, { Name = "ReadingStripe", BackgroundTransparency = 0, Visible = false, ZIndex = 4 }),
		Need = new("Frame", frame, { Name = "ReadingNeeded", BackgroundTransparency = 0.45, Visible = false, ZIndex = 4 }),
		LockMark = new("Frame", frame, {
			Name = "Locked",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -3, 0, 3),
			Size = UDim2.fromOffset(5, 5),
			BackgroundTransparency = 0,
			Visible = false,
			ZIndex = 5,
		}),
		Diamonds = {},
		Cache = {},
	}
	return block
end

function Parts.Ramp(block, ramp, width, height, out, color, blockWidth)
	local put = Parts.Put
	local w = math.round(width)
	local visible = w >= 2 and height >= 2
	put(block, ramp.Shade, "Visible", visible)
	if not visible then
		return
	end
	put(block, ramp.Shade, "Position", UDim2.fromOffset(if out then blockWidth - w else 0, 0))
	put(block, ramp.Shade, "Size", UDim2.fromOffset(w, height))
	local key = `{w}|{height}|{color:ToHex()}`
	if ramp.Key == key then
		return
	end
	ramp.Key = key
	local span = math.sqrt(w * w + height * height) * math.min(w, height) / math.max(w, height)
	local epsilon = math.clamp(Parts.RampThickness / (2 * span), 0.002, 0.2)
	local low, high = 0.5 - epsilon, 0.5 + epsilon
	local shade, line = Parts.RampShade, Parts.RampLine
	local angle = math.deg(math.atan2(w, height))
	local gradient = ramp.Gradient
	if out then
		gradient.Rotation = -angle
		gradient.Transparency = numbers({ { 0, 1 }, { low, 1 }, { 0.5, line }, { high, shade }, { 1, shade } })
		gradient.Color = colors({ { 0, color }, { 0.5, color }, { high, BLACK }, { 1, BLACK } })
	else
		gradient.Rotation = angle
		gradient.Transparency = numbers({ { 0, shade }, { low, shade }, { 0.5, line }, { high, 1 }, { 1, 1 } })
		gradient.Color = colors({ { 0, BLACK }, { low, BLACK }, { 0.5, color }, { 1, color } })
	end
end

function Parts.Diamond(block, index, x, y, role, color, selected)
	local put = Parts.Put
	local entry = block.Diamonds[index]
	if not entry then
		local frame = new("Frame", block.Frame, { Name = "Key", AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3 })
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1
		stroke.Parent = frame
		entry = { Frame = frame, Stroke = stroke }
		block.Diamonds[index] = entry
	end
	local frame = entry.Frame
	local size = if role == "Snap" then 5 elseif selected then 8 else 6
	put(block, frame, "Visible", true)
	put(block, frame, "Position", UDim2.fromOffset(math.round(x), y))
	put(block, frame, "Size", UDim2.fromOffset(size, size))
	put(block, frame, "Rotation", if role == "Snap" then 0 else 45)
	put(block, frame, "BackgroundColor3", color)
	put(block, frame, "BackgroundTransparency", if role == "Pass" and not selected then 1 else 0)
	put(block, entry.Stroke, "Enabled", role == "Pass" and not selected)
	put(block, entry.Stroke, "Color", color)
end

return Parts
