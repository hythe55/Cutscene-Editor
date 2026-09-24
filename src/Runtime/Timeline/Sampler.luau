local Smooth = require(script.Parent.Smooth)
local Bake = require(script.Parent.Bake)

local Sampler = {}
Sampler.__index = Sampler

local IDENTITY = CFrame.identity

local Style = Enum.PoseEasingStyle
local Direction = Enum.PoseEasingDirection
local LINEAR, CONSTANT, CUBIC, CUBICV2 = Style.Linear, Style.Constant, Style.Cubic, Style.CubicV2
local ELASTIC, BOUNCE = Style.Elastic, Style.Bounce
local IN, OUT = Direction.In, Direction.Out
local TAU = math.pi * 2

local function bounceOut(a)
	if a < 1 / 2.75 then
		return 7.5625 * a * a
	elseif a < 2 / 2.75 then
		a -= 1.5 / 2.75
		return 7.5625 * a * a + 0.75
	elseif a < 2.5 / 2.75 then
		a -= 2.25 / 2.75
		return 7.5625 * a * a + 0.9375
	end
	a -= 2.625 / 2.75
	return 7.5625 * a * a + 0.984375
end

local function bounceIn(a)
	return 1 - bounceOut(1 - a)
end

local function ease(style, direction, a)
	if style == LINEAR then
		return a
	elseif style == CONSTANT then
		if direction == IN then
			return 1
		elseif direction == OUT then
			return 0
		end
		return if a < 0.5 then 0 else 1
	elseif style == CUBICV2 or style == CUBIC then
		if style == CUBIC then
			direction = if direction == IN then OUT elseif direction == OUT then IN else direction
		end
		if direction == IN then
			return a * a * a
		elseif direction == OUT then
			return 1 - (1 - a) ^ 3
		end
		return if a < 0.5 then 4 * a * a * a else 1 - (-2 * a + 2) ^ 3 / 2
	elseif style == BOUNCE then
		if direction == IN then
			return bounceIn(a)
		elseif direction == OUT then
			return bounceOut(a)
		end
		return if a < 0.5 then bounceIn(2 * a) / 2 else 0.5 + bounceIn(2 * a - 1) / 2
	elseif style == ELASTIC then
		if direction == IN then
			return -2 ^ (10 * (a - 1)) * math.sin((a - 1.075) * TAU / 0.3)
		elseif direction == OUT then
			return 2 ^ (-10 * a) * math.sin((a - 0.075) * TAU / 0.3) + 1
		end
		local b = 2 * a - 1
		if b < 0 then
			return -0.5 * 2 ^ (10 * b) * math.sin((b - 0.1125) * TAU / 0.45)
		end
		return 0.5 * 2 ^ (-10 * b) * math.sin((b - 0.1125) * TAU / 0.45) + 1
	end
	return a
end

Sampler.Ease = ease

local function quaternion(cframe)
	local axis, angle = cframe:ToAxisAngle()
	if angle ~= angle or axis ~= axis then
		return 0, 0, 0, 1
	end
	local s = math.sin(angle / 2)
	return axis.X * s, axis.Y * s, axis.Z * s, math.cos(angle / 2)
end

local function logarithm(x, y, z, w)
	local s = math.sqrt(x * x + y * y + z * z)
	if s < 1e-12 then
		return Vector3.zero
	end
	return Vector3.new(x, y, z) * (2 * math.atan2(s, w) / s)
end

local function buildSegment(k0, k1)
	local c0, c1 = k0.CFrame, k1.CFrame
	local segment = {
		Style = k0.Style,
		Direction = k0.Direction,
		P0 = c0.Position,
		Delta = c1.Position - c0.Position,
	}
	if k0.Style == CONSTANT then
		return segment
	end
	local ax, ay, az, aw = quaternion(c0)
	local bx, by, bz, bw = quaternion(c1)
	if k0.Style == LINEAR and k1.Style == LINEAR and k0.Adjacent then
		if ax * bx + ay * by + az * bz + aw * bw < 0 then
			bx, by, bz, bw = -bx, -by, -bz, -bw
		end
		segment.Q0 = { ax, ay, az, aw }
		segment.Q1 = { bx - ax, by - ay, bz - az, bw - aw }
	else
		local starts = { logarithm(ax, ay, az, aw), logarithm(-ax, -ay, -az, -aw) }
		local ends = { logarithm(bx, by, bz, bw), logarithm(-bx, -by, -bz, -bw) }
		local best = math.huge
		for _, v0 in starts do
			for _, v1 in ends do
				local distance = (v1 - v0).Magnitude
				if distance < best then
					best = distance
					segment.V0 = v0
					segment.DV = v1 - v0
				end
			end
		end
	end
	return segment
