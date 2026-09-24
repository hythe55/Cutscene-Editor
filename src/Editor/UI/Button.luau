local UI = require(script.Parent)
local Icons = require(script.Parent.Icons)

local Button = {}
Button.__index = Button

local STYLES = {
	Default = { Bg = "Raised", Hover = "Hover", Pressed = "Pressed", Text = "Text", Stroke = "Outline" },
	Primary = { Bg = "Accent", Hover = "AccentHover", Pressed = "AccentPressed", Text = "AccentText" },
	Ghost = { Text = "SubText", HoverText = "Text", Hover = "Hover", Pressed = "Pressed" },
	Danger = { Bg = "Raised", Hover = "ErrorSoft", Pressed = "ErrorSoft", Text = "Error", Stroke = "Outline" },
	Toolbar = { Text = "SubText", HoverText = "Text", Hover = "Hover", Pressed = "Pressed" },
}

function Button.Colors(theme, styleName, state)
	local style = STYLES[styleName] or STYLES.Default
	local bg, bgAlpha, text, stroke, strokeAlpha
	if state.Active then
		bg, bgAlpha = theme:Get("AccentSoft"), 0
		text = theme:Get("Accent")
		stroke, strokeAlpha = theme:Get("Accent"), 0.35
		if state.Hover then
			bg = bg:Lerp(theme:Get("Accent"), 0.15)
		end
	else
		local token = style.Bg
		if state.Pressed and style.Pressed then
			token = style.Pressed
		elseif state.Hover and style.Hover then
			token = style.Hover
		end
		bg, bgAlpha = if token then theme:Get(token) else theme:Get("Window"), if token then 0 else 1
		text = theme:Get(if state.Hover and style.HoverText then style.HoverText else style.Text)
		stroke, strokeAlpha = if style.Stroke then theme:Get(style.Stroke) else theme:Get("Border"), if style.Stroke then 0 else 1
	end
	if state.Enabled == false then
		text = theme:Get("Faint")
		bgAlpha = if bgAlpha < 1 then math.max(bgAlpha, 0.35) else 1
		if style == STYLES.Primary then
			bg = theme:Get("Raised")
			bgAlpha = 0
		end
	end
	return bg, bgAlpha, text, stroke, strokeAlpha
end

function Button.Interact(self, root)
	root.MouseEnter:Connect(function()
		self.Hover = true
		self:_render()
	end)
	root.MouseLeave:Connect(function()
		self.Hover = false
		self.Pressed = false
		self:_render()
	end)
	root.MouseButton1Down:Connect(function()
		self.Pressed = true
		self:_render()
	end)
	root.MouseButton1Up:Connect(function()
		self.Pressed = false
		self:_render()
	end)
end

function Button.new(props)
	local theme = UI.Theme
	local self = setmetatable({
		Style = props.Style or "Default",
		Enabled = props.Enabled ~= false,
		Active = props.Active == true,
		Hover = false,
		Pressed = false,
		OnClick = props.OnClick,
	}, Button)
	local height = props.Height or theme.ControlHeight
	local root = UI.Create("TextButton", {
		Name = props.Name or "Button",
		Parent = props.Parent,
		Text = "",
		LayoutOrder = props.LayoutOrder or 0,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Visible = props.Visible ~= false,
		Size = props.Size or UDim2.fromOffset(0, height),
		AutomaticSize = if props.Size then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
		BackgroundColor3 = "Raised",
		ClipsDescendants = true,
		Corner = props.Corner or theme.Radius,
		Stroke = { Color = "Outline", Thickness = 1 },
		Tooltip = props.Tooltip,
	})
	self.TooltipAttached = props.Tooltip ~= nil
	local content = UI.Create("Frame", {
		Name = "Content",
		Parent = root,
		Size = UDim2.fromScale(if props.Size then 1 else 0, 1),
		AutomaticSize = if props.Size then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
		Padding = { Left = props.PaddingX or (if props.Text and props.Text ~= "" then 10 else 5), Right = props.PaddingX or (if props.Text and props.Text ~= "" then 10 else 5) },
		List = {
			FillDirection = "Horizontal",
			Padding = 6,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			HorizontalAlignment = props.Align or Enum.HorizontalAlignment.Center,
		},
	})
	if props.Icon then
		local holder = UI.Create("Frame", { Name = "IconHolder", Parent = content, Size = UDim2.fromOffset(16, 16), LayoutOrder = 1 })
		self.IconFrame = Icons.Draw(props.Icon, holder, "Text")
	end
	self.Label = UI.Create("TextLabel", {
		Name = "Label",
		Parent = content,
		Text = props.Text or "",
		Visible = props.Text ~= nil and props.Text ~= "",
		Font = props.Font or "Medium",
		TextSize = props.TextSize or 14,
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
	})
	if props.Trailing then
		local holder = UI.Create("Frame", { Name = "TrailingHolder", Parent = content, Size = UDim2.fromOffset(12, 16), LayoutOrder = 3 })
		self.TrailingFrame = Icons.Draw(props.Trailing, holder, "Text", 12)
	end
	self.Instance = root
	self.Content = content
	Button.Interact(self, root)
	root.Activated:Connect(function()
		if self.Enabled and self.OnClick then
			self.OnClick(self)
		end
	end)
	theme:Watch(root, function()
		self:_render()
	end)
	return self
end

function Button:_render()
	local theme = UI.Theme
	local bg, bgAlpha, text, stroke, strokeAlpha = Button.Colors(theme, self.Style, self)
	local root = self.Instance
	root.BackgroundColor3 = bg
	root.BackgroundTransparency = bgAlpha
	local uiStroke = root:FindFirstChild("Stroke")
	if uiStroke then
		uiStroke.Color = stroke
		uiStroke.Transparency = strokeAlpha
	end
	self.Label.TextColor3 = text
	for _, frame in { self.IconFrame, self.TrailingFrame } do
		if frame then
			for _, child in frame:GetDescendants() do
				if child:IsA("ImageLabel") then
					child.ImageColor3 = text
				elseif child:IsA("UIStroke") then
					child.Color = text
				elseif child:IsA("Frame") and child.BackgroundTransparency < 1 then
					child.BackgroundColor3 = text
				end
			end
		end
	end
end

function Button:SetText(text)
	self.Label.Text = text or ""
	self.Label.Visible = text ~= nil and text ~= ""
end

function Button:SetEnabled(enabled)
	self.Enabled = enabled ~= false
	self:_render()
end

function Button:SetActive(active)
	self.Active = active == true
	self:_render()
end

function Button:SetStyle(style)
	self.Style = style
	self:_render()
end

function Button:SetTooltip(text)
	if not self.TooltipAttached then
		self.TooltipAttached = true
		UI.Tooltip(self.Instance, text)
	end
	self.Instance:SetAttribute("TooltipText", text)
end

function Button:Destroy()
	self.Instance:Destroy()
end

return setmetatable(Button, {
	__call = function(_, props)
		return Button.new(props)
	end,
})
