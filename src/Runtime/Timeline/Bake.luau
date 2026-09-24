local Smooth = require(script.Parent.Smooth)

local Bake = {}

local LINEAR = Enum.PoseEasingStyle.Linear
local IN = Enum.PoseEasingDirection.In
local TIME_EPSILON = 1e-4
local ANGLE_TOLERANCE = math.rad(0.05)
local POSITION_TOLERANCE = 1e-4
local MAX_DEPTH = 4

local function locate(track, t)
	local times, count = track.Times, track.Count
	if t < times[1] - TIME_EPSILON or t > times[count] + TIME_EPSILON then
		return nil
	end
	local low, high = 1, count
	while low < high do
		local middle = (low + high + 1) // 2
		if times[middle] <= t + TIME_EPSILON then
			low = middle
		else
			high = middle - 1
		end
	end
	if math.abs(times[low] - t) <= TIME_EPSILON then
		return "Key", low
	end
	local segment = track.Segments[low]
	return if segment and segment.Smooth then "Smooth" else "Native", low
end

local function deviates(a, b, expected)
	local middle = a:Lerp(b, 0.5)
	if Smooth.Angle(middle, expected) > ANGLE_TOLERANCE then
		return true
	end
	return (middle.Position - expected.Position).Magnitude > POSITION_TOLERANCE
end

local function needsSplit(sampler, t0, t1)
	local middle = (t0 + t1) / 2
	for key, track in sampler.Tracks do
		if locate(track, middle) == "Smooth" then
			if deviates(sampler:SampleKey(key, t0), sampler:SampleKey(key, t1), sampler:SampleKey(key, middle)) then
				return true
			end
		end
	end
	return false
end

local function collectTimes(sampler, fps)
	local originals = {}
	for _, keyframe in sampler.Sequence:GetKeyframes() do
		table.insert(originals, keyframe.Time)
	end
	table.insert(originals, sampler.Length)
	table.sort(originals)
	local base = {}
	for _, t in originals do
		if #base == 0 or t - base[#base] > TIME_EPSILON then
			table.insert(base, t)
		end
	end
	local gap = 0.2 / fps
	for frame = 0, math.floor(sampler.Length * fps + 1e-6) do
		local t = frame / fps
		local near = false
		for _, original in originals do
			if math.abs(original - t) < gap then
				near = true
				break
			end
		end
		if not near then
			table.insert(base, t)
		end
	end
	table.sort(base)
	local times = {}
	local function subdivide(t0, t1, depth)
		if depth < MAX_DEPTH and needsSplit(sampler, t0, t1) then
			local middle = (t0 + t1) / 2
			subdivide(t0, middle, depth + 1)
			table.insert(times, middle)
			subdivide(middle, t1, depth + 1)
		end
	end
	for index = 1, #base - 1 do
		table.insert(times, base[index])
		subdivide(base[index], base[index + 1], 0)
	end
	table.insert(times, base[#base])
	return times
end

local function rootNames(sampler)
	local roots = {}
	for key, names in sampler.Roots do
		local list = {}
		for name in names do
			table.insert(list, name)
		end
		table.sort(list)
		roots[key] = list[1]
	end
	return roots
end

function Bake.Run(sampler, fps)
	fps = fps or 30
	local source = sampler.Sequence
	local result = Instance.new("KeyframeSequence")
	result.Name = source.Name
	result.Loop = source.Loop
	result.Priority = source.Priority
	result.AuthoredHipHeight = source.AuthoredHipHeight
	for name, value in source:GetAttributes() do
		if name ~= "Interpolation" then
			result:SetAttribute(name, value)
		end
	end
	if #sampler.Keys == 0 and #source:GetKeyframes() == 0 then
		return result
	end
	local roots = rootNames(sampler)
	local byTime = {}
	for _, t in collectTimes(sampler, fps) do
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = t
		local rootPoses, poses = {}, {}
		local function ensure(key)
			local pose = poses[key]
			if pose then
				return pose
			end
			local parentKey, name = string.match(key, "^(.*)/([^/]+)$")
			local parent
			if parentKey then
				parent = ensure(parentKey)
			else
				name = key
				local rootName = roots[key] or "HumanoidRootPart"
				parent = rootPoses[rootName]
				if not parent then
					parent = Instance.new("Pose")
					parent.Name = rootName
					parent.Weight = 0
					parent.Parent = keyframe
					rootPoses[rootName] = parent
				end
			end
			pose = Instance.new("Pose")
			pose.Name = name
			pose.Weight = 0
			pose.EasingStyle = LINEAR
			pose.EasingDirection = IN
			pose.Parent = parent
			poses[key] = pose
			return pose
		end
		for _, key in sampler.Keys do
			local track = sampler.Tracks[key]
			local kind, index = locate(track, t)
			if kind == "Key" then
				local entry = track.Keys[index]
				local segment = track.Segments[index]
				local pose = ensure(key)
				pose.Weight = 1
				pose.CFrame = entry.CFrame
				if segment and not segment.Smooth then
					pose.EasingStyle = segment.Style
					pose.EasingDirection = segment.Direction
				end
			elseif kind == "Smooth" then
				local pose = ensure(key)
				pose.Weight = 1
				pose.CFrame = sampler:SampleKey(key, t)
			end
		end
		keyframe.Parent = result
		byTime[keyframe] = t
	end
	local keyframes = result:GetKeyframes()
	for _, original in source:GetKeyframes() do
		for _, keyframe in keyframes do
			if math.abs(byTime[keyframe] - original.Time) <= TIME_EPSILON then
				keyframe.Name = original.Name
				for _, child in original:GetChildren() do
					if child:IsA("KeyframeMarker") then
						child:Clone().Parent = keyframe
					end
				end
				break
			end
		end
	end
	return result
end

return Bake
