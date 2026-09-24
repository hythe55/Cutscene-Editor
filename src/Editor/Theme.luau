local Signal = require(script.Parent.Signal)

local Theme = {}
Theme.__index = Theme

local Guide = Enum.StudioStyleGuideColor
local Modifier = Enum.StudioStyleGuideModifier

local SANS = "rbxasset://fonts/families/BuilderSans.json"
local MONO = "rbxasset://fonts/families/BuilderMono.json"

Theme.Fonts = {
	Regular = Font.new(SANS, Enum.FontWeight.Regular),
	Medium = Font.new(SANS, Enum.FontWeight.Medium),
	Bold = Font.new(SANS, Enum.FontWeight.Bold),
	Mono = Font.new(MONO, Enum.FontWeight.Regular),
	MonoBold = Font.new(MONO, Enum.FontWeight.Bold),
}

Theme.TextSize = { Small = 12, Body = 14, Title = 15, Large = 18 }
Theme.Radius = 4
Theme.Spacing = 8
Theme.ControlHeight = 26

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

local FALLBACK = {
	Dark = {
		MainBackground = Color3.fromRGB(46, 46, 46),
		Titlebar = Color3.fromRGB(53, 53, 53),
		InputFieldBackground = Color3.fromRGB(37, 37, 37),
		Border = Color3.fromRGB(34, 34, 34),
		MainText = Color3.fromRGB(204, 204, 204),
		SubText = Color3.fromRGB(170, 170, 170),
		DimmedText = Color3.fromRGB(110, 110, 110),
		MainButton = Color3.fromRGB(0, 162, 255),
		Button = Color3.fromRGB(60, 60, 60),
		WarningText = Color3.fromRGB(255, 176, 0),
		ErrorText = Color3.fromRGB(255, 68, 68),
		ScrollBar = Color3.fromRGB(85, 85, 85),
	},
	Light = {
		MainBackground = Color3.fromRGB(255, 255, 255),
		Titlebar = Color3.fromRGB(243, 243, 243),
		InputFieldBackground = Color3.fromRGB(255, 255, 255),
		Border = Color3.fromRGB(182, 182, 182),
		MainText = Color3.fromRGB(0, 0, 0),
		SubText = Color3.fromRGB(80, 80, 80),
		DimmedText = Color3.fromRGB(150, 150, 150),
		MainButton = Color3.fromRGB(0, 162, 255),
		Button = Color3.fromRGB(247, 247, 247),
		WarningText = Color3.fromRGB(197, 124, 0),
		ErrorText = Color3.fromRGB(215, 38, 38),
		ScrollBar = Color3.fromRGB(205, 205, 205),
	},
}

local function mix(a, b, t)
	return a:Lerp(b, t)
end

local function luminance(color)
	return 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
end

local function studio()
	local ok, value = pcall(function()
		return settings().Studio.Theme
	end)
	return if ok then value else nil
end

local function reader(source, forced)
	local name = forced or (source and source.Name) or "Dark"
	local fallback = FALLBACK[name] or FALLBACK.Dark
	return function(guide, modifier)
		if source then
			local ok, color = pcall(source.GetColor, source, Guide[guide], modifier and Modifier[modifier] or Modifier.Default)
			if ok and typeof(color) == "Color3" then
				return color
			end
		end
		return fallback[guide] or fallback.MainText
	end
end

