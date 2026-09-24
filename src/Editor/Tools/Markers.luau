local CoreGui = game:GetService("CoreGui")

local Markers = {}
Markers.__index = Markers

local CLASSES = { Sphere = "SphereHandleAdornment", Line = "LineHandleAdornment", Cone = "ConeHandleAdornment", Box = "BoxHandleAdornment" }

function Markers.new(name, onTop)
	local self = setmetatable({}, Markers)
	self.OnTop = onTop == true
	local folder = Instance.new("Folder")
	folder.Name = name or "CutsceneEditorMarkers"
	folder.Archivable = false
	folder.Parent = CoreGui
	self.Folder = folder
	self.Pools = {}
	self.Used = {}
	self.Clicks = {}
	return self
end

function Markers:_take(kind)
	local pool = self.Pools[kind]
	if not pool then
		pool = {}
		self.Pools[kind] = pool
	end
	local used = self.Used[kind] or 0
	used += 1
	self.Used[kind] = used
	local adornment = pool[used]
	if not adornment then
		adornment = Instance.new(CLASSES[kind])
		adornment.Name = kind
		adornment.Archivable = false
		adornment.AlwaysOnTop = self.OnTop
		adornment.ZIndex = 1
		adornment.Adornee = workspace.Terrain
		adornment.Parent = self.Folder
		adornment.MouseButton1Down:Connect(function()
			local fn = self.Clicks[adornment]
			if fn then
				fn()
			end
		end)
		pool[used] = adornment
	end
	adornment.Visible = true
	self.Clicks[adornment] = nil
	return adornment
end

function Markers:Begin()
	table.clear(self.Used)
end

function Markers:End()
	for kind, pool in self.Pools do
		local used = self.Used[kind] or 0
		for index = used + 1, #pool do
			local adornment = pool[index]
			adornment.Visible = false
			self.Clicks[adornment] = nil
		end
	end
end

function Markers:Clear()
	self:Begin()
	self:End()
end

function Markers:Sphere(position, radius, color, transparency, onClick)
	local sphere = self:_take("Sphere")
	sphere.CFrame = CFrame.new(position)
	sphere.Radius = radius
	sphere.Color3 = color
	sphere.Transparency = transparency or 0
	sphere.ZIndex = if onClick then 3 else 1
	self.Clicks[sphere] = onClick
	return sphere
end

function Markers:Line(from, to, color, thickness, transparency)
	local delta = to - from
	local length = delta.Magnitude
	if length < 1e-4 then
		return nil
	end
	local line = self:_take("Line")
	line.CFrame = CFrame.lookAt(from, to)
	line.Length = length
	line.Thickness = thickness or 2
	line.Color3 = color
	line.Transparency = transparency or 0
	return line
end

function Markers:Cone(cframe, height, radius, color, transparency, onClick)
	local cone = self:_take("Cone")
	cone.CFrame = cframe
	cone.Height = height
	cone.Radius = radius
	cone.Color3 = color
	cone.Transparency = transparency or 0
	cone.ZIndex = if onClick then 3 else 1
	self.Clicks[cone] = onClick
	return cone
end

function Markers:Polyline(points, color, thickness, transparency)
	for index = 1, #points - 1 do
		self:Line(points[index], points[index + 1], color, thickness, transparency)
	end
end

function Markers:Destroy()
	table.clear(self.Clicks)
	self.Folder:Destroy()
end

return Markers
