local TweenService = game:GetService("TweenService")

local Spline = {}

local EPSILON = 1e-5
local STEP = 1e-4
local FLAT = 0.02
local DEFAULT_FOV = 70

local styles = {}
local directions = {}
local rateCache = {}
local caches = setmetatable({}, { __mode = "k" })

local function styleOf(name)
	name = name or "Linear"
	local style = styles[name]
	if style == nil then
		if name == "Constant" then
			style = "Constant"
		else
			local ok, value = pcall(function()
				return (Enum.EasingStyle :: any)[name]
			end)
			style = ok and value or Enum.EasingStyle.Linear
		end
		styles[name] = style
	end
	return style
end

local function directionOf(name)
	name = name or "InOut"
	local direction = directions[name]
	if direction == nil then
		local ok, value = pcall(function()
			return (Enum.EasingDirection :: any)[name]
		end)
		direction = ok and value or Enum.EasingDirection.InOut
		directions[name] = direction
	end
	return direction
end

local function rawEase(style, direction, u)
	if style == "Constant" then
		return u >= 1 and 1 or 0
	elseif style == Enum.EasingStyle.Linear then
		return u
	end
	return TweenService:GetValue(u, style, direction)
end

function Spline.Ease(key, u)
	return rawEase(styleOf(key.Easing), directionOf(key.EasingDirection), u)
end

local function rates(key)
	local style = styleOf(key.Easing)
	local direction = directionOf(key.EasingDirection)
	local byStyle = rateCache[style]
	if not byStyle then
		byStyle = {}
		rateCache[style] = byStyle
	end
	local cached = byStyle[direction]
	if not cached then
		local startRate, endRate = 0, 0
		if style ~= "Constant" then
			startRate = (rawEase(style, direction, STEP) - rawEase(style, direction, 0)) / STEP
			endRate = (rawEase(style, direction, 1) - rawEase(style, direction, 1 - STEP)) / STEP
		end
		cached = {
			if startRate > FLAT then startRate else 0,
			if endRate > FLAT then endRate else 0,
		}
		byStyle[direction] = cached
	end
	return cached[1], cached[2]
end

local function quaternionOf(cframe)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cframe:GetComponents()
	local trace = r00 + r11 + r22
	local w, x, y, z
	if trace > 0 then
		local s = math.sqrt(trace + 1) * 2
		w, x, y, z = s / 4, (r21 - r12) / s, (r02 - r20) / s, (r10 - r01) / s
	elseif r00 > r11 and r00 > r22 then
		local s = math.sqrt(1 + r00 - r11 - r22) * 2
		w, x, y, z = (r21 - r12) / s, s / 4, (r01 + r10) / s, (r02 + r20) / s
	elseif r11 > r22 then
		local s = math.sqrt(1 + r11 - r00 - r22) * 2
		w, x, y, z = (r02 - r20) / s, (r01 + r10) / s, s / 4, (r12 + r21) / s
	else
		local s = math.sqrt(1 + r22 - r00 - r11) * 2
		w, x, y, z = (r10 - r01) / s, (r02 + r20) / s, (r12 + r21) / s, s / 4
	end
	local length = math.sqrt(w * w + x * x + y * y + z * z)
	return w / length, x / length, y / length, z / length
end

local function multiply(aw, ax, ay, az, bw, bx, by, bz)
	return aw * bw - ax * bx - ay * by - az * bz,
		aw * bx + ax * bw + ay * bz - az * by,
		aw * by - ax * bz + ay * bw + az * bx,
		aw * bz + ax * by - ay * bx + az * bw
end

local function power(w, x, y, z, t)
	if w < 0 then
		w, x, y, z = -w, -x, -y, -z
	end
	local sine = math.sqrt(x * x + y * y + z * z)
	if sine < 1e-12 then
		return 1, x * t, y * t, z * t
	end
	local half = math.atan2(sine, w) * t
	local k = math.sin(half) / sine
	return math.cos(half), x * k, y * k, z * k
end

