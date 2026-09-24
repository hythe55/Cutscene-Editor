local UI = require(script.Parent)

local Toggle = {}
Toggle.__index = Toggle

local TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function Toggle.new(props)
	local theme = UI.Theme
	local self = setmetatable({
		Value = props.Value == true,
		OnChanged = props.OnChanged,
		Enabled = props.Enabled ~= false,
		Hover = false,
	}, Toggle)
	local root = UI.Create("TextButton", {
		Name = props.Name or "Toggle",
		Parent = props.Parent,
		Text = "",
		LayoutOrder = props.LayoutOrder or 0,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = props.Size or UDim2.new(if props.Label then 1 else 0, if props.Label then 0 else 30, 0, theme.ControlHeight),
		Tooltip = props.Tooltip,
	})
	local track = UI.Create("Frame", {
		Name = "Track",
		Parent = root,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(30, 16),
		BackgroundColor3 = "Sunken",
		Corner = UDim.new(1, 0),
		Stroke = { Color = "Outline", Thickness = 1 },
	})
	local knob = UI.Create("Frame", {
		Name = "Knob",
		Parent = track,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = "White",
		Corner = UDim.new(1, 0),
	})
	if props.Label then
		self.Label = UI.Create("TextLabel", {
			Parent = root,
			Text = props.Label,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(40, 0),
			Size = UDim2.new(1, -40, 1, 0),
		})
	end
	self.Instance = root
	self.Track = track
	self.Knob = knob
	root.MouseEnter:Connect(function()
		self.Hover = true
		self:_render(false)
	end)
	root.MouseLeave:Connect(function()
		self.Hover = false
		self:_render(false)
	end)
	root.Activated:Connect(function()
		if not self.Enabled then
			return
		end
		self:Set(not self.Value, true)
		if self.OnChanged then
			self.OnChanged(self.Value, self)
		end
	end)
	theme:Watch(root, function()
		self:_render(false)
	end)
	return self
end

function Toggle:_render(animate)
	local theme = UI.Theme
	local on = self.Value
	local color = if on then theme:Get("Accent") else theme:Get(if self.Hover then "Hover" else "Sunken")
	self.Track.BackgroundColor3 = color
	self.Track.BackgroundTransparency = if self.Enabled then 0 else 0.5
	local stroke = self.Track:FindFirstChild("Stroke")
	if stroke then
		stroke.Transparency = if on then 1 else 0
	end
	self.Knob.BackgroundColor3 = if on then theme:Get("White") else theme:Get("SubText")
	local goal = UDim2.new(0, if on then 16 else 2, 0.5, 0)
	if animate then
		UI.Tween(self.Knob, TWEEN, { Position = goal })
	else
		self.Knob.Position = goal
	end
end

function Toggle:Set(value, animate)
	self.Value = value == true
	self:_render(animate)
end

function Toggle:Get()
	return self.Value
end

function Toggle:SetEnabled(enabled)
	self.Enabled = enabled ~= false
	self:_render(false)
end

function Toggle:Destroy()
	self.Instance:Destroy()
end

return setmetatable(Toggle, {
	__call = function(_, props)
		return Toggle.new(props)
	end,
})
