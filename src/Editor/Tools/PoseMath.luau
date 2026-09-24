local PoseMath = {}

PoseMath.Tolerance = 1 / 60

local Style = Enum.PoseEasingStyle
local Direction = Enum.PoseEasingDirection

local ROTATION_MIN, POSITION_MIN, CONTINUE_COS = math.rad(0.5), 1e-3, 0.3

function PoseMath.Info(document, clip)
	local props = document:Read(clip, "Animation")
	local sequence = clip:FindFirstChild("Keyframes")
	if not (sequence and sequence:IsA("KeyframeSequence")) then
		sequence = clip:FindFirstChildOfClass("KeyframeSequence")
	end
	local keyframes = {}
	if sequence then
		keyframes = sequence:GetKeyframes()
		table.sort(keyframes, function(a, b)
			return a.Time < b.Time
		end)
	end
	local length = 0
	for _, keyframe in keyframes do
		length = math.max(length, keyframe.Time)
	end
	return {
		Clip = clip,
		Props = props,
		Sequence = sequence,
		Keyframes = keyframes,
		Length = length,
		Actor = clip.Parent and clip.Parent:GetAttribute("Actor"),
		Smooth = sequence ~= nil and sequence:GetAttribute("Interpolation") == "Smooth",
	}
end

function PoseMath.Inside(info, t)
	local props = info.Props
	return t >= props.Start - 1e-4 and t <= props.Start + props.Duration + 1e-4
end

function PoseMath.ClipTime(info, t)
	if not PoseMath.Inside(info, t) then
		return nil
	end
	local props = info.Props
	local time = props.ClipOffset + (math.clamp(t, props.Start, props.Start + props.Duration) - props.Start) * props.Speed
	if props.Loop and info.Length > 0 then
		time %= info.Length
	end
	return time
end

function PoseMath.CutsceneTime(info, clipTime, near)
	local props = info.Props
	local speed = math.max(props.Speed, 1e-3)
	local first = props.Start + (clipTime - props.ClipOffset) / speed
	local last = props.Start + props.Duration
	local function inside(t)
		return t >= props.Start - 1e-4 and t <= last + 1e-4
	end
	if not props.Loop or info.Length <= 0 then
		return if inside(first) then math.clamp(first, props.Start, last) else nil
	end
	local period = info.Length / speed
	near = near or props.Start
	local best = nil
	local center = math.floor((near - first) / period + 0.5)
	for k = center - 1, center + 1 do
		local candidate = first + k * period
		if inside(candidate) and (not best or math.abs(candidate - near) < math.abs(best - near)) then
			best = candidate
		end
	end
	if not best then
		local candidate = first + math.ceil((props.Start - first) / period - 1e-6) * period
		if inside(candidate) then
			best = candidate
		end
	end
	return best and math.clamp(best, props.Start, last)
end

function PoseMath.VisibleRange(info)
	local props = info.Props
	if props.Loop then
		return 0, info.Length
	end
	return props.ClipOffset, props.ClipOffset + props.Duration * props.Speed
end

function PoseMath.KeyframeAt(info, clipTime)
	if not clipTime then
		return nil
	end
	local best, distance = nil, PoseMath.Tolerance
	for _, keyframe in info.Keyframes do
		local gap = math.abs(keyframe.Time - clipTime)
		if gap <= distance then
			best, distance = keyframe, gap
		end
	end
	return best
end

function PoseMath.Neighbour(info, clipTime, direction)
	local chosen = nil
	for _, keyframe in info.Keyframes do
		if direction > 0 and keyframe.Time > clipTime + PoseMath.Tolerance then
			return keyframe
		elseif direction < 0 and keyframe.Time < clipTime - PoseMath.Tolerance then
			chosen = keyframe
		end
	end
	return chosen
end

function PoseMath.PoseOf(keyframe, jointKey)
	local current = keyframe and keyframe:FindFirstChildOfClass("Pose")
	if not current then
		return nil
	end
	for _, segment in string.split(jointKey, "/") do
		local child = current:FindFirstChild(segment)
		if not (child and child:IsA("Pose")) then
			return nil
		end
		current = child
	end
	return current
end

function PoseMath.Weighted(keyframe)
	local list = {}
	local function walk(pose, prefix)
		for _, child in pose:GetChildren() do
			if child:IsA("Pose") then
				local key = if prefix then prefix .. "/" .. child.Name else child.Name
				if child.Weight > 0 then
					list[key] = child
				end
				walk(child, key)
			end
		end
	end
	for _, root in keyframe:GetChildren() do
		if root:IsA("Pose") then
			walk(root, nil)
		end
	end
	return list