local function toVector(w, x, y, z)
	if w < 0 then
		w, x, y, z = -w, -x, -y, -z
	end
	local sine = math.sqrt(x * x + y * y + z * z)
	if sine < 1e-12 then
		return Vector3.new(2 * x, 2 * y, 2 * z)
	end
	local k = 2 * math.atan2(sine, w) / sine
	return Vector3.new(x * k, y * k, z * k)
end

local function fromVector(vector)
	local angle = vector.Magnitude
	if angle < 1e-12 then
		return 1, vector.X / 2, vector.Y / 2, vector.Z / 2
	end
	local k = math.sin(angle / 2) / angle
	return math.cos(angle / 2), vector.X * k, vector.Y * k, vector.Z * k
end

local function slerp(aw, ax, ay, az, bw, bx, by, bz, t)
	local dw, dx, dy, dz = multiply(aw, -ax, -ay, -az, bw, bx, by, bz)
	return multiply(aw, ax, ay, az, power(dw, dx, dy, dz, t))
end

local function clampMagnitude(vector, limit)
	local magnitude = vector.Magnitude
	if magnitude > limit and magnitude > 0 then
		return vector * (limit / magnitude)
	end
	return vector
end

local function span(keys, i)
	local a, b = keys[i], keys[i + 1]
	if not a or not b then
		return nil
	end
	local dt = b.Time - a.Time
	if dt <= EPSILON then
		return nil
	end
	return dt
end

local function sideData(keys, rotations, from, dt)
	local a, b = rotations[from], rotations[from + 1]
	return {
		Dt = dt,
		Move = keys[from + 1].CFrame.Position - keys[from].CFrame.Position,
		Turn = toVector(multiply(a[1], -a[2], -a[3], -a[4], b[1], b[2], b[3], b[4])),
		Zoom = (keys[from + 1].FOV or DEFAULT_FOV) - (keys[from].FOV or DEFAULT_FOV),
	}
end

local function interior(inSide, outSide)
	local dtIn, dtOut = inSide.Dt, outSide.Dt
	local total = dtIn + dtOut
	local lengthIn, lengthOut = inSide.Move.Magnitude, outSide.Move.Magnitude
	local velocity = Vector3.zero
	if lengthIn > EPSILON and lengthOut > EPSILON then
		local rootIn, rootOut = math.sqrt(lengthIn), math.sqrt(lengthOut)
		local tangent = inSide.Move / rootIn - (inSide.Move + outSide.Move) / (rootIn + rootOut) + outSide.Move / rootOut
		if tangent.Magnitude > EPSILON then
			local speed = (lengthIn / dtIn * dtOut + lengthOut / dtOut * dtIn) / total
			velocity = tangent.Unit * speed
		end
	end
	local spin = (inSide.Turn / dtIn * dtOut + outSide.Turn / dtOut * dtIn) / total
	local zoom = 0
	if inSide.Zoom * outSide.Zoom > 0 then
		zoom = (inSide.Zoom / dtIn * dtOut + outSide.Zoom / dtOut * dtIn) / total
	end
	return velocity, spin, zoom
end

local function natural(keys, sides, k, nested)
	local inSide = sides[k - 1]
	local outSide = sides[k]
	local velocity, spin, zoom = Vector3.zero, Vector3.zero, 0
	if inSide and outSide then
		velocity, spin, zoom = interior(inSide, outSide)
	elseif inSide or outSide then
		local side = inSide or outSide
		local chordVelocity, chordSpin, chordZoom = side.Move / side.Dt, side.Turn / side.Dt, side.Zoom / side.Dt
		if nested then
			return chordVelocity, chordSpin, chordZoom
		end
		local nv, ns, nz = natural(keys, sides, if inSide then k - 1 else k + 1, true)
		velocity = (chordVelocity * 3 - nv) / 2
		spin = (chordSpin * 3 - ns) / 2
		zoom = (chordZoom * 3 - nz) / 2
		if zoom * chordZoom <= 0 then
			zoom = 0
		end
	end
	local limitMove, limitTurn, limitZoom = math.huge, math.huge, math.huge
	if inSide then
		local _, rate = rates(keys[k - 1])
		local factor = 3 * (if rate > 0 then rate else 1) / inSide.Dt
		limitMove = math.min(limitMove, inSide.Move.Magnitude * factor)
		limitTurn = math.min(limitTurn, inSide.Turn.Magnitude * factor)
		limitZoom = math.min(limitZoom, math.abs(inSide.Zoom) * factor)
	end
	if outSide then
		local rate = rates(keys[k])
		local factor = 3 * (if rate > 0 then rate else 1) / outSide.Dt
		limitMove = math.min(limitMove, outSide.Move.Magnitude * factor)
		limitTurn = math.min(limitTurn, outSide.Turn.Magnitude * factor)
		limitZoom = math.min(limitZoom, math.abs(outSide.Zoom) * factor)
	end
	return clampMagnitude(velocity, limitMove), clampMagnitude(spin, limitTurn), math.clamp(zoom, -limitZoom, limitZoom)
