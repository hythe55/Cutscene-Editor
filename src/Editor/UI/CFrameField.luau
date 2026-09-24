local Selection = game:GetService("Selection")

local UI = require(script.Parent)
local Vector3Field = require(script.Parent.Vector3Field)
local Button = require(script.Parent.Button)

local CFrameField = {}
CFrameField.__index = CFrameField

local function rotationOf(cframe)
	local x, y, z = cframe:ToOrientation()
	return Vector3.new(math.deg(x), math.deg(y), math.deg(z))
end

local function compose(position, rotation)
	return CFrame.new(position) * CFrame.fromOrientation(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
end

local function selectedCFrame()
	for _, instance in Selection:Get() do
		if instance:IsA("PVInstance") then
			return instance:GetPivot()
		elseif instance:IsA("Attachment") then
			return instance.WorldCFrame
		elseif instance:IsA("Camera") then
			return instance.CFrame
		end
	end
	return nil
end

local function row(parent, order, text, height)
	local frame = UI.Create("Frame", {
		Parent = parent,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height),
	})
	UI.Create("TextLabel", {
		Parent = frame,
		Text = text,
		TextSize = 12,
		TextColor3 = "Dim",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0, 54, 1, 0),
	})
	return frame
end

function CFrameField.new(props)
	local theme = UI.Theme
	local self = setmetatable({
		Value = props.Value or CFrame.identity,
		OnChanged = props.OnChanged,
		OnCommit = props.OnCommit,
		Transform = props.Transform,
	}, CFrameField)
	local height = theme.ControlHeight
	local root = UI.Create("Frame", {
		Name = props.Name or "CFrameField",
		Parent = props.Parent,
		LayoutOrder = props.LayoutOrder or 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		List = { Padding = 4 },
	})
	self.Instance = root
	local function changed(commit)
		self.Value = compose(self.Position:Get(), self.Rotation:Get())
		local callback = if commit then self.OnCommit else self.OnChanged
		if callback then
			callback(self.Value, self)
		end
	end
	local positionRow = row(root, 1, "Position", height)
	self.Position = Vector3Field.new({
		Parent = positionRow,
		Position = UDim2.fromOffset(56, 0),
		Size = UDim2.new(1, -56, 1, 0),
		Value = self.Value.Position,
		Step = props.Step or 0.05,
		OnChanged = function()
			changed(false)
		end,
		OnCommit = function()
			changed(true)
		end,
	})
	local rotationRow = row(root, 2, "Rotation", height)
	self.Rotation = Vector3Field.new({
		Parent = rotationRow,
		Position = UDim2.fromOffset(56, 0),
		Size = UDim2.new(1, -56, 1, 0),
		Value = rotationOf(self.Value),
		Step = 1,
		Decimals = 1,
		OnChanged = function()
			changed(false)
		end,
		OnCommit = function()
			changed(true)
		end,
	})
	if props.FromCamera ~= false or props.FromSelection ~= false then
		local actions = UI.Create("Frame", {
			Parent = root,
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, 24),
			Padding = { Left = 56 },
			List = { FillDirection = "Horizontal", Padding = 6 },
		})
		local function apply(cframe)
			if not cframe then
				return
			end
			if self.Transform then
				cframe = self.Transform(cframe)
			end
			if not cframe then
				return
			end
			self:Set(cframe)
			if self.OnCommit then
				self.OnCommit(self.Value, self)
			end
		end
		if props.FromCamera ~= false then
			Button.new({
				Parent = actions,
				Text = "From camera",
				Icon = "Camera",
				Height = 22,
				TextSize = 12,
				Style = "Default",
				OnClick = function()
					local camera = workspace.CurrentCamera
					apply(camera and camera.CFrame)
				end,
			})
		end
		if props.FromSelection ~= false then
			Button.new({
				Parent = actions,
				Text = "From selection",
				Height = 22,
				TextSize = 12,
				Style = "Default",
				OnClick = function()
					apply(selectedCFrame())
				end,
			})
		end
	end
	return self
end

function CFrameField:Set(value)
	if typeof(value) ~= "CFrame" then
		return
	end
	self.Value = value
	self.Position:Set(value.Position)
	self.Rotation:Set(rotationOf(value))
end

function CFrameField:Get()
	return self.Value
end

function CFrameField:SetEnabled(enabled)
	self.Position:SetEnabled(enabled)
	self.Rotation:SetEnabled(enabled)
end

function CFrameField:Destroy()
	self.Instance:Destroy()
end

return setmetatable(CFrameField, {
	__call = function(_, props)
		return CFrameField.new(props)
	end,
})
