local UI = require(script.Parent.Parent.UI)

local Widgets = {}

Widgets.Height = 24

function Widgets.Page(parent)
	local scroll = UI.Create("ScrollingFrame", {
		Name = "Scroll",
		Parent = parent,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = "ScrollBar",
		Padding = { X = 8, Top = 8, Bottom = 10 },
		List = { Padding = 6 },
	})
	return scroll
end

function Widgets.Row(parent, order, height, padding)
	return UI.Create("Frame", {
		Parent = parent,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height or Widgets.Height),
		List = { FillDirection = "Horizontal", Padding = padding or 4, VerticalAlignment = Enum.VerticalAlignment.Center },
	})
end

function Widgets.Wrap(parent, order)
	return UI.Create("Frame", {
		Parent = parent,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		List = { FillDirection = "Horizontal", Padding = 4, Wraps = true },
	})
end

function Widgets.Caption(parent, text, order, color)
	return UI.Label({
		Parent = parent,
		LayoutOrder = order,
		Text = text,
		TextSize = 12,
		TextColor3 = color or "Dim",
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
end

function Widgets.Title(parent, text, order)
	return UI.Label({
		Parent = parent,
		LayoutOrder = order,
		Text = text,
		Font = "Bold",
		TextSize = 14,
		Size = UDim2.new(1, 0, 0, 18),
	})
end

function Widgets.Button(parent, text, onClick, props)
	props = props or {}
	return UI.Button({
		Parent = parent,
		Text = text,
		Icon = props.Icon,
		Style = props.Style,
		Height = props.Height or Widgets.Height,
		TextSize = props.TextSize or 13,
		PaddingX = props.PaddingX or 8,
		Size = props.Size,
		LayoutOrder = props.LayoutOrder or 0,
		Tooltip = props.Tooltip,
		OnClick = onClick,
	})
end

function Widgets.Segmented(parent, options, value, onChanged, props)
	props = props or {}
	local holder = UI.Create("Frame", {
		Parent = parent,
		LayoutOrder = props.LayoutOrder or 0,
		Size = UDim2.fromOffset(0, Widgets.Height),
		AutomaticSize = Enum.AutomaticSize.X,
		List = { FillDirection = "Horizontal", Padding = 2 },
	})
	local control = { Value = value, Buttons = {}, Instance = holder }
	function control.Set(_, newValue)
		control.Value = newValue
		for option, button in control.Buttons do
			button:SetActive(option == newValue)
		end
	end
	for index, option in options do
		local key = if type(option) == "table" then option.Value else option
		local label = if type(option) == "table" then option.Text else tostring(option)
		local button = Widgets.Button(holder, label, function()
			control:Set(key)
			if onChanged then
				onChanged(key)
			end
		end, { LayoutOrder = index, PaddingX = 7, Tooltip = if type(option) == "table" then option.Tooltip else nil })
		control.Buttons[key] = button
	end
	control:Set(value)
	return control
end

function Widgets.Empty(parent, title, text)
	local holder = UI.Create("Frame", {
		Parent = parent,
		Name = "Empty",
		Size = UDim2.fromScale(1, 1),
		Padding = 16,
		Visible = false,
	})
	local column = UI.Create("Frame", {
		Parent = holder,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		List = { Padding = 4, HorizontalAlignment = Enum.HorizontalAlignment.Center },
	})
	local heading = UI.Create("TextLabel", {
		Parent = column,
		LayoutOrder = 1,
		Text = title,
		Font = "Medium",
		TextSize = 13,
		TextColor3 = "SubText",
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	local body = UI.Create("TextLabel", {
		Parent = column,
		LayoutOrder = 2,
		Text = text,
		TextSize = 12,
		TextColor3 = "Dim",
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	return { Instance = holder, Title = heading, Body = body }
end

return Widgets