end

local function segment(keys, sides, naturals, rotations, i, dt)
	local startRate, endRate = rates(keys[i])
	local v0, w0, f0 = naturals[i][1], naturals[i][2], naturals[i][3]
	local v1, w1, f1 = naturals[i + 1][1], naturals[i + 1][2], naturals[i + 1][3]
	local startScale, endScale
	if startRate == 0 then
		startScale = dt
	elseif sides[i - 1] and select(2, rates(keys[i - 1])) == 0 then
		startScale = 0
	else
		startScale = dt / startRate
	end
	if endRate == 0 then
		endScale = dt
	elseif sides[i + 1] and rates(keys[i + 1]) == 0 then
		endScale = 0
	else
		endScale = dt / endRate
	end
	local a, b = rotations[i], rotations[i + 1]
	local r0, r1 = w0 * startScale, w1 * endScale
	local cw, cx, cy, cz = multiply(a[1], a[2], a[3], a[4], fromVector(r0 / 3))
	local dw, dx, dy, dz = multiply(b[1], b[2], b[3], b[4], fromVector(-r1 / 3))
	return {
		M0 = v0 * startScale,
		Z0 = f0 * startScale,
		M1 = v1 * endScale,
		Z1 = f1 * endScale,
		ControlA = { cw, cx, cy, cz },
		ControlB = { dw, dx, dy, dz },
	}
end

local function snapshot(key)
	return {
		Key = key,
		Time = key.Time,
		CFrame = key.CFrame,
		FOV = key.FOV,
		Easing = key.Easing,
		EasingDirection = key.EasingDirection,
	}
end

local function isCurrent(cache, keys)
	local count = #keys
	if cache.Count ~= count then
		return false
	end
	local snaps = cache.Snapshots
	for k = 1, count do
		local key, snap = keys[k], snaps[k]
		if
			snap.Key ~= key
			or snap.Time ~= key.Time
			or snap.CFrame ~= key.CFrame
			or snap.FOV ~= key.FOV
			or snap.Easing ~= key.Easing
			or snap.EasingDirection ~= key.EasingDirection
		then
			return false
		end
	end
	return true
end

local function build(keys)
	local count = #keys
	local rotations, sides, naturals, snapshots = {}, {}, {}, {}
	for k = 1, count do
		rotations[k] = { quaternionOf(keys[k].CFrame) }
		snapshots[k] = snapshot(keys[k])
	end
	for i = 1, count - 1 do
		local dt = span(keys, i)
		sides[i] = if dt then sideData(keys, rotations, i, dt) else false
	end
	for k = 1, count do
		naturals[k] = { natural(keys, sides, k) }
	end
	local segments = {}
	for i = 1, count - 1 do
		local dt = sides[i] and sides[i].Dt
		segments[i] = if dt then segment(keys, sides, naturals, rotations, i, dt) else false
	end
	return {
		Count = count,
		Snapshots = snapshots,
		Rotations = rotations,
		Segments = segments,
	}
end

local function cacheOf(keys)
	local cache = caches[keys]
	if not cache or not isCurrent(cache, keys) then
		cache = build(keys)
		caches[keys] = cache
	end
	return cache
end

local function hermite(s)
	local s2, s3 = s * s, s * s * s
	return 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
end

