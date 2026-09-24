local UI = require(script.Parent)
local NumberField = require(script.Parent.NumberField)

local Vector3Field = {}
Vector3Field.__index = Vector3Field

Vector3Field.AxisColors = {
	X = Color3.fromRGB(226, 92, 92),
	Y = Color3.fromRGB(110, 190, 90),
	Z = Color3.fromRGB(86, 140, 230),
}

function Vector3Field.new(props)
	local self = setmetatable({
		Value = props.Value or Vector3.zero,
		OnChanged = props.OnChanged,
		OnCommit = props.OnCommit,
		Fields = {},
	}, Vector3Field)
	local root = UI.Create("Frame", {
		Name = props.Name or "Vector3Field",
		Parent = props.Parent,
		LayoutOrder = props.LayoutOrder or 0,
		Position = props.Position,
		Size = props.Size or UDim2.new(1, 0, 0, props.Height or UI.Theme.ControlHeight),
		Tooltip = props.Tooltip,
		List = { FillDirection = "Horizontal", Padding = 4 },
	})
	self.Instance = root
	for index, axis in { "X", "Y", "Z" } do
		self.Fields[axis] = NumberField.new({
			Parent = root,
			LayoutOrder = index,
			Size = UDim2.new(1 / 3, -3, 1, 0),
			Label = axis,
			LabelColor = Vector3Field.AxisColors[axis],
			Value = self.Value[axis],
			Step = props.Step or 0.1,
			Decimals = props.Decimals,
			Min = props.Min,
			Max = props.Max,
			OnChanged = function()
				self.Value = self:_read()
				if self.OnChanged then
					self.OnChanged(self.Value, self)
				end
			end,
			OnCommit = function()
				self.Value = self:_read()
				if self.OnCommit then
					self.OnCommit(self.Value, self)
				end
			end,
		})
	end
	return self
end

function Vector3Field:_read()
	return Vector3.new(self.Fields.X:Get(), self.Fields.Y:Get(), self.Fields.Z:Get())
end

function Vector3Field:Set(value)
	if typeof(value) ~= "Vector3" then
		return
	end
	self.Value = value
	self.Fields.X:Set(value.X)
	self.Fields.Y:Set(value.Y)
	self.Fields.Z:Set(value.Z)
end

function Vector3Field:Get()
	return self.Value
end

function Vector3Field:SetEnabled(enabled)
	for _, field in self.Fields do
		field:SetEnabled(enabled)
	end
end

function Vector3Field:Destroy()
	self.Instance:Destroy()
end

return setmetatable(Vector3Field, {
	__call = function(_, props)
		return Vector3Field.new(props)
	end,
})
