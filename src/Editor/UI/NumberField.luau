local UI = require(script.Parent)

local NumberField = {}
NumberField.__index = NumberField

local DRAG_THRESHOLD = 3

local function decimalsFor(step)
	if not step or step >= 1 then
		return 0
	end
	local decimals = 0
	while decimals < 4 and math.abs(step * 10 ^ decimals - math.round(step * 10 ^ decimals)) > 1e-6 do
		decimals += 1
	end
	return decimals
end

function NumberField.Format(value, decimals)
	if type(value) ~= "number" then
		return ""
	end
	local text = string.format("%." .. (decimals or 3) .. "f", value)
	if string.find(text, "%.") then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	if text == "-0" then
		text = "0"
	end
	return text
end

function NumberField.new(props)
	local theme = UI.Theme
	local step = props.Step or 0.1
	local self = setmetatable({
		Value = props.Value or 0,
		Min = props.Min,
		Max = props.Max,
		Step = step,
		Decimals = props.Decimals or math.max(decimalsFor(step), 2),
		Suffix = props.Suffix or "",
		OnChanged = props.OnChanged,
		OnCommit = props.OnCommit,
		Enabled = props.Enabled ~= false,
		Focused = false,
		Hover = false,
		Dragging = false,
	}, NumberField)
	local height = props.Height or theme.ControlHeight
	local root = UI.Create("Frame", {
		Name = props.Name or "NumberField",
		Parent = props.Parent,
		LayoutOrder = props.LayoutOrder or 0,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = props.Size or UDim2.new(1, 0, 0, height),
		BackgroundColor3 = "Sunken",
		ClipsDescendants = true,
		Corner = theme.Radius,
		Stroke = { Color = "Border", Thickness = 1 },
		Tooltip = props.Tooltip,
	})
	local labelWidth = 0
	if props.Label then
		labelWidth = props.LabelWidth or 18
		self.LabelFrame = UI.Create("TextLabel", {
			Parent = root,
			Text = props.Label,
			Font = "Bold",
			TextSize = 11,
			TextColor3 = props.LabelColor or "Dim",
			BackgroundColor3 = UI.Color("Sunken", "Text", 0.05),
			Size = UDim2.new(0, labelWidth, 1, 0),
		})
	end
	local box = UI.Create("TextBox", {
		Parent = root,
		Text = "",
		TextSize = 13,
		Font = "Mono",
		ClearTextOnFocus = false,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(labelWidth + 6, 0),
		Size = UDim2.new(1, -(labelWidth + 12), 1, 0),
		Interactable = false,
	})
	local grab = UI.Create("TextButton", {
		Name = "Grab",
		Parent = root,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	})
	self.Instance = root
	self.Box = box
	self.Grab = grab
	root.MouseEnter:Connect(function()
		self.Hover = true
		self:_render()
	end)
	root.MouseLeave:Connect(function()
		self.Hover = false
		self:_render()
	end)
	grab.MouseButton1Down:Connect(function(x, y)
		if self.Enabled then
			self:_beginDrag(x, y)
		end
	end)
	box.FocusLost:Connect(function()
		self.Focused = false
		box.Interactable = false
		grab.Visible = true
		local value = tonumber(box.Text)
		if value then
			self:_commit(value)
		else
			self:_display()
		end
		self:_render()
	end)
	theme:Watch(root, function()
		self:_render()
	end)
	self:_display()
	return self
end

function NumberField:_clamp(value)
	if self.Min then
		value = math.max(value, self.Min)
	end
	if self.Max then
		value = math.min(value, self.Max)
	end
	return value
end

function NumberField:_display()
	if not self.Focused then
		self.Box.Text = NumberField.Format(self.Value, self.Decimals) .. self.Suffix
	end
end

function NumberField:_render()
	local theme = UI.Theme
	local stroke = self.Instance:FindFirstChild("Stroke")
	if stroke then
		stroke.Color = theme:Get(if self.Focused or self.Dragging then "Accent" elseif self.Hover and self.Enabled then "Outline" else "Border")
	end
	self.Box.TextColor3 = theme:Get(if self.Enabled then "Text" else "Dim")
end

function NumberField:_focus()
	self.Focused = true
	self.Grab.Visible = false
	self.Box.Interactable = true
	self.Box.Text = NumberField.Format(self.Value, math.max(self.Decimals, 3))
	self.Box:CaptureFocus()
	self.Box.SelectionStart = 1
	self.Box.CursorPosition = #self.Box.Text + 1
	self:_render()
end

function NumberField:_beginDrag(startX)
	local layer = UI.Layer
	if not layer then
		self:_focus()
		return
	end
	local startValue = self.Value
	local moved = false
	self.Dragging = true
	self:_render()
	local capture = UI.Create("TextButton", {
		Name = "NumberDrag",
		Parent = layer,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 500,
	})
	local function finish()
		if not self.Dragging then
			return
		end
		self.Dragging = false
		capture:Destroy()
		self:_render()
		if moved then
			if self.OnCommit and self.Value ~= startValue then
				self.OnCommit(self.Value, self)
			end
		else
			self:_focus()
		end
	end
	capture.MouseMoved:Connect(function(x)
		local delta = x - startX
		if not moved and math.abs(delta) < DRAG_THRESHOLD then
			return
		end
		moved = true
		local steps = math.floor(delta / 4 + 0.5)
		local value = self:_clamp(startValue + steps * self.Step)
		value = math.round(value / self.Step) * self.Step
		value = tonumber(NumberField.Format(value, self.Decimals + 2)) or value
		if value ~= self.Value then
			self.Value = value
			self:_display()
			if self.OnChanged then
				self.OnChanged(value, self)
			end
		end
	end)
	capture.MouseButton1Up:Connect(finish)
	capture.MouseLeave:Connect(finish)
end

function NumberField:_commit(value)
	value = self:_clamp(value)
	local changed = value ~= self.Value
	self.Value = value
	self:_display()
	if changed and self.OnCommit then
		self.OnCommit(value, self)
	end
end

function NumberField:Set(value)
	if type(value) == "number" then
		self.Value = value
		self:_display()
	end
end

function NumberField:Get()
	return self.Value
end

function NumberField:SetEnabled(enabled)
	self.Enabled = enabled ~= false
	self:_render()
end

function NumberField:Destroy()
	self.Instance:Destroy()
end

return setmetatable(NumberField, {
	__call = function(_, props)
		return NumberField.new(props)
	end,
})