end

function PoseMath.Keyed(info)
	local keyed = {}
	for _, keyframe in info.Keyframes do
		for key in PoseMath.Weighted(keyframe) do
			keyed[key] = true
		end
	end
	return keyed
end

function PoseMath.Rotate(cframe, axis, angle)
	return cframe * CFrame.fromAxisAngle(if typeof(axis) == "Vector3" then axis else Vector3.FromAxis(axis), angle)
end

function PoseMath.Translate(cframe, localOffset, scale)
	return cframe + cframe:VectorToWorldSpace(localOffset) / math.max(scale or 1, 1e-6)
end

function PoseMath.Role(pose)
	local style, direction = pose.EasingStyle, pose.EasingDirection
	if style == Style.Linear then
		return "Pass"
	elseif style == Style.Cubic or (style == Style.CubicV2 and direction == Direction.InOut) then
		return "Stop"
	end
	return "Snap"
end

function PoseMath.RoleEasing(role, pose)
	if role == "Pass" then
		return Style.Linear, Direction.InOut
	elseif role == "Stop" then
		return Style.CubicV2, Direction.InOut
	end
	if pose and PoseMath.Role(pose) == "Snap" then
		return pose.EasingStyle, pose.EasingDirection
	end
	return Style.CubicV2, Direction.Out
end

function PoseMath.KeyframeRole(keyframe)
	local counts = { Pass = 0, Stop = 0, Snap = 0 }
	for _, pose in PoseMath.Weighted(keyframe) do
		local role = PoseMath.Role(pose)
		counts[role] += 1
	end
	local best, count = "Stop", -1
	for _, role in { "Stop", "Pass", "Snap" } do
		if counts[role] > count then
			best, count = role, counts[role]
		end
	end
	return best, counts
end

local function rotationVector(a, b)
	local axis, angle = (a.Rotation:Inverse() * b.Rotation):ToAxisAngle()
	if angle ~= angle or axis ~= axis then
		return Vector3.zero
	end
	if angle > math.pi then
		angle -= 2 * math.pi
	end
	return axis * angle
end

local function channel(before, after, minimum)
	local a, b = before.Magnitude, after.Magnitude
	if a < minimum and b < minimum then
		return "Idle"
	elseif a < minimum or b < minimum then
		return "Break"
	end
	return if before:Dot(after) / (a * b) > CONTINUE_COS then "Continue" else "Break"
end

function PoseMath.Classify(info, jointKey, keyframe)
	local list = {}
	for _, candidate in info.Keyframes do
		local pose = PoseMath.PoseOf(candidate, jointKey)
		if pose and pose.Weight > 0 then
			table.insert(list, { Keyframe = candidate, Pose = pose })
		end
	end
	local index = nil
	for i, entry in list do
		if entry.Keyframe == keyframe then
			index = i
		end
	end
	if not index then
		return nil
	end
	local current = list[index].Pose
	if PoseMath.Role(current) == "Snap" then
		return "Snap"
	end
	if index == 1 or index == #list then
		return "Stop"
	end
	local a, b, c = list[index - 1].Pose.CFrame, current.CFrame, list[index + 1].Pose.CFrame
	local rotation = channel(rotationVector(a, b), rotationVector(b, c), ROTATION_MIN)
	local position = channel(b.Position - a.Position, c.Position - b.Position, POSITION_MIN)
	local pass = rotation ~= "Break" and position ~= "Break" and (rotation == "Continue" or position == "Continue")
	return if pass then "Pass" else "Stop"
end

function PoseMath.InsertEasing(info, jointKey, clipTime)
	if info.Smooth then
		return Style.Linear, Direction.InOut
	end
	local before, after = nil, nil
	for _, keyframe in info.Keyframes do
		local pose = PoseMath.PoseOf(keyframe, jointKey)
		if pose and pose.Weight > 0 then
			if keyframe.Time < clipTime then
				before = pose
			elseif not after then
				after = pose
			end
		end
	end
	local source = before or after
	if source then
		return source.EasingStyle, source.EasingDirection
	end
	return Style.CubicV2, Direction.InOut
end

function PoseMath.Sampler(deps, info)
	return info.Sequence and deps.Sampler.new(info.Sequence)
end

function PoseMath.SampleAll(deps, info, clipTime)
	local pose = {}
	local sampler = PoseMath.Sampler(deps, info)
	if sampler then
		sampler:Sample(clipTime, function(key, cframe)
			pose[key] = cframe
		end)
	end
	return pose
end

return PoseMath
