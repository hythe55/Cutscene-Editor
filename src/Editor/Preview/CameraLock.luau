local CameraLock = {}
CameraLock.__index = CameraLock

local EPSILON = 1e-3
local LOOK_TOLERANCE = 1e-6
local MIN_FOCUS = 1
local MAX_FOCUS = 500

local function moved(a, b)
	if (a.Position - b.Position).Magnitude > EPSILON then
		return true
	end
	return a.LookVector:Dot(b.LookVector) < 1 - LOOK_TOLERANCE
end

CameraLock.Moved = moved

local function snapshot(camera)
	return {
		Camera = camera,
		CFrame = camera.CFrame,
		Focus = camera.Focus,
		FieldOfView = camera.FieldOfView,
	}
end

function CameraLock.new(container, onUserInput)
	local self = setmetatable({}, CameraLock)
	self.OnUserInput = onUserInput
	self.Engaged = false
	self.Saved = nil
	self.LastWritten = nil
	self.Context = nil
	self.Moved = {}
	self.Connections = {}
	local proxy = Instance.new("Camera")
	proxy.Name = "CutsceneCamera"
	proxy.Archivable = false
	proxy.CFrame = workspace.CurrentCamera and workspace.CurrentCamera.CFrame or CFrame.identity
	proxy.FieldOfView = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70
	proxy.Parent = container
	self.Proxy = proxy
	table.insert(self.Connections, proxy.ChildAdded:Connect(function(child)
		self:_route(child)
	end))
	table.insert(self.Connections, proxy:GetPropertyChangedSignal("CFrame"):Connect(function()
		self:Write()
	end))
	table.insert(self.Connections, proxy:GetPropertyChangedSignal("FieldOfView"):Connect(function()
		self:Write()
	end))
	return self
end

function CameraLock:Attach(timeline)
	local ctx = timeline and timeline.Context
	self.Context = ctx
	if not ctx then
		return
	end
	local claimed = ctx.CameraSaved
	local real = ctx.Camera
	ctx.Camera = self.Proxy
	if claimed and real and real ~= self.Proxy then
		real.CameraType = claimed.CameraType
		real.CFrame = claimed.CFrame
		real.Focus = claimed.Focus
		real.FieldOfView = claimed.FieldOfView
		ctx.CameraSaved = nil
	end
end

function CameraLock:Detach()
	self.Context = nil
end

function CameraLock:Owner()
	local ctx = self.Context
	return ctx and ctx.CameraOwner
end

function CameraLock:_real()
	return workspace.CurrentCamera
end

function CameraLock:_route(child)
	if not child:IsA("PostEffect") or child.Parent ~= self.Proxy then
		return
	end
	if child:IsA("DepthOfFieldEffect") and not self.Engaged then
		return
	end
	local real = self:_real()
	if real and pcall(function()
		child.Parent = real
	end) then
		self.Moved[child] = true
	end
end

function CameraLock:_moveFocusEffects(toReal)
	if toReal then
		for _, child in self.Proxy:GetChildren() do
			self:_route(child)
		end
	else
		for effect in self.Moved do
			if effect:IsA("DepthOfFieldEffect") then
				self.Moved[effect] = nil
				if effect.Parent then
					pcall(function()
						effect.Parent = self.Proxy
					end)
				end
			end
		end
	end
end

function CameraLock:Engage()
	if self.Engaged then
		return
	end
	local real = self:_real()
	if not real then
		return
	end
	self.Saved = snapshot(real)
	self.Engaged = true
	self.LastWritten = real.CFrame
	self:_moveFocusEffects(true)
	self:Write()
end

function CameraLock:Disengage(restore)
	if not self.Engaged then
		return
	end
	self.Engaged = false
	self:_moveFocusEffects(false)
	local saved = self.Saved
	self.Saved = nil
	self.LastWritten = nil
	local camera = saved and saved.Camera
	if camera and camera.Parent then
		if restore ~= false then
			camera.CFrame = saved.CFrame
			camera.Focus = saved.Focus
		else
			local distance = math.clamp((saved.Focus.Position - saved.CFrame.Position).Magnitude, MIN_FOCUS, MAX_FOCUS)
			local current = camera.CFrame
			camera.Focus = CFrame.new(current.Position + current.LookVector * distance)
		end
		camera.FieldOfView = saved.FieldOfView
	end
end

function CameraLock:CheckInput()
	if not self.Engaged or not self.LastWritten then
		return false
	end
	local real = self:_real()
	if not real or real ~= (self.Saved and self.Saved.Camera) then
		return false
	end
	if moved(real.CFrame, self.LastWritten) then
		self.LastTrip = { Found = real.CFrame, Expected = self.LastWritten }
		self:Disengage(false)
		if self.OnUserInput then
			task.spawn(self.OnUserInput)
		end
		return true
	end
	return false
end

function CameraLock:Write()
	if not self.Engaged then
		return
	end
	if self:CheckInput() then
		return
	end
	if not self:Owner() then
		return
	end
	local real = self:_real()
	local proxy = self.Proxy
	if not real or real == proxy then
		return
	end
	real.CFrame = proxy.CFrame
	real.Focus = proxy.Focus
	if real.FieldOfView ~= proxy.FieldOfView then
		real.FieldOfView = proxy.FieldOfView
	end
	self.LastWritten = real.CFrame
end

function CameraLock:InGap()
	return self.Engaged and self:Owner() == nil
end

function CameraLock:Destroy()
	self:Disengage(true)
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	for effect in self.Moved do
		if effect.Parent and effect.Parent ~= self.Proxy then
			effect:Destroy()
		end
	end
	table.clear(self.Moved)
	self.Proxy:Destroy()
end

return CameraLock
