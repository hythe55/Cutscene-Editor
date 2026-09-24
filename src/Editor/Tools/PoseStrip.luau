local UI = require(script.Parent.Parent.UI)
local PoseMath = require(script.Parent.PoseMath)

local PoseStrip = {}
PoseStrip.__index = PoseStrip

local HEIGHT = 30
local SIZE = 9
local INSET = 8

function PoseStrip.new(props)
	local self = setmetatable({}, PoseStrip)
	self.OnKeyframe = props.OnKeyframe
	self.OnScrub = props.OnScrub
	self.Markers = {}
	local root = UI.Create("TextButton", {
		Name = "KeyframeStrip",
		Parent = props.Parent,
		LayoutOrder = props.LayoutOrder or 0,
		Text = "",
		Size = UDim2.new(1, 0, 0, HEIGHT),
		BackgroundColor3 = "Sunken",
		ClipsDescendants = true,
		Corner = 4,
		Stroke = { Color = "Border", Thickness = 1 },
	})
	self.Track = UI.Create("Frame", {
		Parent = root,
		Position = UDim2.new(0, INSET, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(1, -INSET * 2, 0, 2),
		BackgroundColor3 = "Divider",
	})
	self.Range = UI.Create("Frame", {
		Parent = root,
		Position = UDim2.new(0, INSET, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(0, 0, 0, 12),
		BackgroundColor3 = "AccentSoft",
		Corner = 3,
	})
	self.Playhead = UI.Create("Frame", {
		Parent = root,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0, 2, 1, 0),
		BackgroundColor3 = "Playhead",
		ZIndex = 4,
	})
	self.Root = root
	self.Instance = root
	root.MouseButton1Down:Connect(function(x)
		self:_scrub(x)
	end)
	return self
end

function PoseStrip:_x(time)
	local length = math.max(self.Length or 0, 1e-3)
	local width = math.max(self.Root.AbsoluteSize.X - INSET * 2, 1)
	return INSET + time / length * width
end

function PoseStrip:_scrub(x)
	if not self.OnScrub or not self.Length or self.Length <= 0 then
		return
	end
	local width = math.max(self.Root.AbsoluteSize.X - INSET * 2, 1)
	local time = math.clamp((x - self.Root.AbsolutePosition.X - INSET) / width, 0, 1) * self.Length
	self.OnScrub(time)
end

function PoseStrip:_marker(index)
	local marker = self.Markers[index]
	if marker then
		marker.Button.Visible = true
		return marker
	end
	local button = UI.Create("TextButton", {
		Parent = self.Root,
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(SIZE + 6, SIZE + 6),
		ZIndex = 3,
		Tooltip = "Keyframe",
	})
	local shape = UI.Create("Frame", {
		Parent = button,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(SIZE, SIZE),
		Rotation = 45,
		BackgroundColor3 = Color3.new(1, 1, 1),
	})
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Parent = shape
	marker = { Button = button, Shape = shape, Stroke = stroke }
	button.Activated:Connect(function()
		if marker.Keyframe and self.OnKeyframe then
			self.OnKeyframe(marker.Keyframe)
		end
	end)
	self.Markers[index] = marker
	return marker
end

function PoseStrip:Render(info, clipTime, current, jointKey)
	local theme = UI.Theme
	self.Length = info and info.Length or 0
	local keyframes = info and info.Keyframes or {}
	if info then
		local from, to = PoseMath.VisibleRange(info)
		from = math.clamp(from, 0, self.Length)
		to = math.clamp(to, from, self.Length)
		self.Range.Visible = self.Length > 0
		self.Range.Position = UDim2.new(0, self:_x(from), 0.5, 0)
		self.Range.Size = UDim2.new(0, math.max(self:_x(to) - self:_x(from), 2), 0, 12)
	else
		self.Range.Visible = false
	end
	self.Playhead.Visible = clipTime ~= nil and self.Length > 0
	if clipTime then
		self.Playhead.Position = UDim2.fromOffset(self:_x(clipTime), 0)
	end
	for index, keyframe in keyframes do
		local marker = self:_marker(index)
		marker.Keyframe = keyframe
		local role
		if jointKey then
			local pose = PoseMath.PoseOf(keyframe, jointKey)
			role = if pose and pose.Weight > 0 then PoseMath.Role(pose) else nil
		else
			role = PoseMath.KeyframeRole(keyframe)
		end
		local selected = keyframe == current
		local color = theme:Get(if selected then "Accent" elseif role then "Text" else "Faint")
		local shape = marker.Shape
		shape.Rotation = if role == "Snap" then 0 else 45
		shape.BackgroundColor3 = color
		shape.BackgroundTransparency = if role == "Pass" or role == nil then 1 else 0
		marker.Stroke.Color = color
		shape.Size = UDim2.fromOffset(if selected then SIZE + 2 else SIZE, if selected then SIZE + 2 else SIZE)
		marker.Button.Position = UDim2.new(0, self:_x(keyframe.Time), 0.5, 0)
		marker.Button:SetAttribute("TooltipText", string.format("%.2fs · %s", keyframe.Time, role or "not keyed"))
	end
	for index = #keyframes + 1, #self.Markers do
		self.Markers[index].Button.Visible = false
		self.Markers[index].Keyframe = nil
	end
end

function PoseStrip:Destroy()
	self.Root:Destroy()
end

return PoseStrip
