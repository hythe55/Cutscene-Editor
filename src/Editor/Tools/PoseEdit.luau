local PoseMath = require(script.Parent.PoseMath)

local PoseEdit = {}

local function round(value)
	return math.round(value * 10000) / 10000
end

local function keyframeAt(document, info, clipTime)
	local sequence = document:EnsureSequence(info.Clip)
	local existing = PoseMath.KeyframeAt(info, clipTime)
	if existing and existing.Parent == sequence then
		return existing, false
	end
	local keyframe = Instance.new("Keyframe")
	keyframe.Time = round(math.max(clipTime, 0))
	keyframe.Parent = sequence
	return keyframe, true
end

local function write(document, info, keyframe, jointKey, cframe)
	local existing = PoseMath.PoseOf(keyframe, jointKey)
	local weighted = existing ~= nil and existing.Weight > 0
	local pose = document:WritePose(info.Clip, keyframe, jointKey, cframe)
	if not weighted then
		pose.EasingStyle, pose.EasingDirection = PoseMath.InsertEasing(info, jointKey, keyframe.Time)
	end
	return pose
end

function PoseEdit.HoldTimes(info, editedTime)
	local times = {}
	local keyframes = info.Keyframes
	local first, last = keyframes[1], keyframes[#keyframes]
	for _, keyframe in { first, last } do
		if keyframe and math.abs(keyframe.Time - editedTime) > PoseMath.Tolerance and not table.find(times, keyframe.Time) then
			table.insert(times, keyframe.Time)
		end
	end
	return times
end

function PoseEdit.Chain(sequence, keyframe, jointKey)
	local root = keyframe:FindFirstChildOfClass("Pose")
	if not root then
		root = Instance.new("Pose")
		root.Name = "HumanoidRootPart"
		for _, other in sequence:GetKeyframes() do
			local found = other:FindFirstChildOfClass("Pose")
			if found then
				root.Name = found.Name
				break
			end
		end
		root.Weight = 0
		root.Parent = keyframe
	end
	local current = root
	for _, segment in string.split(jointKey, "/") do
		local child = current:FindFirstChild(segment)
		if not (child and child:IsA("Pose")) then
			child = Instance.new("Pose")
			child.Name = segment
			child.Weight = 0
			child.Parent = current
		end
		current = child
	end
	local weighted = current.Weight > 0
	current.Weight = 1
	return current, weighted
end

function PoseEdit.SetJoint(document, info, clipTime, jointKey, cframe, hold)
	local keyframe = PoseMath.KeyframeAt(info, clipTime)
	local pose = keyframe and PoseMath.PoseOf(keyframe, jointKey)
	if pose and pose.Weight > 0 and not hold then
		local result = document:SetPose(info.Clip, keyframe, jointKey, cframe)
		return result and keyframe, result
	end
	return document:Batch(if keyframe then "Edit pose" else "Key joint", function(doc)
		local target = keyframeAt(doc, info, clipTime)
		local written = write(doc, info, target, jointKey, cframe)
		if hold then
			for _, time in PoseEdit.HoldTimes(info, target.Time) do
				local holdFrame = keyframeAt(doc, info, time)
				if not PoseMath.PoseOf(holdFrame, jointKey) or PoseMath.PoseOf(holdFrame, jointKey).Weight <= 0 then
					write(doc, info, holdFrame, jointKey, hold)
				end
			end
		end
		return target, written
	end)
end

function PoseEdit.SetPoses(document, info, clipTime, poses, name)
	if next(poses) == nil then
		return nil
	end
	return document:Batch(name or "Key pose", function(doc)
		local target = keyframeAt(doc, info, clipTime)
		for jointKey, cframe in poses do
			write(doc, info, target, jointKey, cframe)
		end
		return target
	end)
end

function PoseEdit.ResetJoint(document, info, clipTime, jointKey)
	local keyframe = PoseMath.KeyframeAt(info, clipTime)
	if keyframe then
		local result = document:ResetPose(info.Clip, keyframe, jointKey)
		return result and keyframe
	end
	return PoseEdit.SetJoint(document, info, clipTime, jointKey, CFrame.identity)
end

function PoseEdit.DeleteKeyframe(document, keyframe)
	return document:DeleteKeyframe(keyframe)
end

function PoseEdit.SetRoles(document, info, keyframe, jointKeys, role)
	return document:Batch("Set key role", function(doc)
		doc:Touch(info.Sequence)
		local count = 0
		for _, jointKey in jointKeys do
			local pose = PoseMath.PoseOf(keyframe, jointKey)
			if pose and pose.Weight > 0 then
				local chosen = if role == "Auto" then PoseMath.Classify(info, jointKey, keyframe) else role
				if chosen then
					local style, direction = PoseMath.RoleEasing(chosen, pose)
					if pose.EasingStyle ~= style or pose.EasingDirection ~= direction then
						pose.EasingStyle = style
						pose.EasingDirection = direction
						count += 1
					end
				end
			end
		end
		return count
	end)
end

function PoseEdit.SetSmooth(document, info, enabled)
	if not info.Sequence then
		return nil
	end
	return document:SetAttribute(info.Sequence, "Interpolation", if enabled then "Smooth" else nil)
end

return PoseEdit
