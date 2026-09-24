local UI = require(script.Parent)
local Icons = require(script.Parent.Icons)
local Popup = require(script.Parent.Popup)
local Button = require(script.Parent.Button)

local Dropdown = {}
Dropdown.__index = Dropdown

local ROW = 24
local MAX_ROWS = 10

local function normalize(option)
	if type(option) == "table" then
		return {
			Text = option.Text or tostring(option.Value),
			Value = if option.Value ~= nil then option.Value else option.Text,
			Color = option.Color,
			Hint = option.Hint,
		}
	end
	return { Text = tostring(option), Value = option }
end

function Dropdown.new(props)
	local theme = UI.Theme
	local self = setmetatable({
		Value = props.Value,
		Options = props.Options or {},
		Placeholder = props.Placeholder or "Select…",
		OnChanged = props.OnChanged,
		Searchable = props.Searchable,
		AllowCustom = props.AllowCustom == true,
		Enabled = props.Enabled ~= false,
		Style = "Default",
		Hover = false,
		Pressed = false,
	}, Dropdown)
	local height = props.Height or theme.ControlHeight
	local root = UI.Create("TextButton", {
		Name = props.Name or "Dropdown",
		Parent = props.Parent,
		Text = "",
		LayoutOrder = props.LayoutOrder or 0,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = props.Size or UDim2.new(1, 0, 0, height),
		BackgroundColor3 = "Sunken",
		Corner = theme.Radius,
		Stroke = { Color = "Outline", Thickness = 1 },
		Tooltip = props.Tooltip,
	})
	self.Swatch = UI.Create("Frame", {
		Parent = root,
		BackgroundColor3 = "Dim",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(8, 8),
		Corner = 2,
		Visible = false,
	})
	self.Label = UI.Create("TextLabel", {
		Parent = root,
		Text = "",
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -30, 1, 0),
	})
	local chevron = UI.Create("Frame", {
		Parent = root,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
	})
	Icons.Draw("ChevronDown", chevron, "Dim", 16)
	self.Instance = root
	Button.Interact(self, root)
	root.Activated:Connect(function()
		if self.Enabled then
			self:Open()
		end
	end)
	theme:Watch(root, function()
		self:_render()
	end)
	self:_refresh()
	return self
end

function Dropdown:_options()
	local options = self.Options
	if type(options) == "function" then
		options = options()
	end
	local list = {}
	for _, option in options or {} do
		table.insert(list, normalize(option))
	end
	return list
end

function Dropdown:_render()
	local theme = UI.Theme
	local root = self.Instance
	root.BackgroundColor3 = theme:Get(if self.Hover and self.Enabled then "Panel" else "Sunken")
	local stroke = root:FindFirstChild("Stroke")
	if stroke then
		stroke.Color = theme:Get(if self.Open_ then "Accent" elseif self.Hover then "Outline" else "Border")
	end
end

function Dropdown:_refresh()
	local current
	for _, option in self:_options() do
		if option.Value == self.Value then
			current = option
		end
	end
	local text = if current then current.Text elseif self.Value ~= nil and self.Value ~= "" then tostring(self.Value) else self.Placeholder
	self.Label.Text = text
	UI.Set(self.Label, "TextColor3", if current or (self.Value ~= nil and self.Value ~= "") then (if self.Enabled then "Text" else "Dim") else "Faint")
	local color = current and current.Color
	self.Swatch.Visible = color ~= nil
	if color then
		UI.Set(self.Swatch, "BackgroundColor3", color)
	end
	self.Label.Position = UDim2.fromOffset(if color then 22 else 8, 0)
	self.Label.Size = UDim2.new(1, if color then -44 else -30, 1, 0)
end

function Dropdown:Set(value)
	self.Value = value
	self:_refresh()
end

function Dropdown:Get()
	return self.Value
end

function Dropdown:SetOptions(options)
	self.Options = options
	self:_refresh()
end

