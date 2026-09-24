local Rig = {}
Rig.__index = Rig

local IDENTITY = CFrame.identity

local function findRoot(model, motorsByPart1)
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	local humanoidRoot = model:FindFirstChild("HumanoidRootPart")
	if humanoidRoot and humanoidRoot:IsA("BasePart") then
		return humanoidRoot
	end
	local best, bestScore = nil, -1
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not motorsByPart1[part] then
			local score = 0
			for _, child in part:GetChildren() do
				if child:IsA("Bone") then
					score += 1
				end
			end
			if score > bestScore then
				best, bestScore = part, score
			end
		end
	end
	return best
end

local function addJoint(self, joint)
	self.Joints[joint.Key] = joint
	table.insert(self.List, joint)
	local existing = self.Names[joint.Name]
	if not existing or self.Joints[existing].Depth > joint.Depth then
		self.Names[joint.Name] = joint.Key
	end
end

local function addBones(self, parent, prefix, parentKey, base, depth)
	for _, child in parent:GetChildren() do
		if child:IsA("Bone") then
			local key = if prefix == "" then child.Name else prefix .. "/" .. child.Name
			addJoint(self, {
				Key = key,
				Name = child.Name,
				Instance = child,
				Kind = "Bone",
				Parent = parentKey,
				Base = if parentKey then nil else base,
				Rest = child.CFrame,
				Depth = depth,
			})
			addBones(self, child, key, key, nil, depth + 1)
		end
	end
end

local function jointInfo(instance)
	if instance:IsA("Motor6D") then
		return instance.Part0, instance.Part1, instance.C0, instance.C1
	elseif instance:IsA("AnimationConstraint") then
		local a0, a1 = instance.Attachment0, instance.Attachment1
		if a0 and a1 and a0.Parent and a1.Parent and a0.Parent:IsA("BasePart") and a1.Parent:IsA("BasePart") then
			return a0.Parent, a1.Parent, a0.CFrame, a1.CFrame
		end
	end
	return nil
end

function Rig.new(model, mode)
	local self = setmetatable({}, Rig)
	self.Model = model
	self.Mode = mode or "Direct"
	self.Joints = {}
	self.List = {}
	self.Names = {}
	self.Frame = {}
	self.Last = {}
	self.Bases = {}
	self.FrameBase = {}
	self.Building = false
	self.Released = true
	self.Scale = if model:IsA("Model") then model:GetScale() else 1

	local motorsByPart1 = {}
	local infos = {}
	for _, descendant in model:GetDescendants() do
		local part0, part1, c0, c1 = jointInfo(descendant)
		if part0 and part1 and part1:IsDescendantOf(model) then
			motorsByPart1[part1] = descendant
			infos[descendant] = { Part0 = part0, C0 = c0, C1 = c1 }
		end
	end
	self.Root = findRoot(model, motorsByPart1)

	local partKeys = {}
	local function partKey(part)
		if part == self.Root then
			return ""
		end
		local cached = partKeys[part]
		if cached ~= nil then
			return cached or nil
		end
		partKeys[part] = false
		local motor = motorsByPart1[part]
		if not motor then
			return nil
		end
		local info = infos[motor]
		local parentKey = partKey(info.Part0)
		if parentKey == nil then
			return nil
		end
		local key = if parentKey == "" then part.Name else parentKey .. "/" .. part.Name
		partKeys[part] = key
		local parentJoint = self.Joints[parentKey]
		addJoint(self, {
			Key = key,
			Name = part.Name,
			Instance = motor,
			Kind = "Motor6D",
			Parent = if parentKey == "" then nil else parentKey,
			Base = if parentKey == "" then info.Part0 else nil,
			Rest = info.C0 * info.C1:Inverse(),
			C0 = info.C0,
			C1 = info.C1,
			C1Inverse = info.C1:Inverse(),
			Depth = if parentJoint then parentJoint.Depth + 1 else 1,
		})
		if motor.Name ~= part.Name and not self.Names[motor.Name] then
			self.Names[motor.Name] = key
		end
		return key
	end

	if self.Root then
		for part in motorsByPart1 do
			partKey(part)
		end
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				local key = partKey(part)
				if key ~= nil then
					local joint = self.Joints[key]
					addBones(self, part, key, if key == "" then nil else key, part, if joint then joint.Depth + 1 else 1)
				end
			end
		end
	end

	table.sort(self.List, function(a, b)
		return a.Depth < b.Depth
	end)
	self:_computeRest()
	return self
end

function Rig:_computeRest()
	local pivot = self.Model:GetPivot()
	for _, joint in self.List do
		local parentRest
		if joint.Parent then
			parentRest = self.Joints[joint.Parent].RestChar
		else
			parentRest = pivot:ToObjectSpace(joint.Base.CFrame)
		end
		joint.RestChar = parentRest * joint.Rest
	end
end

function Rig:Find(nameOrKey)
	return self.Joints[nameOrKey] or self.Joints[self.Names[nameOrKey] or ""]
end

