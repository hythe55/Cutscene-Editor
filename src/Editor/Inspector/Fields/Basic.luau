local UI = require(script.Parent.Parent.Parent.UI)

local Basic = {}

local function busyNumber(widget)
	return widget.Dragging or widget.Focused
end

local function busyVector(vector)
	for _, field in vector.Fields do
		if busyNumber(field) then
			return true
		end
	end
	return false
end

function Basic.Wrap(widget, extra)
	local field = { Instance = widget.Instance, Widget = widget }
	function field:Set(value)
		widget:Set(value)
	end
	function field:SetEnabled(enabled)
		if widget.SetEnabled then
			widget:SetEnabled(enabled)
		end
	end
	function field:Destroy()
		widget:Destroy()
	end
	for key, value in extra or {} do
		field[key] = value
	end
	return field
end

function Basic.number(entry, ctx)
	local widget = UI.NumberField({
		Parent = ctx.Parent,
		Value = ctx.Value,
		Min = entry.Min,
		Max = entry.Max,
		Step = entry.Step or 0.05,
		Decimals = entry.Decimals,
		OnCommit = function(value)
			ctx.Commit(value)
		end,
	})
	return Basic.Wrap(widget, {
		Busy = function()
			return busyNumber(widget)
		end,
	})
end

function Basic.string(entry, ctx)
	if entry.Options then
		return Basic.enum(entry, ctx, true)
	end
	local widget = UI.TextField({
		Parent = ctx.Parent,
		Value = if ctx.Value == nil then "" else tostring(ctx.Value),
		Placeholder = ctx.Placeholder or entry.Placeholder,
		ReadOnly = ctx.ReadOnly,
		OnCommit = function(text)
			ctx.Commit(text)
		end,
	})
	return Basic.Wrap(widget, {
		Set = function(_, value)
			widget:Set(if value == nil then "" else tostring(value))
		end,
		Busy = function()
			return widget.Focused
		end,
	})
end

function Basic.bool(_entry, ctx)
	local widget = UI.Toggle({
		Parent = ctx.Parent,
		Value = ctx.Value == true,
		OnChanged = function(value)
			ctx.Commit(value)
		end,
	})
	return Basic.Wrap(widget, {
		Set = function(_, value)
			widget:Set(value == true)
		end,
	})
end

function Basic.enum(entry, ctx, custom)
	local widget = UI.Dropdown({
		Parent = ctx.Parent,
		Value = ctx.Value,
		Options = ctx.Options or entry.Options or {},
		AllowCustom = custom == true or entry.AllowCustom == true,
		Placeholder = ctx.Placeholder or "(none)",
		OnChanged = function(value)
			ctx.Commit(value)
		end,
	})
	return Basic.Wrap(widget)
end

Basic.easing = Basic.enum
Basic.direction = Basic.enum

function Basic.Color3(_entry, ctx)
	local widget = UI.ColorField({
		Parent = ctx.Parent,
		Value = if typeof(ctx.Value) == "Color3" then ctx.Value else Color3.new(1, 1, 1),
		OnCommit = function(value)
			ctx.Commit(value)
		end,
	})
	return Basic.Wrap(widget, {
		Busy = function()
			return widget.Box:IsFocused()
		end,
	})
end

function Basic.Vector3(entry, ctx)
	local widget = UI.Vector3Field({
		Parent = ctx.Parent,
		Value = if typeof(ctx.Value) == "Vector3" then ctx.Value else Vector3.zero,
		Step = entry.Step or 0.05,
		Decimals = entry.Decimals or 3,
		OnCommit = function(value)
			ctx.Commit(value)
		end,
	})
	return Basic.Wrap(widget, {
		Busy = function()
			return busyVector(widget)
		end,
	})
end

function Basic.CFrame(entry, ctx)
	local widget = UI.CFrameField({
		Parent = ctx.Parent,
		Value = if typeof(ctx.Value) == "CFrame" then ctx.Value else CFrame.identity,
		Step = entry.Step or 0.05,
		Transform = ctx.Transform,
		FromCamera = if ctx.FromCamera ~= nil then ctx.FromCamera else entry.FromCamera,
		FromSelection = entry.FromSelection,
		OnCommit = function(value)
			ctx.Commit(value)
		end,
	})
	return Basic.Wrap(widget, {
		Busy = function()
			return busyVector(widget.Position) or busyVector(widget.Rotation)
		end,
	})
end

return Basic