function Dropdown:SetEnabled(enabled)
	self.Enabled = enabled ~= false
	self:_refresh()
	self:_render()
end

function Dropdown:_choose(value)
	local changed = value ~= self.Value
	self:Set(value)
	if changed and self.OnChanged then
		self.OnChanged(value, self)
	end
end

function Dropdown:Open()
	local options = self:_options()
	local searchable = self.Searchable
	if searchable == nil then
		searchable = #options > 8 or self.AllowCustom
	end
	local width = math.max(self.Instance.AbsoluteSize.X, 160)
	local listHeight = math.max(math.min(#options, MAX_ROWS), 1) * ROW + 8
	local top = if searchable then 34 else 0
	local card = Popup.Card({ Name = "DropdownList", Size = UDim2.fromOffset(width, listHeight + top) })
	local list = UI.Create("ScrollingFrame", {
		Parent = card,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -top),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = "ScrollBar",
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Padding = 4,
		List = { Padding = 0 },
	})
	local handle
	local rows = {}
	local function pick(value)
		handle.Close()
		self:_choose(value)
	end
	for index, option in options do
		local button = UI.Create("TextButton", {
			Parent = list,
			LayoutOrder = index,
			Text = "",
			BackgroundColor3 = if option.Value == self.Value then "AccentSoft" else "Hover",
			BackgroundTransparency = if option.Value == self.Value then 0 else 1,
			Size = UDim2.new(1, 0, 0, ROW),
			Corner = 3,
		})
		if option.Color then
			UI.Create("Frame", {
				Parent = button,
				BackgroundColor3 = option.Color,
				Position = UDim2.fromOffset(8, 8),
				Size = UDim2.fromOffset(8, 8),
				Corner = 2,
			})
		end
		UI.Create("TextLabel", {
			Parent = button,
			Text = option.Text,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(if option.Color then 22 else 8, 0),
			Size = UDim2.new(if option.Hint then 0.6 else 1, if option.Color then -26 else -12, 1, 0),
		})
		if option.Hint then
			UI.Create("TextLabel", {
				Parent = button,
				Text = option.Hint,
				TextSize = 12,
				TextColor3 = "Dim",
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -8, 0, 0),
				Size = UDim2.new(0.4, 0, 1, 0),
			})
		end
		local selected = option.Value == self.Value
		button.MouseEnter:Connect(function()
			button.BackgroundTransparency = 0
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundTransparency = if selected then 0 else 1
		end)
		button.Activated:Connect(function()
			pick(option.Value)
		end)
		rows[index] = { Button = button, Option = option }
	end
	if searchable then
		local box = UI.Create("TextBox", {
			Parent = card,
			Text = "",
			PlaceholderText = if self.AllowCustom then "Search or type a value" else "Search",
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = "Sunken",
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.new(1, -12, 0, 24),
			Corner = 3,
			Padding = { Left = 8, Right = 8 },
		})
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local query = string.lower(box.Text)
			for _, entry in rows do
				entry.Button.Visible = query == "" or string.find(string.lower(entry.Option.Text), query, 1, true) ~= nil
			end
		end)
		box.FocusLost:Connect(function(enter)
			if not enter then
				return
			end
			for _, entry in rows do
				if entry.Button.Visible then
					pick(entry.Option.Value)
					return
				end
			end
			if self.AllowCustom and box.Text ~= "" then
				pick(box.Text)
			end
		end)
		task.defer(function()
			if box.Parent then
				box:CaptureFocus()
			end
		end)
	end
	self.Open_ = true
	self:_render()
	handle = Popup.Open(card, {
		Anchor = self.Instance,
		OnClose = function()
			self.Open_ = false
			self:_render()
		end,
	})
	return handle
end

function Dropdown:Destroy()
	self.Instance:Destroy()
end

return setmetatable(Dropdown, {
	__call = function(_, props)
		return Dropdown.new(props)
	end,
})