local function locate(keys, time)
	local low, high = 1, #keys
	while high - low > 1 do
		local middle = (low + high) // 2
		if keys[middle].Time <= time then
			low = middle
		else
			high = middle
		end
	end
	return low
end

local function finite(value)
	value = tonumber(value)
	if value == nil or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function word(value, default)
	return if type(value) == "string" and value ~= "" then value else default
end

function Spline.ReadKeys(keysFolder)
	local keys = {}
	if not keysFolder then
		return keys
	end
	for _, child in keysFolder:GetChildren() do
		if child:IsA("CFrameValue") then
			local fov = finite(child:GetAttribute("FOV"))
			table.insert(keys, {
				Time = math.max(finite(child:GetAttribute("Time")) or finite(child.Name) or 0, 0),
				CFrame = child.Value,
				FOV = if fov then math.clamp(fov, 1, 120) else DEFAULT_FOV,
				Easing = word(child:GetAttribute("Easing"), "Linear"),
				EasingDirection = word(child:GetAttribute("EasingDirection"), "InOut"),
				Instance = child,
			})
		end
	end
	table.sort(keys, function(a, b)
		if a.Time == b.Time then
			return a.Instance.Name < b.Instance.Name
		end
		return a.Time < b.Time
	end)
	return keys
end

function Spline.Length(keys)
	local last = keys[#keys]
	return last and last.Time or 0
end

local function compose(position, w, x, y, z)
	return CFrame.new(position.X, position.Y, position.Z, x, y, z, w)
end

function Spline.Evaluate(keys, time, interpolation)
	local count = #keys
	if count == 0 then
		return nil, nil
	end
	local first, last = keys[1], keys[count]
	if count == 1 or time <= first.Time then
		return first.CFrame, first.FOV or DEFAULT_FOV
	elseif time >= last.Time then
		return last.CFrame, last.FOV or DEFAULT_FOV
	end
	local i = locate(keys, time)
	local a, b = keys[i], keys[i + 1]
	local dt = b.Time - a.Time
	if dt <= EPSILON then
		return b.CFrame, b.FOV or DEFAULT_FOV
	end
	local cache = cacheOf(keys)
	local s = Spline.Ease(a, (time - a.Time) / dt)
	local qa, qb = cache.Rotations[i], cache.Rotations[i + 1]
	local aw, ax, ay, az = qa[1], qa[2], qa[3], qa[4]
	local bw, bx, by, bz = qb[1], qb[2], qb[3], qb[4]
	local fovA, fovB = a.FOV or DEFAULT_FOV, b.FOV or DEFAULT_FOV
	local positionA, positionB = a.CFrame.Position, b.CFrame.Position
	if interpolation == "Linear" then
		return compose(positionA:Lerp(positionB, s), slerp(aw, ax, ay, az, bw, bx, by, bz, s)), fovA + (fovB - fovA) * s
	end
	local piece = cache.Segments[i]
	local h00, h10, h01, h11 = hermite(s)
	local position = positionA * h00 + piece.M0 * h10 + positionB * h01 + piece.M1 * h11
	local fov = fovA * h00 + piece.Z0 * h10 + fovB * h01 + piece.Z1 * h11
	local ca, cb = piece.ControlA, piece.ControlB
	local cw, cx, cy, cz = ca[1], ca[2], ca[3], ca[4]
	local dw, dx, dy, dz = cb[1], cb[2], cb[3], cb[4]
	local p1w, p1x, p1y, p1z = slerp(aw, ax, ay, az, cw, cx, cy, cz, s)
	local p2w, p2x, p2y, p2z = slerp(cw, cx, cy, cz, dw, dx, dy, dz, s)
	local p3w, p3x, p3y, p3z = slerp(dw, dx, dy, dz, bw, bx, by, bz, s)
	local q1w, q1x, q1y, q1z = slerp(p1w, p1x, p1y, p1z, p2w, p2x, p2y, p2z, s)
	local q2w, q2x, q2y, q2z = slerp(p2w, p2x, p2y, p2z, p3w, p3x, p3y, p3z, s)
	return compose(position, slerp(q1w, q1x, q1y, q1z, q2w, q2x, q2y, q2z, s)), fov
end

return Spline
