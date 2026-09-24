local UI = require(script.Parent)
local Popup = require(script.Parent.Popup)
local NumberField = require(script.Parent.NumberField)

local ColorField = {}
ColorField.__index = ColorField

local function hexOf(color)
	return string.format("#%02X%02X%02X", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
end

local function parse(text)
	text = string.gsub(text, "%s", "")
	local hex = string.match(text, "^#?(%x%x%x%x%x%x)$")
	if hex then
		return Color3.fromHex(hex)
	end
	local r, g, b = string.match(text, "^(%d+%.?%d*),(%d+%.?%d*),(%d+%.?%d*)$")
	if r then
		return Color3.fromRGB(math.clamp(tonumber(r), 0, 255), math.clamp(tonumber(g), 0, 255), math.clamp(tonumber(b), 0, 255))
	end
	return nil
end

function ColorField.new(props)
	local theme = UI.Theme
	local self = setmetatable({
		Value = props.Value or Color3.new(1, 1, 1),
		OnChanged = props.OnChanged,
		OnCommit = props.OnCommit,
	}, ColorField)
	local height = props.Height or theme.ControlHeight
	local root = UI.Create("Frame", {
		Name = props.Name or "ColorField",
		Parent = props.Parent,
		LayoutOrder = props.LayoutOrder or 0,
		Position = props.Position,
		Size = props.Size or UDim2.new(1, 0, 0, height),
		BackgroundColor3 = "Sunken",
		Corner = theme.Radius,
		Stroke = { Color = "Border", Thickness = 1 },
		Tooltip = props.Tooltip,
	})
	local swatch = UI.Create("TextButton", {
		Name = "Swatch",
		Parent = root,
		Text = "",
		BackgroundColor3 = self.Value,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.new(0, 28, 1, -8),
		Corner = 3,
		Stroke = { Color = "Outline", Thickness = 1 },
	})
	local box = UI.Create("TextBox", {
		Parent = root,
		Text = hexOf(self.Value),
		Font = "Mono",
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(40, 0),
		Size = UDim2.new(1, -46, 1, 0),
	})
	self.Instance = root
	self.Swatch = swatch
	self.Box = box
	box.FocusLost:Connect(function()
		local color = parse(box.Text)
		if color then
			self:_commit(color)
		else
			box.Text = hexOf(self.Value)
		end
	end)
	swatch.Activated:Connect(function()
		self:Open()
	end)
	return self
end

function ColorField:_commit(color)
	local changed = color ~= self.Value
	self:Set(color)
	if changed and self.OnCommit then
		self.OnCommit(color, self)
	end
end

function ColorField:Open()
	local start = self.Value
	local card = Popup.Card({ Name = "ColorPopup", Size = UDim2.fromOffset(220, 118), Padding = 8, List = { Padding = 6 } })
	local preview = UI.Create("Frame", {
		Parent = card,
		LayoutOrder = 0,
		BackgroundColor3 = start,
		Size = UDim2.new(1, 0, 0, 22),
		Corner = 3,
	})
	local fields = {}
	local function current()
		return Color3.fromRGB(fields.R:Get(), fields.G:Get(), fields.B:Get())
	end
	for index, channel in { "R", "G", "B" } do
		fields[channel] = NumberField.new({
			Parent = card,
			LayoutOrder = index,
			Label = channel,
			Height = 22,
			Value = math.round(start[channel] * 255),
			Min = 0,
			Max = 255,
			Step = 1,
			Decimals = 0,
			OnChanged = function()
				local color = current()
				preview.BackgroundColor3 = color
				self.Swatch.BackgroundColor3 = color
				if self.OnChanged then
					self.OnChanged(color, self)
				end
			end,
			OnCommit = function()
				local color = current()
				preview.BackgroundColor3 = color
				self:_commit(color)
			end,
		})
	end
	return Popup.Open(card, { Anchor = self.Instance })
end

function ColorField:Set(color)
	if typeof(color) ~= "Color3" then
		return
	end
	self.Value = color
	self.Swatch.BackgroundColor3 = color
	self.Box.Text = hexOf(color)
end

function ColorField:Get()
	return self.Value
end

function ColorField:Destroy()
	self.Instance:Destroy()
end

return setmetatable(ColorField, {
	__call = function(_, props)
		return ColorField.new(props)
	end,
})
