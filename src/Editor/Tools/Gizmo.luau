local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local Gizmo = {}
Gizmo.__index = Gizmo

Gizmo.RotateColor = Color3.fromRGB(255, 196, 64)
Gizmo.MoveColor = Color3.fromRGB(64, 196, 255)

local function setUpConnections(self)
	local connections = self.Connections
	local arcs, handles = self.Arcs, self.Handles
	table.insert(connections, arcs.MouseButton1Down:Connect(function()
		self:_begin("Rotate")
	end))
	table.insert(connections, arcs.MouseDrag:Connect(function(axis, angle)
		if self.Dragging == "Rotate" and self.OnRotate then
			self.OnRotate(axis, angle)
		end
	end))
	table.insert(connections, arcs.MouseButton1Up:Connect(function()
		self:_finish()
	end))
	table.insert(connections, handles.MouseButton1Down:Connect(function()
		self:_begin("Move")
	end))
	table.insert(connections, handles.MouseDrag:Connect(function(face, distance)
		if self.Dragging == "Move" and self.OnMove then
			self.OnMove(face, distance)
		end
	end))
	table.insert(connections, handles.MouseButton1Up:Connect(function()
		self:_finish()
	end))
	for _, adornment in { arcs, handles } do
		table.insert(connections, adornment.MouseEnter:Connect(function()
			self.Hovering += 1
		end))
		table.insert(connections, adornment.MouseLeave:Connect(function()
			self.Hovering = math.max(self.Hovering - 1, 0)
		end))
	end
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and self.Dragging then
			task.defer(function()
				self:_finish()
			end)
		end
	end))
end

function Gizmo.new(props)
	local self = setmetatable({}, Gizmo)
	props = props or {}
	self.OnBegin = props.OnBegin
	self.OnRotate = props.OnRotate
	self.OnMove = props.OnMove
	self.OnEnd = props.OnEnd
	self.Mode = props.Mode or "Rotate"
	self.Dragging = nil
	self.Hovering = 0
	self.Shown = false
	self.Connections = {}
	local folder = Instance.new("Folder")
	folder.Name = props.Name or "CutsceneEditorGizmo"
	folder.Archivable = false
	local proxy = Instance.new("Part")
	proxy.Name = "Proxy"
	proxy.Archivable = false
	proxy.Anchored = true
	proxy.CanCollide = false
	proxy.CanQuery = false
	proxy.CanTouch = false
	proxy.Locked = true
	proxy.CastShadow = false
	proxy.Transparency = 1
	proxy.Size = Vector3.one
	proxy.Parent = folder
	local arcs = Instance.new("ArcHandles")
	arcs.Name = "Rotate"
	arcs.Archivable = false
	arcs.Axes = Axes.new(Enum.Axis.X, Enum.Axis.Y, Enum.Axis.Z)
	arcs.Adornee = proxy
	arcs.Visible = false
	arcs.Parent = folder
	local handles = Instance.new("Handles")
	handles.Name = "Move"
	handles.Archivable = false
	handles.Style = Enum.HandlesStyle.Movement
	handles.Color3 = props.MoveColor or Gizmo.MoveColor
	handles.Adornee = proxy
	handles.Visible = false
	handles.Parent = folder
	folder.Parent = props.Parent or CoreGui
	self.Folder, self.Proxy, self.Arcs, self.Handles = folder, proxy, arcs, handles
	setUpConnections(self)
	return self
end

function Gizmo:_render()
	local shown = self.Shown
	self.Arcs.Visible = shown and self.Mode == "Rotate"
	self.Handles.Visible = shown and self.Mode == "Move"
end

function Gizmo:_begin(kind)
	if self.Dragging then
		return
	end
	self.Dragging = kind
	self.Origin = self.Proxy.CFrame
	if self.OnBegin then
		self.OnBegin(kind)
	end
end

function Gizmo:_finish()
	local kind = self.Dragging
	if not kind then
		return
	end
	self.Dragging = nil
	if self.OnEnd then
		self.OnEnd(kind)
	end
end

function Gizmo:Cancel()
	self.Dragging = nil
end

function Gizmo:SetMode(mode)
	self.Mode = if mode == "Move" then "Move" else "Rotate"
	self:_render()
end

function Gizmo:Show(cframe, size)
	if cframe then
		self.Proxy.CFrame = cframe
	end
	if size then
		local value = math.max(size, 0.05)
		self.Proxy.Size = Vector3.new(value, value, value)
	end
	if not self.Shown then
		self.Shown = true
		self:_render()
	end
end

function Gizmo:SetCFrame(cframe)
	self.Proxy.CFrame = cframe
end

function Gizmo:Hide()
	if self.Dragging then
		self:_finish()
	end
	if self.Shown then
		self.Shown = false
		self.Hovering = 0
		self:_render()
	end
end

function Gizmo:IsHovered()
	return self.Shown and (self.Hovering > 0 or self.Dragging ~= nil)
end

function Gizmo.RotateDelta(axis, angle)
	return CFrame.fromAxisAngle(Vector3.FromAxis(axis), angle)
end

function Gizmo.MoveDelta(face, distance)
	return Vector3.FromNormalId(face) * distance
end

function Gizmo.SizeFor(position, fraction)
	local camera = workspace.CurrentCamera
	local distance = if camera then (camera.CFrame.Position - position).Magnitude else 20
	return math.clamp(distance * (fraction or 0.06), 0.1, 40)
end

function Gizmo.CameraMoved(owner)
	local camera = workspace.CurrentCamera
	local position = camera and camera.CFrame.Position
	if position and (not owner.CameraPosition or (position - owner.CameraPosition).Magnitude > 0.25) then
		owner.CameraPosition = position
		return true
	end
	return false
end

function Gizmo:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	self.Dragging = nil
	self.Folder:Destroy()
end

return Gizmo
