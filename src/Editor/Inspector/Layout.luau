local UI = require(script.Parent.Parent.UI)

local Layout = {}

Layout.LabelWidth = 0.4
Layout.RowHeight = 26

function Layout.Section(inspector, order, key, title)
	local app = inspector.App
	local collapsed = app:GetSetting("Inspector.Collapsed." .. key, false) == true
	local section = UI.Section({
		Name = key,
		Parent = inspector.Content,
		LayoutOrder = order,
		Title = title,
		Collapsed = collapsed,
		OnToggled = function(value)
			app:SetSetting("Inspector.Collapsed." .. key, value)
		end,
	})
	return section, section.Content
end

function Layout.Row(parent, order, label, options)
	options = options or {}
	local height = Layout.RowHeight
	local row = UI.Create("Frame", {
		Name = options.Name or label,
		Parent = parent,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, if options.Stacked then 0 else height),
		AutomaticSize = Enum.AutomaticSize.Y,
		List = if options.Stacked then { Padding = 3 } else nil,
	})
	local text = UI.Create("TextLabel", {
		Name = "Label",
		Parent = row,
		LayoutOrder = 1,
		Text = label,
		TextSize = 13,
		TextColor3 = "SubText",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = if options.Stacked then UDim2.new(1, 0, 0, 16) else UDim2.new(Layout.LabelWidth, -8, 0, height),
	})
	if options.Tooltip then
		UI.Tooltip(text, options.Tooltip)
	end
	local holder = UI.Create("Frame", {
		Name = "Control",
		Parent = row,
		LayoutOrder = 2,
		Position = if options.Stacked then nil else UDim2.fromScale(Layout.LabelWidth, 0),
		Size = if options.Stacked then UDim2.new(1, 0, 0, 0) else UDim2.new(1 - Layout.LabelWidth, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	return row, holder, text
end

function Layout.Text(parent, order, text, props)
	props = props or {}
	return UI.Create("TextLabel", {
		Name = props.Name or "Note",
		Parent = parent,
		LayoutOrder = order,
		Text = text,
		RichText = props.RichText == true,
		TextSize = props.TextSize or 12,
		Font = props.Font,
		TextColor3 = props.Color or "Dim",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
end

function Layout.Buttons(parent, order, name)
	return UI.Create("Frame", {
		Name = name or "Buttons",
		Parent = parent,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		List = { FillDirection = "Horizontal", Padding = 6, Wraps = true, VerticalAlignment = Enum.VerticalAlignment.Center },
	})
end

function Layout.Button(parent, order, text, onClick, props)
	props = props or {}
	return UI.Button({
		Name = props.Name or text,
		Parent = parent,
		LayoutOrder = order,
		Text = text,
		Icon = props.Icon,
		Style = props.Style or "Default",
		Height = props.Height or 24,
		TextSize = props.TextSize or 13,
		Tooltip = props.Tooltip,
		Enabled = props.Enabled,
		OnClick = onClick,
	})
end

function Layout.Status(parent, order, name)
	local frame = UI.Create("Frame", {
		Name = name or "Status",
		Parent = parent,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = "Sunken",
		Corner = 4,
		Padding = { X = 8, Y = 6 },
		List = { FillDirection = "Horizontal", Padding = 6, VerticalAlignment = Enum.VerticalAlignment.Center },
	})
	local dot = UI.Create("Frame", {
		Name = "Dot",
		Parent = frame,
		LayoutOrder = 1,
		BackgroundColor3 = "Dim",
		Size = UDim2.fromOffset(8, 8),
		Corner = UDim.new(1, 0),
	})
	local label = UI.Create("TextLabel", {
		Name = "Text",
		Parent = frame,
		LayoutOrder = 2,
		Text = "",
		TextSize = 13,
		Font = "Medium",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -14, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	local status = { Instance = frame }
	function status.Set(text, color)
		label.Text = text
		UI.Set(label, "TextColor3", color or "Text")
		UI.Set(dot, "BackgroundColor3", color or "Dim")
	end
	return status
end

function Layout.FormatTime(t)
	t = math.max(t or 0, 0)
	local minutes = math.floor(t / 60)
	return string.format("%d:%05.2f", minutes, t - minutes * 60)
end

function Layout.Seconds(t)
	return string.format("%.2f s", t or 0)
end

return Layout
