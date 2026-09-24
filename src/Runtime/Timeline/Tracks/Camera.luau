local Spline = require(script.Parent.Parent.Spline)

local Camera = {}
Camera.Priority = 70
Camera.Seekable = true

local SHAKE_SEEDS = { 11.31, 23.73, 37.17, 41.93, 53.39, 67.71 }
local FOCUS_SMOOTHING = 0.22
local FOCUS_CARRY = 0.15
local DEFAULT_FOCUS = 12

local registries = setmetatable({}, { __mode = "k" })

local function named(value)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function registryOf(ctx)
	local key = ctx.Timeline or ctx
	local registry = registries[key]
	if not registry then
		registry = { Anchors = {} }
		registries[key] = registry
	end
	return registry
end

local function cameraOf(ctx)
	return ctx.Camera or workspace.CurrentCamera
end

local function jointCFrame(ctx, actor, joint)
	if not actor then
		return nil
	end
	local cframe = ctx:GetJointCFrame(actor, joint)
	if typeof(cframe) == "CFrame" then
		return cframe
	end
	return nil
end

local function noise(x, seed)
	return (math.noise(x, seed, 0.5) + 0.5 * math.noise(x * 2.13, seed, 7.5)) * 1.5
end

local function shakeOffset(amount, frequency, t)
	local x = t * math.max(frequency, 0)
	local offset = Vector3.new(noise(x, SHAKE_SEEDS[1]), noise(x, SHAKE_SEEDS[2]), noise(x, SHAKE_SEEDS[3])) * amount
	local angle = math.rad(amount)
	return CFrame.new(offset)
		* CFrame.Angles(noise(x, SHAKE_SEEDS[4]) * angle, noise(x, SHAKE_SEEDS[5]) * angle, noise(x, SHAKE_SEEDS[6]) * angle * 0.5)
end

local function anchorOf(state, ctx)
	local actor = state.Anchor
	local anchors = registryOf(ctx).Anchors
	local cframe = jointCFrame(ctx, actor, state.AnchorJoint)
	if cframe then
		state.LastAnchor = cframe
		anchors[state.AnchorKey] = cframe
		return cframe
	end
	cframe = state.LastAnchor or anchors[state.AnchorKey]
	if not cframe and not state.Warned then
		state.Warned = true
		warn(`Timeline: Camera clip "{state.Clip.Name}" can't find anchor "{actor}"; holding the previous view`)
	end
	return cframe
end

local function compute(state, localTime, ctx)
	local cframe, fov = Spline.Evaluate(state.Keys, localTime, state.Props.Interpolation)
	if not cframe then
		return nil, nil
	end
	local props = state.Props
	if state.Anchor then
		local anchor = anchorOf(state, ctx)
		if not anchor then
			return nil, nil
		end
		cframe = anchor * cframe
	end
	local weight = math.clamp(props.LookAtWeight or 0, 0, 1)
	local target = weight > 0 and jointCFrame(ctx, named(props.LookAtActor), named(props.LookAtJoint))
	if target and (target.Position - cframe.Position).Magnitude > 1e-3 then
		local look = CFrame.lookAt(cframe.Position, target.Position, cframe.UpVector)
		cframe = cframe:Lerp(look, weight)
	end
	local shake = props.Shake or 0
	if shake > 0 then
		cframe *= shakeOffset(shake, props.ShakeFrequency or 1, localTime)
	end
	return cframe, fov
end

local function focusOf(ctx)
	local registry = registryOf(ctx)
	local focus = registry.Focus
	if not focus then
		focus = {}
		registry.Focus = focus
		ctx:OnCleanup(function()
			if focus.Effect then
				focus.Effect:Destroy()
				focus.Effect = nil
			end
		end)
	end
	return focus
end

local function releaseFocus(state, ctx)
	local focus = focusOf(ctx)
	if focus.Owner == state then
		focus.Owner = nil
		if focus.Effect then
			focus.Effect:Destroy()
			focus.Effect = nil
		end
	end
end

local function updateFocus(state, ctx, cframe, dt)
	local actor = named(state.Props.FocusActor)
	if not actor then
		return nil
	end
	local focus = focusOf(ctx)
	if not focus.Effect or not focus.Effect.Parent then
		local effect = Instance.new("DepthOfFieldEffect")
		effect.Name = "TimelineFocus"
		effect.Archivable = false
		effect.FarIntensity = 0.75
		effect.NearIntensity = 0.6
		effect.Parent = cameraOf(ctx)
		focus.Effect = effect
	end
	local target = jointCFrame(ctx, actor, named(state.Props.FocusJoint))
	local goal = if target then (target.Position - cframe.Position).Magnitude else focus.Distance or DEFAULT_FOCUS
	local now = os.clock()
	if focus.Owner ~= state then
		local carried = focus.Distance and focus.Stamp and now - focus.Stamp <= FOCUS_CARRY
		focus.Owner = state
		if not carried then
			focus.Distance = goal
		end
	end
	if ctx.Seeking or not focus.Distance or dt > 0.5 then
		focus.Distance = goal
	else
		focus.Distance += (goal - focus.Distance) * (1 - math.exp(-dt / FOCUS_SMOOTHING))
	end
	focus.Stamp = now
	local effect = focus.Effect
	effect.Enabled = true
	effect.FocusDistance = math.clamp(focus.Distance, 0, 200)
	effect.InFocusRadius = math.clamp(focus.Distance * 0.2, 0.5, 50)
	return focus.Distance
end

local function apply(state, ctx, localTime, dt)
	local registry = registryOf(ctx)
	local cframe, fov = compute(state, localTime, ctx)
	if cframe then
		registry.LastCFrame, registry.LastFOV = cframe, fov
	else
		cframe, fov = registry.LastCFrame, registry.LastFOV
		if not cframe then
			return
		end
	end
	local camera = cameraOf(ctx)
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local distance = updateFocus(state, ctx, cframe, dt) or DEFAULT_FOCUS
	camera.CFrame = cframe
	camera.Focus = cframe * CFrame.new(0, 0, -distance)
	camera.FieldOfView = math.clamp(fov, 1, 120)
end

function Camera.Prepare(clip, props, _track, _ctx)
	local anchor = named(props.Anchor)
	local joint = named(props.AnchorJoint)
	return {
		Clip = clip,
		Props = props,
		Keys = Spline.ReadKeys(clip:FindFirstChild("Keys")),
		Anchor = anchor,
		AnchorJoint = joint,
		AnchorKey = if anchor then anchor .. "\0" .. (joint or "") else nil,
		Active = false,
	}
end

function Camera.Enter(state, ctx)
	ctx:ClaimCamera(state)
	state.Active = true
	state.LocalTime = nil
end

function Camera.Update(state, localTime, _alpha, ctx)
	if not state.Active then
		return
	end
	local speed = math.max(state.Props.Speed or 1, 1e-3)
	local dt = if state.LocalTime then math.abs(localTime - state.LocalTime) / speed else math.huge
	state.LocalTime = localTime
	apply(state, ctx, localTime, dt)
end

function Camera.Exit(state, ctx)
	if not state.Active then
		return
	end
	state.Active = false
	releaseFocus(state, ctx)
	ctx:ReleaseCamera(state)
end

function Camera.Destroy(state, ctx)
	Camera.Exit(state, ctx)
	local focus = focusOf(ctx)
	if not focus.Owner and focus.Effect then
		focus.Effect:Destroy()
		focus.Effect = nil
	end
end

return Camera
