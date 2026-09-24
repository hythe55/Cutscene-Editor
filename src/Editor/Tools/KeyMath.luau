local Live = require(script.Parent.Live)

local KeyMath = {}

KeyMath.Kinds = { Move = true, Camera = true, Attach = true }
KeyMath.Tolerance = 1 / 60

local function named(value)
	return if type(value) == "string" and value ~= "" then value else nil
end

function KeyMath.Kind(document, clip)
	return document and clip and document:KindOf(clip)
end

function KeyMath.Props(document, clip)
	return document:Read(clip)
end

function KeyMath.KeyTime(key)
	local value = key:GetAttribute("Time")
	return if type(value) == "number" then value else tonumber(key.Name) or 0
end

function KeyMath.ToCutscene(props, localTime)
	return props.Start + localTime / math.max(props.Speed or 1, 1e-3)
end

function KeyMath.ToLocal(props, t)
	return (t - props.Start) * (props.Speed or 1)
end

function KeyMath.Inside(props, t)
	return t >= props.Start - 1e-4 and t <= props.Start + props.Duration + 1e-4
end

function KeyMath.Clamp(props, t)
	return math.clamp(t, props.Start, props.Start + props.Duration)
end

function KeyMath.IsAnchored(kind, props)
	return (kind == "Camera" and named(props.Anchor) ~= nil) or kind == "Attach"
end

function KeyMath.Frame(app, kind, props, t)
	if kind == "Camera" then
		local anchor = named(props.Anchor)
		if not anchor then
			return CFrame.identity
		end
		return Live.JointCFrame(app, anchor, props.AnchorJoint or "", t)
	elseif kind == "Attach" then
		local target = named(props.Target)
		if not target then
			return nil
		end
		return Live.JointCFrame(app, target, props.TargetJoint or "", t)
	end
	return CFrame.identity
end

function KeyMath.KeyWorld(app, kind, props, value, localTime)
	local frame = KeyMath.Frame(app, kind, props, KeyMath.ToCutscene(props, localTime))
	return frame and frame * value
end

function KeyMath.WorldToKey(app, kind, props, world, localTime)
	local frame = KeyMath.Frame(app, kind, props, KeyMath.ToCutscene(props, localTime))
	return frame and frame:ToObjectSpace(world)
end

function KeyMath.AttachTime(app, props)
	return KeyMath.Clamp(props, app.Time)
end

function KeyMath.AttachWorld(app, props)
	local frame = KeyMath.Frame(app, "Attach", props, KeyMath.AttachTime(app, props))
	return frame and frame * (props.Offset or CFrame.identity)
end

function KeyMath.Path(app, spline, kind, props, keys, samples)
	local count = #keys
	if count < 2 then
		return {}
	end
	local first, last = keys[1].Time, keys[count].Time
	local points = {}
	samples = samples or math.clamp(count * 12, 16, 96)
	for index = 0, samples do
		local localTime = first + (last - first) * index / samples
		local cframe = spline.Evaluate(keys, localTime, props.Interpolation)
		local world = cframe and KeyMath.KeyWorld(app, kind, props, cframe, localTime)
		if world then
			table.insert(points, world.Position)
		end
	end
	return points
end

function KeyMath.FindKey(keys, localTime)
	local best, bestDistance = nil, KeyMath.Tolerance
	for _, key in keys do
		local distance = math.abs(KeyMath.KeyTime(key) - localTime)
		if distance <= bestDistance then
			best, bestDistance = key, distance
		end
	end
	return best
end

function KeyMath.Frustum(cframe, fov, depth)
	local half = math.tan(math.rad(math.clamp(fov or 70, 1, 120)) / 2) * depth
	local width = half * 16 / 9
	local corners = {}
	for _, sign in { Vector2.new(-1, 1), Vector2.new(1, 1), Vector2.new(1, -1), Vector2.new(-1, -1) } do
		table.insert(corners, cframe * Vector3.new(sign.X * width, sign.Y * half, -depth))
	end
	return corners
end

return KeyMath