end

local function evaluateSegment(segment, k0, k1, a)
	if a <= 0 then
		return k0.CFrame
	end
	if segment.Smooth then
		return Smooth.Evaluate(segment, a)
	end
	local f = ease(segment.Style, segment.Direction, a)
	if segment.Style == CONSTANT then
		return if f >= 1 then k1.CFrame else k0.CFrame
	end
	local p = segment.P0 + segment.Delta * f
	local q0 = segment.Q0
	if q0 then
		local d = segment.Q1
		local x, y, z, w = q0[1] + d[1] * f, q0[2] + d[2] * f, q0[3] + d[3] * f, q0[4] + d[4] * f
		local length = math.sqrt(x * x + y * y + z * z + w * w)
		return CFrame.new(p.X, p.Y, p.Z, x / length, y / length, z / length, w / length)
	end
	local v = segment.V0 + segment.DV * f
	local angle = v.Magnitude
	if angle < 1e-12 then
		return CFrame.new(p)
	end
	return CFrame.fromAxisAngle(v / angle, angle) + p
end

local function collect(pose, prefix, time, order, tracks, weighted, roots)
	for _, child in pose:GetChildren() do
		if child:IsA("Pose") then
			local key = if prefix then prefix .. "/" .. child.Name else child.Name
			if not prefix then
				roots[key] = roots[key] or {}
				roots[key][pose.Name] = true
			end
			local list = tracks[key]
			if not list then
				list = {}
				tracks[key] = list
			end
			table.insert(list, {
				Time = time,
				Order = order,
				Weighted = child.Weight > 0,
				CFrame = child.CFrame,
				Style = child.EasingStyle,
				Direction = child.EasingDirection,
			})
			if child.Weight > 0 then
				weighted[key] = true
			end
			collect(child, key, time, order, tracks, weighted, roots)
		end
	end
end

