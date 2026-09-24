local LookAt = {}
LookAt.Priority = 30
LookAt.Seekable = true

local HEAD = { "Head", "head" }
local NECK = { "Neck", "neck" }
local RESPONSE = 7

local function findJoint(rig, names)
	for _, name in names do
		local joint = rig:Find(name)
		if joint and joint.Kind == "Bone" then
			return joint
		end
	end
	for _, name in names do
		local joint = rig:Find(name)
		if joint then
			return joint
		end
	end
	return nil
end

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function targetPosition(state, ctx, model)
	local props = state.Props
	local id = props.Target
	if id == "Speaker" then
		id = ctx:ActiveSpeaker()
	end
	if not id or id == "" then
		return nil
	end
	local actor = ctx:GetActor(id)
	if not actor or not actor.Model then
		return nil
	end
	if table.find(actor.Models, model) then
		return nil
	end
	local joint = props.TargetJoint
	if joint == "" then
		joint = actor.Attributes.PortraitJoint
	end
	local cframe = ctx:GetJointCFrame(id, joint)
	return cframe and cframe.Position
end

local function rotate(rig, joint, reference, yaw, pitch)
	local world = reference * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0) * reference:Inverse()
	local frame = rig:JointFrame(joint.Key).Rotation
	rig:Additive(joint.Key, frame:Inverse() * world * frame)
end

local function applyRig(state, ctx, rig, weight)
	local head = findJoint(rig, HEAD)
	if not head then
		return
	end
	local neck = findJoint(rig, NECK)
	if neck == head then
		neck = nil
	end
	local smoothing = state.Smoothing[rig]
	if not smoothing then
		smoothing = { Yaw = 0, Pitch = 0, Presence = 0 }
		state.Smoothing[rig] = smoothing
	end
	local reference = rig:ReferenceFrame((neck or head).Parent).Rotation
	local target = targetPosition(state, ctx, rig.Model)
	local yaw, pitch, presence = smoothing.Yaw, smoothing.Pitch, 0
	if target then
		local direction = reference:VectorToObjectSpace(target - rig:WorldCFrame(head.Key).Position)
		if direction.Magnitude > 1e-3 then
			local maxYaw, maxPitch = math.rad(state.Props.MaxYaw), math.rad(state.Props.MaxPitch)
			yaw = math.clamp(math.atan2(-direction.X, -direction.Z), -maxYaw, maxYaw)
			pitch = math.clamp(math.atan2(direction.Y, math.sqrt(direction.X ^ 2 + direction.Z ^ 2)), -maxPitch, maxPitch)
			presence = 1
		end
	end
	if ctx.Seeking or not smoothing.Started then
		smoothing.Started = true
		smoothing.Yaw, smoothing.Pitch, smoothing.Presence = yaw, pitch, presence
	else
		local k = 1 - math.exp(-ctx.DeltaTime * RESPONSE)
		smoothing.Yaw += (yaw - smoothing.Yaw) * k
		smoothing.Pitch += (pitch - smoothing.Pitch) * k
		smoothing.Presence += (presence - smoothing.Presence) * k
	end
	local amount = weight * smoothing.Presence
	if amount <= 1e-3 then
		return
	end
	local y, p = smoothing.Yaw * amount, smoothing.Pitch * amount
	if neck then
		rotate(rig, neck, reference, y * 0.4, p * 0.4)
		rotate(rig, head, reference, y * 0.6, p * 0.6)
	else
		rotate(rig, head, reference, y, p)
	end
end

function LookAt.Prepare(clip, props, track)
	return { Actor = track.Actor, Props = props, Smoothing = {} }
end

function LookAt.Update(state, localTime, alpha, ctx)
	local props = state.Props
	local elapsed = alpha * props.Duration
	local fade = 1
	if props.FadeIn > 0 then
		fade = math.min(fade, elapsed / props.FadeIn)
	end
	if props.FadeOut > 0 then
		fade = math.min(fade, (props.Duration - elapsed) / props.FadeOut)
	end
	local weight = props.Weight * smooth(fade)
	if weight <= 0 then
		return
	end
	for _, rig in ctx:GetRigs(state.Actor) do
		applyRig(state, ctx, rig, weight)
	end
end

function LookAt.Exit(state)
	table.clear(state.Smoothing)
end

return LookAt
