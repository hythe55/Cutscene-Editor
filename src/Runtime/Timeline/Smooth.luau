local Smooth = {}

local Style = Enum.PoseEasingStyle
local LINEAR, CONSTANT, CUBIC, CUBICV2 = Style.Linear, Style.Constant, Style.Cubic, Style.CubicV2
local INOUT = Enum.PoseEasingDirection.InOut

local ROTATION_EPSILON = 1e-4
local POSITION_EPSILON = 1e-5
local SAME_ANGLE = 1e-3
local SAME_POSITION = 1e-4
local TIME_EPSILON = 1e-4
local SLOPE_EPSILON = 1e-6
local SLOPE_STEP = 1e-5
local LIMIT = 3

local function isStop(key)
	return key.Style == CUBIC or (key.Style == CUBICV2 and key.Direction == INOUT)
end

local function isNative(key)
	return key.Style ~= LINEAR and not isStop(key)
end

local function quaternion(cframe)
	local _, _, _, m00, m01, m02, m10, m11, m12, m20, m21, m22 = cframe:GetComponents()
	local x, y, z, w
	local trace = m00 + m11 + m22
	if trace > 0 then
		local s = 0.5 / math.sqrt(trace + 1)
		x, y, z, w = (m21 - m12) * s, (m02 - m20) * s, (m10 - m01) * s, 0.25 / s
	elseif m00 > m11 and m00 > m22 then
		local s = 2 * math.sqrt(1 + m00 - m11 - m22)
		x, y, z, w = 0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s
	elseif m11 > m22 then
		local s = 2 * math.sqrt(1 + m11 - m00 - m22)
		x, y, z, w = (m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s
	else
		local s = 2 * math.sqrt(1 + m22 - m00 - m11)
		x, y, z, w = (m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s
	end
	local l = math.sqrt(x * x + y * y + z * z + w * w)
	return { x / l, y / l, z / l, w / l }
end

local function rotationVector(a, b)
	local ax, ay, az, aw = a[1], a[2], a[3], a[4]
	local bx, by, bz, bw = b[1], b[2], b[3], b[4]
	local x = aw * bx - ax * bw - ay * bz + az * by
	local y = aw * by - ay * bw - az * bx + ax * bz
	local z = aw * bz - az * bw - ax * by + ay * bx
	local w = aw * bw + ax * bx + ay * by + az * bz
	if w < 0 then
		x, y, z, w = -x, -y, -z, -w
	end
	local s = math.sqrt(x * x + y * y + z * z)
	if s < 1e-12 then
		return Vector3.zero
	end
	return Vector3.new(x, y, z) * (2 * math.atan2(s, w) / s)
end

function Smooth.Angle(a, b)
	return rotationVector(quaternion(a), quaternion(b)).Magnitude
end

local function same(a, b)
	return rotationVector(a.Q, b.Q).Magnitude < SAME_ANGLE and (a.CFrame.Position - b.CFrame.Position).Magnitude < SAME_POSITION
end

local function limit(tangent, before, after, hBefore, hAfter, epsilon)
	local sBefore, sAfter = before.Magnitude, after.Magnitude
	if sBefore < epsilon or sAfter < epsilon then
		return Vector3.zero
	end
	local uBefore, uAfter = before / sBefore, after / sAfter
	local c = tangent:Dot(uBefore)
	if c < 0 then
		tangent -= uBefore * c
	end
	c = tangent:Dot(uAfter)
	if c < 0 then
		tangent -= uAfter * c
	end
	local speed = tangent.Magnitude
	if tangent:Dot(uBefore) < -1e-9 * speed then
		return Vector3.zero
	end
	local bound = LIMIT * math.min(sBefore / hBefore, sAfter / hAfter)
	if speed > bound then
		tangent *= bound / speed
	end
	return tangent
end

local function tangents(previous, current, following, hBefore, hAfter)
	local span = hBefore + hAfter
	local rBefore = rotationVector(previous.Q, current.Q)
	local rAfter = rotationVector(current.Q, following.Q)
	local pBefore = current.CFrame.Position - previous.CFrame.Position
	local pAfter = following.CFrame.Position - current.CFrame.Position
	return limit((rBefore + rAfter) / span, rBefore, rAfter, hBefore, hAfter, ROTATION_EPSILON),
		limit((pBefore + pAfter) / span, pBefore, pAfter, hBefore, hAfter, POSITION_EPSILON)
end

local function slope(ease, style, direction, a)
	local d = SLOPE_STEP
	if a == 0 then
		return (4 * ease(style, direction, d) - 3 * ease(style, direction, 0) - ease(style, direction, 2 * d)) / (2 * d)
	end
	return (3 * ease(style, direction, 1) - 4 * ease(style, direction, 1 - d) + ease(style, direction, 1 - 2 * d)) / (2 * d)
end

local function nativeVelocity(segment, h, a, ease)
	if segment.Style == CONSTANT or not segment.V0 or h <= 0 then
		return Vector3.zero, Vector3.zero
	end
	local rate = slope(ease, segment.Style, segment.Direction, a)
	if math.abs(rate) < SLOPE_EPSILON then
		return Vector3.zero, Vector3.zero
	end
	rate /= h
	local d = segment.DV
	local v = segment.V0 + d * a
	local angle = v.Magnitude
	local turn = d
	if angle > 1e-6 then
		local c = v:Cross(d)
		turn = d - c * ((1 - math.cos(angle)) / (angle * angle)) + v:Cross(c) * ((angle - math.sin(angle)) / (angle * angle * angle))
	end
	return turn * rate, segment.Delta * rate
end

local function junction(velocity, chord, h, epsilon)
	local s = chord.Magnitude
	if s < epsilon or velocity:Dot(chord) <= 0 then
		return Vector3.zero
	end
	local bound = LIMIT * s / h
	local speed = velocity.Magnitude
	if speed > bound then
		return velocity * (bound / speed)
	end
	return velocity
end

local function build(k0, k1, w0, w1, v0, v1, h)
	local p0, p1 = k0.CFrame.Position, k1.CFrame.Position
	local a, b = v0 * h, v1 * h
	local ax, ay, az, aw = k0.Q[1], k0.Q[2], k0.Q[3], k0.Q[4]
	local bx, by, bz, bw = k1.Q[1], k1.Q[2], k1.Q[3], k1.Q[4]
	if ax * bx + ay * by + az * bz + aw * bw < 0 then
		bx, by, bz, bw = -bx, -by, -bz, -bw
	end
	local u = w0 * (h / 6)
	local ux, uy, uz = u.X, u.Y, u.Z
	local ex = ax + aw * ux + ay * uz - az * uy
	local ey = ay + aw * uy + az * ux - ax * uz
	local ez = az + aw * uz + ax * uy - ay * ux
	local ew = aw - (ax * ux + ay * uy + az * uz)
	local v = w1 * (h / 6)
	local vx, vy, vz = v.X, v.Y, v.Z
	local fx = bx - (bw * vx + by * vz - bz * vy)
	local fy = by - (bw * vy + bz * vx - bx * vz)
	local fz = bz - (bw * vz + bx * vy - by * vx)
	local fw = bw + (bx * vx + by * vy + bz * vz)
	return {
		Smooth = true,
		P0 = p0,
		P1 = a,
		P2 = 3 * (p1 - p0) - 2 * a - b,
		P3 = 2 * (p0 - p1) + a + b,
		ax,
		ay,
		az,
		aw,
		3 * (ex - ax),
		3 * (ey - ay),
		3 * (ez - az),
		3 * (ew - aw),
		3 * (ax - 2 * ex + fx),
		3 * (ay - 2 * ey + fy),
		3 * (az - 2 * ez + fz),
		3 * (aw - 2 * ew + fw),
		bx - ax + 3 * (ex - fx),
		by - ay + 3 * (ey - fy),
		bz - az + 3 * (ez - fz),
		bw - aw + 3 * (ew - fw),
	}
end

local function keyTangent(keys, times, segments, i, b, hBefore, ease)
	local key, count = keys[i], #keys
	local a = i + 1
	local hAfter = if a <= count then times[a] - times[i] else 0
	if b < 1 or a > count or hBefore <= 0 or hAfter <= 0 then
		return Vector3.zero, Vector3.zero
	end
	local previous, following = keys[b], keys[a]
	if key.Style == LINEAR then
		if not isNative(previous) then
			return tangents(previous, key, following, hBefore, hAfter)
		end
		local w, v = nativeVelocity(segments[b], hBefore, 1, ease)
		return junction(w, rotationVector(key.Q, following.Q), hAfter, ROTATION_EPSILON),
			junction(v, following.CFrame.Position - key.CFrame.Position, hAfter, POSITION_EPSILON)
	elseif isNative(key) and not isNative(previous) then
		local w, v = nativeVelocity(segments[i], hAfter, 0, ease)
		return junction(w, rotationVector(previous.Q, key.Q), hBefore, ROTATION_EPSILON),
			junction(v, key.CFrame.Position - previous.CFrame.Position, hBefore, POSITION_EPSILON)
	end
	return Vector3.zero, Vector3.zero
end

function Smooth.Prepare(track, loop, length, ease)
	local keys, times, count, segments = track.Keys, track.Times, track.Count, track.Segments
	if count < 2 then
		track.Pass = table.create(count, false)
		return
	end
	for _, key in keys do
		key.Q = quaternion(key.CFrame)
	end
	local seam = loop
		and count >= 3
		and times[1] <= TIME_EPSILON
		and math.abs(times[count] - length) <= TIME_EPSILON
		and times[2] > times[1]
		and times[count] > times[count - 1]
		and keys[1].Style == LINEAR
		and same(keys[1], keys[count])
	local pass, angular, linear = {}, {}, {}
	for i = 1, count do
		if seam and i == count then
			angular[i], linear[i] = angular[1], linear[1]
		elseif seam and i == 1 then
			angular[i], linear[i] = keyTangent(keys, times, segments, 1, count - 1, times[count] - times[count - 1], ease)
		elseif i < count then
			angular[i], linear[i] = keyTangent(keys, times, segments, i, i - 1, if i > 1 then times[i] - times[i - 1] else 0, ease)
		else
			angular[i], linear[i] = Vector3.zero, Vector3.zero
		end
		pass[i] = angular[i] ~= Vector3.zero or linear[i] ~= Vector3.zero
	end
	for i = 1, count - 1 do
		local key = keys[i]
		local h = times[i + 1] - times[i]
		if h > 0 and not isNative(key) then
			if isStop(key) and not pass[i + 1] then
				segments[i].Direction = INOUT
			else
				segments[i] = build(key, keys[i + 1], angular[i], angular[i + 1], linear[i], linear[i + 1], h)
			end
		end
	end
	track.Pass = pass
	track.Angular = angular
	track.Linear = linear
end

function Smooth.Evaluate(s, a)
	local p = s.P0 + a * (s.P1 + a * (s.P2 + a * s.P3))
	local x = s[1] + a * (s[5] + a * (s[9] + a * s[13]))
	local y = s[2] + a * (s[6] + a * (s[10] + a * s[14]))
	local z = s[3] + a * (s[7] + a * (s[11] + a * s[15]))
	local w = s[4] + a * (s[8] + a * (s[12] + a * s[16]))
	local l = math.sqrt(x * x + y * y + z * z + w * w)
	return CFrame.new(p.X, p.Y, p.Z, x / l, y / l, z / l, w / l)
end

return Smooth
