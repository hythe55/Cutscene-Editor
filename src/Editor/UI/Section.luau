local UI = require(script.Parent)
local Icons = require(script.Parent.Icons)

local Section = {}
Section.__index = Section

function Section.new(props)
	local self = setmetatable({
		Collapsed = props.Collapsed == true,
		OnToggled = props.OnToggled,
	}, Section)
	local root = UI.Create("Frame", {
		Name = props.Name or "Section",
		Parent = props.Parent,
		LayoutOrder = props.LayoutOrder or 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		List = { Padding = 0 },
	})
	local header = UI.Create("TextButton", {
		Name = "Header",
		Parent = root,
		LayoutOrder = 1,
		Text = "",
		BackgroundColor3 = "Surface",
		Size = UDim2.new(1, 0, 0, 28),
	})
	UI.Divider({ Parent = header, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1) })
	local chevron = UI.Create("Frame", {
		Parent = header,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
	})
	self.Chevron = chevron
	self.Title = UI.Create("TextLabel", {
		Parent = header,
		Text = props.Title or "",
		Font = "Bold",
		TextSize = 12,
		TextColor3 = "SubText",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(26, 0),
		Size = UDim2.new(1, -34, 1, 0),
	})
	self.Accessory = UI.Create("Frame", {
		Name = "Accessory",
		Parent = header,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		List = { FillDirection = "Horizontal", Padding = 4, VerticalAlignment = Enum.VerticalAlignment.Center },
	})
	local content = UI.Create("Frame", {
		Name = "Content",
		Parent = root,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = props.Padding or { X = 10, Top = 8, Bottom = 10 },
		List = { Padding = props.Spacing or 6 },
	})
	self.Instance = root
	self.Header = header
	self.Content = content
	header.MouseEnter:Connect(function()
		UI.Set(header, "BackgroundColor3", "Hover")
	end)
	header.MouseLeave:Connect(function()
		UI.Set(header, "BackgroundColor3", "Surface")
	end)
	header.Activated:Connect(function()
		self:SetCollapsed(not self.Collapsed)
		if self.OnToggled then
			self.OnToggled(self.Collapsed, self)
		end
	end)
	self:_render()
	return self
end

function Section:_render()
	for _, child in self.Chevron:GetChildren() do
		child:Destroy()
	end
	Icons.Draw(if self.Collapsed then "ChevronRight" else "ChevronDown", self.Chevron, "Dim", 16)
	self.Content.Visible = not self.Collapsed
end

function Section:SetCollapsed(collapsed)
	self.Collapsed = collapsed == true
	self:_render()
end

function Section:SetTitle(text)
	self.Title.Text = text
end

function Section:Destroy()
	self.Instance:Destroy()
end

return setmetatable(Section, {
	__call = function(_, props)
		return Section.new(props)
	end,
})
