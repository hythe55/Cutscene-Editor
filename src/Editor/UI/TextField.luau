local UI = require(script.Parent)

local TextField = {}
TextField.__index = TextField

function TextField.new(props)
	local theme = UI.Theme
	local self = setmetatable({
		Value = props.Value or "",
		OnCommit = props.OnCommit,
		OnChanged = props.OnChanged,
		ReadOnly = props.ReadOnly == true,
		Focused = false,
		Hover = false,
	}, TextField)
	local multi = props.MultiLine == true
	local height = props.Height or (if multi then 72 else theme.ControlHeight)
	local root = UI.Create("Frame", {
		Name = props.Name or "TextField",
		Parent = props.Parent,
		LayoutOrder = props.LayoutOrder or 0,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = props.Size or UDim2.new(1, 0, 0, height),
		BackgroundColor3 = "Sunken",
		Corner = theme.Radius,
		Stroke = { Color = "Border", Thickness = 1 },
		Tooltip = props.Tooltip,
	})
	local box = UI.Create("TextBox", {
		Parent = root,
		Text = self.Value,
		PlaceholderText = props.Placeholder or "",
		TextSize = props.TextSize or 13,
		Font = props.Font,
		TextEditable = not self.ReadOnly,
		MultiLine = multi,
		TextWrapped = multi,
		ClearTextOnFocus = false,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left,
		TextYAlignment = if multi then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center,
		TextTruncate = if multi then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(8, if multi then 6 else 0),
		Size = UDim2.new(1, -16, 1, if multi then -12 else 0),
	})
	self.Instance = root
	self.Box = box
	root.MouseEnter:Connect(function()
		self.Hover = true
		self:_render()
	end)
	root.MouseLeave:Connect(function()
		self.Hover = false
		self:_render()
	end)
	box.Focused:Connect(function()
		self.Focused = true
		box.TextTruncate = Enum.TextTruncate.None
		self:_render()
	end)
	box.FocusLost:Connect(function(enter)
		self.Focused = false
		box.TextTruncate = if multi then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd
		self:_render()
		if multi and not enter and props.CommitOnBlur == false then
			return
		end
		self:_commit()
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if self.OnChanged and self.Focused then
			self.OnChanged(box.Text, self)
		end
	end)
	theme:Watch(root, function()
		self:_render()
	end)
	return self
end

function TextField:_render()
	local theme = UI.Theme
	local stroke = self.Instance:FindFirstChild("Stroke")
	if stroke then
		stroke.Color = theme:Get(if self.Focused then "Accent" elseif self.Hover and not self.ReadOnly then "Outline" else "Border")
	end
	self.Box.TextColor3 = theme:Get(if self.ReadOnly then "Dim" else "Text")
end

function TextField:_commit()
	local text = self.Box.Text
	if text == self.Value then
		return
	end
	self.Value = text
	if self.OnCommit then
		self.OnCommit(text, self)
	end
end

function TextField:Set(value)
	self.Value = value or ""
	if not self.Focused then
		self.Box.Text = self.Value
	end
end

function TextField:Get()
	return self.Box.Text
end

function TextField:Focus()
	self.Box:CaptureFocus()
end

function TextField:Destroy()
	self.Instance:Destroy()
end

return setmetatable(TextField, {
	__call = function(_, props)
		return TextField.new(props)
	end,
})
