local Talk = {}
Talk.Priority = 35
Talk.Seekable = true

local TAU = math.pi * 2
local RESPONSE = 14
local BOB = math.rad(1.6)

local function split(list)
	local names = {}
	for _, name in string.split(list, ",") do
		name = string.gsub(name, "^%s+", "")
		name = string.gsub(name, "%s+$", "")
		if name ~= "" then
			table.insert(names, name)
		end
	end
	return names
end

local function resolve(state, rig)
	local joints = {}
	local offset = state.Offset
	for _, name in state.Names do
		local joint = rig:Find(name)
		if joint then
			local rest = joint.RestChar
			local inward = if rest.Position.X > 0 then -1 else 1
			local character = Vector3.new(offset.X * inward, offset.Y, offset.Z)
			table.insert(joints, { Key = joint.Key, Offset = rest:VectorToObjectSpace(character) })
			if not state.Head and joint.Parent then
				local head = rig.Joints[joint.Parent]
				state.Head = { Key = head.Key, Axis = head.RestChar:VectorToObjectSpace(Vector3.xAxis) }
			end
		end
	end
	state.Joints = joints
	state.Rig = rig
end

local function openness(t, seed)
	local a = math.sin((t + seed) * TAU * 4.3)
	local b = math.sin((t + seed) * TAU * 2.7 + 0.8)
	local c = math.sin((t + seed) * TAU * 0.9 + 2.1)
	return math.clamp(0.5 + 0.38 * a + 0.22 * b + 0.12 * c, 0, 1)
end

function Talk.Prepare(_, props, _, ctx)
	local actor = ctx:GetActor(props.Actor)
	return {
		Actor = props.Actor,
		Names = split(actor.Attributes.TalkJoints),
		Offset = actor.Attributes.TalkOffset,
		Envelope = 0,
		Seed = (#props.Actor % 7) * 0.137,
	}
end

function Talk.Update(state, _, _, ctx)
	local rig = ctx:GetRig(state.Actor)
	if not rig then
		return
	end
	if state.Rig ~= rig then
		state.Head = nil
		resolve(state, rig)
	end
	local speaker, talking = ctx:ActiveSpeaker()
	local goal = if speaker == state.Actor and talking then 1 else 0
	if ctx.Seeking then
		state.Envelope = goal
	else
		state.Envelope += (goal - state.Envelope) * (1 - math.exp(-ctx.DeltaTime * RESPONSE))
	end
	local envelope = state.Envelope
	if envelope < 1e-3 then
		return
	end
	local t = ctx.Time
	local open = envelope * openness(t, state.Seed)
	for _, joint in state.Joints do
		rig:Additive(joint.Key, CFrame.new(joint.Offset * open))
	end
	local head = state.Head
	if head then
		local angle = BOB * envelope * (0.6 * math.sin((t + state.Seed) * TAU * 2.1) + 0.4 * math.sin((t + state.Seed) * TAU * 0.8 + 1.3))
		rig:Additive(head.Key, CFrame.fromAxisAngle(head.Axis, angle))
	end
end

function Talk.Exit(state)
	state.Envelope = 0
end

return Talk
