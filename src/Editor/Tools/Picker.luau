local Live = require(script.Parent.Live)

local Picker = {}
Picker.__index = Picker

Picker.KeyedBias = 0.85
Picker.DepthWindow = 1.2
Picker.Reach = 0.12
Picker.MeshBias = 4

local SAMPLES = { 0, 0.25, 0.5, 0.75, 1 }

local function setUpConnections(self)
	local mouse = self.Mouse
	local plugin = self.Plugin
	local connections = self.Connections
	if mouse then
		table.insert(connections, mouse.Button1Down:Connect(function()
			if self.Active and self.OnClick then
				local ray = mouse.UnitRay
				task.defer(function()
					if self.Active then
						self.OnClick(ray)
					end
				end)
			end
		end))
		table.insert(connections, mouse.Move:Connect(function()
			if self.Active and self.OnHover then
				self.OnHover(mouse.UnitRay)
			end
		end))
	end
	if plugin then
		table.insert(connections, plugin.Deactivation:Connect(function()
			if self.Active then
				self.Active = false
				if self.OnChanged then
					self.OnChanged(false)
				end
			end
		end))
	end
end

function Picker.new(plugin, props)
	local self = setmetatable({}, Picker)
	self.Plugin = plugin
	self.Active = false
	self.OnClick = props.OnClick
	self.OnHover = props.OnHover
	self.OnChanged = props.OnChanged
	self.Connections = {}
	if plugin then
		local ok, mouse = pcall(plugin.GetMouse, plugin)
		self.Mouse = if ok then mouse else nil
	end
	setUpConnections(self)
	return self
end

function Picker:SetActive(active)
	active = active == true and self.Plugin ~= nil
	if active == self.Active then
		return
	end
	self.Active = active
	if self.Plugin then
		if active then
			pcall(self.Plugin.Activate, self.Plugin, true)
		else
			pcall(self.Plugin.Deactivate, self.Plugin)
		end
	end
	if self.OnChanged then
		self.OnChanged(active)
	end
end

local function angular(origin, direction, point)
	local offset = point - origin
	local along = offset:Dot(direction)
	if along <= 0.05 then
		return math.huge, along
	end
	return (offset - direction * along).Magnitude / along, along
end

function Picker.Positions(rig)
	local positions, children = {}, {}
	for key, joint in rig.Joints do
		local frame = Live.JointFrame(rig, key)
		if frame then
			positions[key] = frame.Position
		end
		if joint.Parent then
			children[joint.Parent] = children[joint.Parent] or {}
			table.insert(children[joint.Parent], key)
		end
	end
	return positions, children
end

function Picker.Nearest(rig, ray, keyed, skip)
	if not rig then
		return nil
	end
	local origin, direction = ray.Origin, ray.Direction.Unit
	local positions, children = Picker.Positions(rig)
	local skinned = false
	for _, joint in rig.Joints do
		if joint.Kind == "Bone" then
			skinned = true
			break
		end
	end
	local scored = {}
	for key, position in positions do
		if not (skip and skip[key]) then
			local tip = position
			local list = children[key]
			if list then
				local sum, count = Vector3.zero, 0
				for _, child in list do
					if positions[child] then
						sum += positions[child]
						count += 1
					end
				end
				if count > 0 then
					tip = sum / count
				end
			end
			local best, depth = math.huge, math.huge
			for _, s in SAMPLES do
				local score, along = angular(origin, direction, position:Lerp(tip, s))
				if score < best then
					best, depth = score, along
				end
			end
			if keyed and keyed[key] then
				best *= Picker.KeyedBias
			end
			if skinned and rig.Joints[key].Kind ~= "Bone" then
				best *= Picker.MeshBias
			end
			if best < Picker.Reach then
				table.insert(scored, { Key = key, Score = best, Depth = depth })
			end
		end
	end
	if #scored == 0 then
		return nil
	end
	table.sort(scored, function(a, b)
		return a.Score < b.Score
	end)
	local winner = scored[1]
	local limit = winner.Score * Picker.DepthWindow + 0.002
	for _, entry in scored do
		if entry.Score <= limit and entry.Depth < winner.Depth - 0.5 then
			winner = entry
		end
	end
	return winner.Key, winner.Score
end

function Picker:Destroy()
	self:SetActive(false)
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
end

return Picker
