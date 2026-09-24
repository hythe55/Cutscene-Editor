local Gizmo = require(script.Parent.Gizmo)
local KeyMath = require(script.Parent.KeyMath)
local Live = require(script.Parent.Live)

local NEAR = 1.5

local function eyePosition()
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position
end

local function near(eye, position)
	return eye ~= nil and (position - eye).Magnitude < NEAR
end

local function segmentNear(eye, a, b)
	if not eye then
		return false
	end
	local ab = b - a
	local length = ab:Dot(ab)
	local t = if length > 1e-9 then math.clamp((eye - a):Dot(ab) / length, 0, 1) else 0
	return (a + ab * t - eye).Magnitude < NEAR
end

return function(KeyTool)
	KeyTool.NearCamera = NEAR
	KeyTool.NearEye = near

	function KeyTool:_buildPath()
		local app = self.App
		local clip, kind, props = self.Clip, self.Kind, self.Props
		local cache = { Points = {}, Keys = {} }
		self.Path = cache
		if not clip or kind == "Attach" then
			return
		end
		local keys = self:_keyList()
		cache.Entries = keys
		if self.ShowPath then
			cache.Points = KeyMath.Path(app, app.Deps.Spline, kind, props, keys)
		end
		for _, entry in keys do
			local world = KeyMath.KeyWorld(app, kind, props, entry.CFrame, entry.Time)
			if world then
				table.insert(cache.Keys, { Entry = entry, World = world })
			end
		end
	end

	function KeyTool:_drawKeys(eye)
		local markers = self.Markers
		local app = self.App
		local kind, props = self.Kind, self.Props
		local colors = KeyTool.Colors
		local cache = self.Path
		local points = cache.Points
		for index = 1, #points - 1 do
			local a, b = points[index], points[index + 1]
			if not segmentNear(eye, a, b) then
				markers:Line(a, b, colors.Path, 3, 0)
			end
		end
		for _, item in cache.Keys do
			local entry, world = item.Entry, item.World
			if not near(eye, world.Position) then
				local selected = entry.Instance == self.Key
				local size = Gizmo.SizeFor(world.Position, 0.016)
				local color = if selected then colors.Selected else colors.Key
				markers:Sphere(world.Position, size * (if selected then 1.3 else 1), color, 0, function()
					self:SelectKey(entry.Instance)
				end)
				if kind == "Camera" then
					local corners = KeyMath.Frustum(world, entry.FOV, size * 5)
					local edge = if selected then colors.Selected else colors.Frustum
					for index, corner in corners do
						markers:Line(world.Position, corner, edge, 1, 0.3)
						markers:Line(corner, corners[index % 4 + 1], edge, 1, 0.3)
					end
				end
			end
		end
		local entries = cache.Entries
		if entries and #entries > 0 and KeyMath.Inside(props, app.Time) then
			local localTime = KeyMath.ToLocal(props, app.Time)
			local cframe = app.Deps.Spline.Evaluate(entries, localTime, props.Interpolation)
			local world = cframe and KeyMath.KeyWorld(app, kind, props, cframe, localTime)
			if world and not near(eye, world.Position) then
				markers:Sphere(world.Position, Gizmo.SizeFor(world.Position, 0.008), colors.Playhead, 0)
			end
		end
	end

	function KeyTool:Redraw()
		local markers = self.Markers
		local eye = eyePosition()
		markers:Begin()
		if self.Path and self.Clip and self.Kind ~= "Attach" then
			self:_drawKeys(eye)
		end
		markers:End()
		local target = self:TargetWorld()
		local preview = self.App.Preview
		local playing = preview and preview.Playing
		if self.Drag then
			if target then
				self.Gizmo:SetCFrame(target)
			end
		elseif target and not playing and not Live.Locked(self.Clip) and not near(eye, target.Position) then
			self.Gizmo:Show(target, Gizmo.SizeFor(target.Position, 0.05))
		else
			self.Gizmo:Hide()
		end
	end
end
