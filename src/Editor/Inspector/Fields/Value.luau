local UI = require(script.Parent.Parent.Parent.UI)
local Basic = require(script.Parent.Basic)

local Value = {}
Value.__index = Value

local TYPES = { "Empty", "Number", "Bool", "Text", "Color3", "Vector3", "CFrame" }

local DEFAULTS = {
	Number = function()
		return 0
	end,
	Bool = function()
		return false
	end,
	Text = function()
		return ""
	end,
	Color3 = function()
		return Color3.new(1, 1, 1)
	end,
	Vector3 = function()
		return Vector3.zero
	end,
	CFrame = function()
		return CFrame.identity
	end,
}

local BUILDERS = {
	Number = function(ctx)
		return Basic.number({ Step = 0.05 }, ctx)
	end,
	Bool = function(ctx)
		return Basic.bool({}, ctx)
	end,
	Text = function(ctx)
		return Basic.string({}, ctx)
	end,
	Color3 = function(ctx)
		return Basic.Color3({}, ctx)
	end,
	Vector3 = function(ctx)
		return Basic.Vector3({}, ctx)
	end,
	CFrame = function(ctx)
		return Basic.CFrame({ FromCamera = false }, ctx)
	end,
}

local function typeOf(value)
	local kind = typeof(value)
	if value == nil then
		return "Empty"
	elseif kind == "number" then
		return "Number"
	elseif kind == "boolean" then
		return "Bool"
	elseif kind == "string" then
		return "Text"
	elseif kind == "Color3" or kind == "Vector3" or kind == "CFrame" then
		return kind
	end
	return "Other"
end

function Value.new(_entry, ctx)
	local self = setmetatable({ Ctx = ctx, Value = ctx.Value, Kind = typeOf(ctx.Value) }, Value)
	local root = UI.Create("Frame", {
		Name = "ValueField",
		Parent = ctx.Parent,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		List = { Padding = 4 },
	})
	self.Instance = root
	self.TypePicker = UI.Dropdown({
		Parent = root,
		LayoutOrder = 1,
		Value = self.Kind,
		Options = TYPES,
		OnChanged = function(kind)
			local default = DEFAULTS[kind]
			ctx.Commit(if default then default() else nil)
		end,
	})
	self.Holder = UI.Create("Frame", {
		Parent = root,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	self:_build()
	return self
end

function Value:_build()
	if self.Editor then
		self.Editor:Destroy()
		self.Editor = nil
	end
	local builder = BUILDERS[self.Kind]
	if builder then
		self.Editor = builder({
			Parent = self.Holder,
			Value = self.Value,
			App = self.Ctx.App,
			Commit = self.Ctx.Commit,
		})
	elseif self.Kind == "Other" then
		local label = UI.Create("TextLabel", {
			Parent = self.Holder,
			Text = typeof(self.Value) .. ": " .. tostring(self.Value),
			TextSize = 12,
			TextColor3 = "Dim",
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		})
		self.Editor = { Destroy = function()
			label:Destroy()
		end, Set = function() end }
	end
end

function Value:Busy()
	local editor = self.Editor
	return editor ~= nil and editor.Busy ~= nil and editor:Busy()
end

function Value:Set(value)
	local kind = typeOf(value)
	self.Value = value
	if kind ~= self.Kind then
		self.Kind = kind
		self.TypePicker:Set(kind)
		self:_build()
	elseif self.Editor then
		self.Editor:Set(value)
	end
end

function Value:SetEnabled(enabled)
	self.TypePicker:SetEnabled(enabled)
end

function Value:Destroy()
	self.Instance:Destroy()
end

return {
	value = function(entry, ctx)
		return Value.new(entry, ctx)
	end,
}
