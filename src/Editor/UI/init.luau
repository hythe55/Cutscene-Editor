local UI = {}

UI.Theme = nil
UI.Layer = nil

local SPECIAL = {
	Events = true,
	Changed = true,
	Corner = true,
	Stroke = true,
	Padding = true,
	List = true,
	Flex = true,
	Tooltip = true,
	Font = true,
	Children = true,
}

local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }

function UI.SetTheme(theme)
	UI.Theme = theme
end

function UI.SetLayer(frame)
	UI.Layer = frame
end

function UI.Color(token, mixWith, amount)
	return { Token = token, Mix = mixWith, Amount = amount }
end

function UI.Kind(kind)
	return { Kind = kind }
end

local function isColorProperty(name)
	return string.sub(name, -6) == "Color3" or name == "Color"
end

local function isToken(name, value)
	local kind = type(value)
	if kind == "table" and (value.Token or value.Kind) then
		return true
	end
	if kind == "function" then
		return true
	end
	return kind == "string" and isColorProperty(name)
end

function UI.Set(instance, name, value)
	if isToken(name, value) and UI.Theme then
		UI.Theme:Bind(instance, name, value)
	else
		if UI.Theme and isColorProperty(name) then
			UI.Theme:Unbind(instance, name)
		end
		instance[name] = value
	end
end

local function makeCorner(value)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if typeof(value) == "UDim" then value else UDim.new(0, value)
	return corner
end

local function makeStroke(value)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local props = if type(value) == "table" and not (value.Token or value.Kind) then value else { Color = value }
	for key, entry in props do
		UI.Set(stroke, key, entry)
	end
	return stroke
end

local function makePadding(value)
	local padding = Instance.new("UIPadding")
	if type(value) == "number" then
		value = { X = value, Y = value }
	end
	local x, y = value.X or 0, value.Y or 0
	padding.PaddingLeft = UDim.new(0, value.Left or x)
	padding.PaddingRight = UDim.new(0, value.Right or x)
	padding.PaddingTop = UDim.new(0, value.Top or y)
	padding.PaddingBottom = UDim.new(0, value.Bottom or y)
	return padding
end

local function makeList(value)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	if type(value) == "string" then
		value = { FillDirection = value }
	end
	for key, entry in value do
		if key == "FillDirection" and type(entry) == "string" then
			layout.FillDirection = Enum.FillDirection[entry]
		elseif key == "Padding" and type(entry) == "number" then
			layout.Padding = UDim.new(0, entry)
		else
			layout[key] = entry
		end
	end
	return layout
end

local function makeFlex(value)
	local flex = Instance.new("UIFlexItem")
	if value == "Fill" or value == true then
		flex.FlexMode = Enum.UIFlexMode.Fill
	elseif value == "Shrink" then
		flex.FlexMode = Enum.UIFlexMode.Shrink
	elseif type(value) == "number" then
		flex.FlexMode = Enum.UIFlexMode.Custom
		flex.GrowRatio = value
		flex.ShrinkRatio = value
	end
	return flex
end

local function applyDefaults(instance, props)
	if instance:IsA("GuiObject") then
		instance.BorderSizePixel = 0
		if props.BackgroundColor3 == nil and props.BackgroundTransparency == nil then
			instance.BackgroundTransparency = 1
		end
	end
	if TEXT_CLASSES[instance.ClassName] then
		local theme = UI.Theme
		instance.FontFace = if theme then theme.Fonts.Regular else Font.fromEnum(Enum.Font.BuilderSans)
		instance.TextSize = 14
		if props.TextColor3 == nil then
			UI.Set(instance, "TextColor3", "Text")
		end
		if instance:IsA("TextBox") then
			instance.ClearTextOnFocus = false
			if props.PlaceholderColor3 == nil then
				UI.Set(instance, "PlaceholderColor3", "Faint")
			end
		end
	end
	if instance:IsA("GuiButton") then
		instance.AutoButtonColor = false
	end
	if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		instance.ScaleType = Enum.ScaleType.Fit
	end
end

function UI.Create(className, props, children)
	props = props or {}
	local instance = Instance.new(className)
	applyDefaults(instance, props)
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" and not SPECIAL[key] then
			UI.Set(instance, key, value)
		end
	end
	if props.Font then
		local theme = UI.Theme
		instance.FontFace = if type(props.Font) == "string" and theme then theme.Fonts[props.Font] else props.Font
	end
	if props.Corner then
		makeCorner(props.Corner).Parent = instance
	end
	if props.Stroke then
		makeStroke(props.Stroke).Parent = instance
	end
	if props.Padding then
		makePadding(props.Padding).Parent = instance
	end
	if props.List then
		makeList(props.List).Parent = instance
	end
	if props.Flex then
		makeFlex(props.Flex).Parent = instance
	end
	for name, fn in props.Events or {} do
		instance[name]:Connect(fn)
	end
	for name, fn in props.Changed or {} do
		instance:GetPropertyChangedSignal(name):Connect(fn)
	end
	for key, child in props.Children or children or {} do
		if type(key) == "string" then
			child.Name = key
		end
		child.Parent = instance
	end
	if props.Tooltip then
		UI.Tooltip(instance, props.Tooltip)
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UI.Label(props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextTruncate = props.TextTruncate or Enum.TextTruncate.AtEnd
	return UI.Create("TextLabel", props)
end

function UI.Divider(props)
	props = props or {}
	local vertical = props.Vertical
	props.Vertical = nil
	props.BackgroundColor3 = props.BackgroundColor3 or "Divider"
	props.Size = props.Size or (if vertical then UDim2.new(0, 1, 1, 0) else UDim2.new(1, 0, 0, 1))
	return UI.Create("Frame", props)
end

function UI.Clear(instance, keep)
	for _, child in instance:GetChildren() do
		if not (keep and keep[child.ClassName]) then
			child:Destroy()
		end
	end
end

function UI.Contains(guiObject, position)
	local origin, size = guiObject.AbsolutePosition, guiObject.AbsoluteSize
	return position.X >= origin.X and position.Y >= origin.Y and position.X <= origin.X + size.X and position.Y <= origin.Y + size.Y
end

function UI.Tween(instance, info, goals)
	local tween = game:GetService("TweenService"):Create(instance, info, goals)
	tween:Play()
	return tween
end

setmetatable(UI, {
	__index = function(_, key)
		local module = script:FindFirstChild(key)
		if module and module:IsA("ModuleScript") then
			local value = require(module)
			rawset(UI, key, value)
			return value
		end
		return nil
	end,
})

function UI.WatchRelease(input, fn)
	if typeof(input) ~= "Instance" or not input:IsA("InputObject") then
		return nil
	end
	local connection
	connection = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
		local state = input.UserInputState
		if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			connection:Disconnect()
			fn()
		end
	end)
	return connection
end

return UI