local function compile(all)
	table.sort(all, function(a, b)
		if a.Time == b.Time then
			return a.Order < b.Order
		end
		return a.Time < b.Time
	end)
	local list = {}
	for i = 1, #all do
		local entry = all[i]
		if entry.Weighted then
			local following = all[i + 1]
			entry.Adjacent = following ~= nil and following.Weighted
			table.insert(list, entry)
		end
	end
	local track = { Keys = list, Times = {}, Segments = {}, Cursor = 1, Count = #list }
	for i, key in list do
		track.Times[i] = key.Time
		if i < #list then
			track.Segments[i] = buildSegment(key, list[i + 1])
		end
	end
	return track
end

local function locate(track, t)
	local times = track.Times
	local i = track.Cursor
	if i >= track.Count or times[i] > t then
		local low, high = 1, track.Count
		while high - low > 1 do
			local middle = (low + high) // 2
			if times[middle] <= t then
				low = middle
			else
				high = middle
			end
		end
		i = low
	end
	while i < track.Count - 1 and times[i + 1] <= t do
		i += 1
	end
	track.Cursor = i
	return i
end

local function evaluate(track, t)
	local times = track.Times
	local count = track.Count
	if t < times[1] then
		return IDENTITY
	elseif t >= times[count] then
		return track.Keys[count].CFrame
	end
	local i = locate(track, t)
	local t0, t1 = times[i], times[i + 1]
	local span = t1 - t0
	if span <= 0 then
		return track.Keys[i + 1].CFrame
	end
	return evaluateSegment(track.Segments[i], track.Keys[i], track.Keys[i + 1], (t - t0) / span)
end

function Sampler.new(keyframeSequence)
	local self = setmetatable({}, Sampler)
	self.Sequence = keyframeSequence
	self.Loop = keyframeSequence.Loop
	self.Priority = keyframeSequence.Priority
	self.Keys = {}
	self.Tracks = {}
	self.Roots = {}
	self.Skips = setmetatable({}, { __mode = "k" })
	local raw, weighted = {}, {}
	local length = 0
	for order, keyframe in keyframeSequence:GetChildren() do
		if keyframe:IsA("Keyframe") then
			length = math.max(length, keyframe.Time)
			for _, root in keyframe:GetChildren() do
				if root:IsA("Pose") then
					collect(root, nil, keyframe.Time, order, raw, weighted, self.Roots)
				end
			end
		end
	end
	self.Smooth = keyframeSequence:GetAttribute("Interpolation") == "Smooth"
	for key in weighted do
		table.insert(self.Keys, key)
		local track = compile(raw[key])
		if self.Smooth then
			Smooth.Prepare(track, self.Loop, length, ease)
		end
		self.Tracks[key] = track
	end
	table.sort(self.Keys)
	self.Length = length
	return self
end

function Sampler:Sample(time, fn, skip)
	local tracks = self.Tracks
	for _, key in self.Keys do
		if not (skip and skip[key]) then
			fn(key, evaluate(tracks[key], time))
		end
	end
end

function Sampler:Skip(rig)
	local skip = self.Skips[rig]
	if skip == nil then
		skip = {}
		local rootName = rig.Root and rig.Root.Name
		for key, names in self.Roots do
			if rootName and not names[rootName] then
				skip[key] = true
			end
		end
		self.Skips[rig] = skip
	end
	return skip
end

function Sampler:SampleKey(key, time)
	local track = self.Tracks[key]
	return track and evaluate(track, time)
end

function Sampler:Has(key)
	return self.Tracks[key] ~= nil
end

local function mul32(a, b)
	local lo = bit32.band(a, 0xFFFF)
	local hi = bit32.rshift(a, 16)
	return bit32.band(lo * b + bit32.lshift(bit32.band(hi * b, 0xFFFF), 16), 0xFFFFFFFF)
end

local function hasher()
	local h1, h2 = 0x811C9DC5, 0x2545F491
	local state = {}
	function state.Int(value)
		value = value % 4294967296
		h1 = mul32(bit32.bxor(h1, value), 16777619)
		h2 = mul32(bit32.bxor(h2, bit32.lrotate(value, 13)), 0x5BD1E995)
		h2 = bit32.bxor(h2, bit32.rshift(h2, 15))
	end
	function state.Number(value)
		state.Int(math.floor(value * 10000 + 0.5))
	end
	function state.String(text)
		state.Int(#text)
		for i = 1, #text do
			state.Int(string.byte(text, i))
		end
	end
	function state.Result()
		return string.format("%08x%08x", h1, h2)
	end
	return state
end

local function sortedPoses(parent)
	local poses = {}
	for _, child in parent:GetChildren() do
		if child:IsA("Pose") then
			table.insert(poses, child)
		end
	end
	table.sort(poses, function(a, b)
		return a.Name < b.Name
	end)
	return poses
end

local function hashPose(h, pose, depth)
	h.String(pose.Name)
	h.Int(depth)
	h.Number(pose.Weight)
	h.Int(pose.EasingStyle.Value)
	h.Int(pose.EasingDirection.Value)
	for _, component in { pose.CFrame:GetComponents() } do
		h.Number(component)
	end
	for _, child in sortedPoses(pose) do
		hashPose(h, child, depth + 1)
	end
end

function Sampler.Hash(keyframeSequence)
	local h = hasher()
	h.Int(if keyframeSequence.Loop then 1 else 0)
	h.Int(keyframeSequence.Priority.Value)
	local interpolation = keyframeSequence:GetAttribute("Interpolation")
	if interpolation ~= nil then
		h.String("Interpolation")
		h.String(tostring(interpolation))
	end
	local keyframes = {}
	for _, keyframe in keyframeSequence:GetChildren() do
		if keyframe:IsA("Keyframe") then
			table.insert(keyframes, keyframe)
		end
	end
	table.sort(keyframes, function(a, b)
		return a.Time < b.Time
	end)
	for _, keyframe in keyframes do
		h.Number(keyframe.Time)
		for _, root in sortedPoses(keyframe) do
			for _, child in sortedPoses(root) do
				hashPose(h, child, 1)
			end
		end
	end
	return h.Result()
end

function Sampler.Bake(keyframeSequence, fps)
	return Bake.Run(Sampler.new(keyframeSequence), fps)
end

return Sampler
