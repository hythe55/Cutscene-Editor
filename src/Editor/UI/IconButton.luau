local UI = require(script.Parent)
local Icons = require(script.Parent.Icons)
local Button = require(script.Parent.Button)

local IconButton = {}
IconButton.__index = IconButton

function IconButton.new(props)
	local theme = UI.Theme
	local size = props.Size or theme.ControlHeight
	local self = setmetatable({
		Style = props.Style or "Ghost",
		Enabled = props.Enabled ~= false,
		Toggle = props.Toggle == true,
		Active = props.Value == true or props.Active == true,
		Value = props.Value == true,
		Hover = false,
		Pressed = false,
		OnClick = props.OnClick,
		OnChanged = props.OnChanged,
		ActiveColor = props.ActiveColor,
	}, IconButton)
	local root = UI.Create("TextButton", {
		Name = props.Name or "IconButton",
		Parent = props.Parent,
		Text = "",
		LayoutOrder = props.LayoutOrder or 0,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = if typeof(size) == "UDim2" then size else UDim2.fromOffset(size, size),
		BackgroundColor3 = "Raised",
		Corner = props.Corner or theme.Radius,
		Stroke = { Color = "Outline", Thickness = 1 },
		Tooltip = props.Tooltip,
	})
	self.TooltipAttached = props.Tooltip ~= nil
	self.Instance = root
	self.IconName = props.Icon
	self.IconFrame = Icons.Draw(props.Icon, root, "Text", props.IconSize)
	Button.Interact(self, root)
	root.Activated:Connect(function()
		if not self.Enabled then
			return
		end
		if self.Toggle then
			self:Set(not self.Value)
			if self.OnChanged then
				self.OnChanged(self.Value, self)
			end
		end
		if self.OnClick then
			self.OnClick(self)
		end
	end)
	theme:Watch(root, function()
		self:_render()
	end)
	return self
end

function IconButton:_render()
	local theme = UI.Theme
	local bg, bgAlpha, text, stroke, strokeAlpha = Button.Colors(theme, self.Style, self)
	if self.Active and self.ActiveColor then
		local color = theme:Resolve(self.ActiveColor)
		text = color
		bg = theme:Get("Window"):Lerp(color, if self.Hover then 0.3 else 0.22)
		stroke = color
	end
	local root = self.Instance
	root.BackgroundColor3 = bg
	root.BackgroundTransparency = bgAlpha
	local uiStroke = root:FindFirstChild("Stroke")
	if uiStroke then
		uiStroke.Color = stroke
		uiStroke.Transparency = strokeAlpha
	end
	for _, child in self.IconFrame:GetDescendants() do
		if child:IsA("ImageLabel") then
			child.ImageColor3 = text
		elseif child:IsA("UIStroke") then
			child.Color = text
		elseif child:IsA("Frame") and child.BackgroundTransparency < 1 then
			child.BackgroundColor3 = text
		end
	end
end

function IconButton:SetIcon(name)
	if name == self.IconName then
		return
	end
	self.IconName = name
	self.IconFrame:Destroy()
	self.IconFrame = Icons.Draw(name, self.Instance, "Text")
	self:_render()
end

function IconButton:Set(value)
	self.Value = value == true
	self.Active = self.Value
	self:_render()
end

function IconButton:Get()
	return self.Value
end

function IconButton:SetEnabled(enabled)
	self.Enabled = enabled ~= false
	self:_render()
end

function IconButton:SetTooltip(text)
	if not self.TooltipAttached then
		self.TooltipAttached = true
		UI.Tooltip(self.Instance, text)
	end
	self.Instance:SetAttribute("TooltipText", text)
end

function IconButton:Destroy()
	self.Instance:Destroy()
end

return setmetatable(IconButton, {
	__call = function(_, props)
		return IconButton.new(props)
	end,
})