local function palette(source, forced)
	local get = reader(source, forced)
	local window = get("MainBackground")
	local dark = luminance(window) < 0.5
	local text = get("MainText")
	local accent = get("MainButton")
	local shade = if dark then BLACK else WHITE
	local lift = if dark then WHITE else BLACK
	local colors = {
		Window = window,
		Surface = if dark then mix(window, lift, 0.035) else mix(window, BLACK, 0.035),
		Panel = if dark then mix(window, BLACK, 0.12) else mix(window, BLACK, 0.02),
		Sunken = if dark then mix(window, BLACK, 0.22) else mix(window, BLACK, 0.045),
		Raised = if dark then mix(window, lift, 0.08) else WHITE,
		Hover = if dark then mix(window, lift, 0.13) else mix(window, BLACK, 0.07),
		Pressed = if dark then mix(window, lift, 0.18) else mix(window, BLACK, 0.11),
		Border = if dark then mix(window, BLACK, 0.4) else mix(window, BLACK, 0.16),
		Divider = if dark then mix(window, BLACK, 0.3) else mix(window, BLACK, 0.1),
		Outline = if dark then mix(window, lift, 0.16) else mix(window, BLACK, 0.2),
		Text = text,
		SubText = mix(text, window, 0.28),
		Dim = mix(text, window, 0.5),
		Faint = mix(text, window, 0.72),
		Accent = accent,
		AccentHover = mix(accent, lift, 0.12),
		AccentPressed = mix(accent, shade, 0.15),
		AccentText = WHITE,
		AccentSoft = mix(window, accent, if dark then 0.22 else 0.14),
		Selection = mix(window, accent, if dark then 0.3 else 0.2),
		Warning = get("WarningText"),
		WarningSoft = mix(window, get("WarningText"), 0.18),
		Error = get("ErrorText"),
		ErrorSoft = mix(window, get("ErrorText"), 0.18),
		Success = if dark then Color3.fromRGB(88, 200, 128) else Color3.fromRGB(28, 150, 76),
		Lane = if dark then mix(window, BLACK, 0.2) else mix(window, BLACK, 0.03),
		LaneAlt = if dark then mix(window, BLACK, 0.15) else mix(window, BLACK, 0.05),
		GroupRow = if dark then mix(window, lift, 0.02) else mix(window, BLACK, 0.07),
		ScrollBar = get("ScrollBar"),
		Tooltip = if dark then Color3.fromRGB(24, 24, 26) else Color3.fromRGB(252, 252, 252),
		Scrim = BLACK,
		Shadow = BLACK,
		Playhead = Color3.fromRGB(255, 72, 72),
		Lock = Color3.fromRGB(236, 164, 64),
		Mute = Color3.fromRGB(236, 96, 96),
		White = WHITE,
		Black = BLACK,
	}
	return colors, dark
end

function Theme.new(schema)
	local self = setmetatable({}, Theme)
	self.Schema = schema
	self.Fonts = Theme.Fonts
	self.TextSize = Theme.TextSize
	self.Radius = Theme.Radius
	self.Spacing = Theme.Spacing
	self.ControlHeight = Theme.ControlHeight
	self.Changed = Signal.new()
	self.Bindings = {}
	self.Connections = {}
	self:Refresh()
	local ok, studioSettings = pcall(function()
		return settings().Studio
	end)
	if ok and studioSettings then
		table.insert(
			self.Connections,
			studioSettings.ThemeChanged:Connect(function()
				self:Refresh()
			end)
		)
	end
	return self
end

function Theme:Refresh(forced)
	local source = if forced then nil else studio()
	self.Name = forced or (source and source.Name) or "Dark"
	self.Colors, self.IsDark = palette(source, forced)
	for instance, properties in self.Bindings do
		for property, token in properties do
			self:_apply(instance, property, token)
		end
	end
	self.Changed:Fire(self)
end

function Theme:Get(name)
	return self.Colors[name] or self.Colors.Text
end

function Theme:Kind(kind)
	local schema = self.Schema
	local definition = schema and schema.Kinds and schema.Kinds[kind]
	return definition and definition.Color or self.Colors.Dim
end

function Theme:Resolve(token)
	if type(token) == "string" then
		return self:Get(token)
	elseif type(token) == "function" then
		return token(self)
	elseif type(token) == "table" then
		if token.Kind then
			return self:Kind(token.Kind)
		end
		local color = self:Get(token.Token)
		if token.Mix then
			color = color:Lerp(self:Get(token.Mix), token.Amount or 0.5)
		end
		return color
	end
	return token
end

function Theme:_apply(instance, property, token)
	local ok, err = pcall(function()
		instance[property] = self:Resolve(token)
	end)
	if not ok then
		warn("CutsceneEditor theme: " .. tostring(err))
	end
end

function Theme:Bind(instance, property, token)
	local properties = self.Bindings[instance]
	if not properties then
		properties = {}
		self.Bindings[instance] = properties
		instance.Destroying:Connect(function()
			self.Bindings[instance] = nil
		end)
	end
	properties[property] = token
	self:_apply(instance, property, token)
	return instance
end

function Theme:Unbind(instance, property)
	local properties = self.Bindings[instance]
	if properties then
		properties[property] = nil
	end
end

function Theme:Watch(instance, fn)
	fn(self)
	local connection
	connection = self.Changed:Connect(fn)
	instance.Destroying:Connect(function()
		connection:Disconnect()
	end)
	return connection
end

function Theme:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	table.clear(self.Bindings)
	self.Changed:Destroy()
end

return Theme