function Rig:PoseToTransform(cframe)
	if self.Scale == 1 then
		return cframe
	end
	return cframe + cframe.Position * (self.Scale - 1)
end

function Rig:TransformToPose(cframe)
	if self.Scale == 1 then
		return cframe
	end
	return cframe + cframe.Position * (1 / self.Scale - 1)
end

function Rig:_base(key)
	if self.Mode ~= "Animator" then
		return IDENTITY
	end
	local base = self.FrameBase[key]
	if not base then
		base = self.Joints[key].Instance.Transform
		self.FrameBase[key] = base
	end
	return base
end

function Rig:Transform(key)
	local value = self.Frame[key]
	if value then
		return value
	end
	if self.Building then
		return self:_base(key)
	end
	value = self.Last[key]
	if value then
		return value
	end
	if self.Mode == "Animator" then
		return self.Joints[key].Instance.Transform
	end
	return IDENTITY
end

function Rig:Release()
	if self.Released then
		return
	end
	self.Released = true
	if self.Mode ~= "Animator" then
		return
	end
	local joints, bases = self.Joints, self.Bases
	for key in self.Last do
		local instance = joints[key].Instance
		if instance.Parent then
			instance.Transform = bases[key] or IDENTITY
		end
	end
end

function Rig:Begin()
	if not self.Released then
		self:Release()
	end
	table.clear(self.Frame)
	table.clear(self.FrameBase)
	self.Building = true
end

function Rig:Blend(key, cframe, weight)
	if not self.Joints[key] or weight <= 0 then
		return
	end
	if self.Scale ~= 1 then
		cframe += cframe.Position * (self.Scale - 1)
	end
	if weight >= 1 then
		self.Frame[key] = cframe
	else
		self.Frame[key] = (self.Frame[key] or self:_base(key)):Lerp(cframe, weight)
	end
end

function Rig:Additive(key, cframe)
	if not self.Joints[key] then
		return
	end
	self.Frame[key] = (self.Frame[key] or self:_base(key)) * cframe
end

function Rig:Set(key, cframe)
	if self.Joints[key] then
		self.Frame[key] = self:PoseToTransform(cframe)
	end
end

function Rig:Apply()
	local frame, last, joints = self.Frame, self.Last, self.Joints
	if self.Mode == "Animator" then
		local bases = self.Bases
		table.clear(bases)
		for key, value in frame do
			bases[key] = self:_base(key)
			joints[key].Instance.Transform = value
		end
	else
		for key, value in frame do
			if last[key] ~= value then
				joints[key].Instance.Transform = value
			end
		end
		for key in last do
			if frame[key] == nil then
				joints[key].Instance.Transform = IDENTITY
			end
		end
	end
	self.Last, self.Frame = frame, last
	table.clear(self.Frame)
	self.Building = false
	self.Released = next(self.Last) == nil
end

function Rig:Reset()
	if self.Mode == "Animator" then
		self.Released = false
		self:Release()
	else
		for key in self.Last do
			local instance = self.Joints[key].Instance
			if instance.Parent then
				instance.Transform = IDENTITY
			end
		end
	end
	table.clear(self.Last)
	table.clear(self.Frame)
	table.clear(self.FrameBase)
	table.clear(self.Bases)
	self.Building = false
	self.Released = true
end

function Rig:_world(joint, pose, pivot)
	local parent
	if joint.Parent then
		parent = self:_world(self.Joints[joint.Parent], pose, pivot)
	elseif pivot then
		parent = pivot * self.Model:GetPivot():ToObjectSpace(joint.Base.CFrame)
	else
		parent = joint.Base.CFrame
	end
	local transform
	if pose then
		transform = self:PoseToTransform(pose[joint.Key] or IDENTITY)
	else
		transform = self:Transform(joint.Key)
	end
	if joint.Kind == "Bone" then
		return parent * joint.Rest * transform
	end
	return parent * joint.C0 * transform * joint.C1Inverse
end

function Rig:WorldCFrame(nameOrKey, pose, pivot)
	local joint = self:Find(nameOrKey)
	if joint then
		return self:_world(joint, pose, pivot)
	end
	local found = self.Model:FindFirstChild(nameOrKey, true)
	if not found then
		return nil
	end
	local cframe
	if found:IsA("BasePart") then
		cframe = found.CFrame
	elseif found:IsA("Attachment") then
		cframe = found.WorldCFrame
	else
		return nil
	end
	if pivot then
		return pivot * self.Model:GetPivot():ToObjectSpace(cframe)
	end
	return cframe
end

function Rig:JointFrame(key)
	local joint = self.Joints[key]
	local world = self:_world(joint)
	if joint.Kind == "Bone" then
		return world
	end
	return world * joint.C1
end

function Rig:ReferenceFrame(key)
	local joint = key and self.Joints[key]
	if not joint then
		return self.Model:GetPivot()
	end
	return self:_world(joint) * joint.RestChar:Inverse()
end

function Rig:RestChar(key)
	local joint = self.Joints[key]
	return joint and joint.RestChar
end

return Rig
