local RunService = game:GetService("RunService")

local Sampler = require(script.Parent.Parent.Sampler)

local Animation = {}
Animation.Priority = 20
Animation.Seekable = true

local function clips(ctx, actorId)
	local registry = ctx:Registry("Animation")
	local list = registry[actorId]
	if not list then
		list = {}
		registry[actorId] = list
	end
	return list
end

local function fadeWeight(props, elapsed)
	local weight = 1
	if props.FadeIn > 0 then
		weight = math.min(weight, elapsed / props.FadeIn)
	end
	if props.FadeOut > 0 then
		weight = math.min(weight, (props.Duration - elapsed) / props.FadeOut)
	end
	return math.clamp(weight, 0, 1) * props.Weight
end

local function sampleTime(state, localTime)
	local time = localTime + state.Props.ClipOffset
	local length = state.Sampler and state.Sampler.Length or 0
	if state.Props.Loop and length > 0 then
		time %= length
	end
	return time
end

local function assetId(id)
	if string.match(id, "^%d+$") then
		return "rbxassetid://" .. id
	end
	return id
end

local function qualifies(sequence, animationId, exportedHash)
	return sequence ~= nil
		and animationId ~= nil
		and animationId ~= ""
		and exportedHash == Sampler.Hash(sequence)
end

function Animation.UsesAnimator(ctx, actorId)
	if not ctx.Prepared then
		return false
	end
	local modes = ctx:Registry("AnimationMode")
	local mode = modes[actorId]
	if mode == nil then
		mode = false
		local list = clips(ctx, actorId)
		if not ctx.Preview and RunService:IsRunning() and #list > 0 then
			mode = true
			for _, state in list do
				if not qualifies(state.Sequence, state.Props.AnimationId, state.Props.ExportedHash) then
					mode = false
					break
				end
			end
			local actor = ctx:GetActor(actorId)
			local idle = actor and actor.IdleSequence
			if mode and idle and not qualifies(idle, idle:GetAttribute("AnimationId"), idle:GetAttribute("ExportedHash")) then
				mode = false
			end
		end
		modes[actorId] = mode
	end
	return mode
end

local function loadTrack(ctx, actorId, id, looped, priority)
	local animator = ctx:GetAnimator(actorId)
	if not animator then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = assetId(id)
	local track = animator:LoadAnimation(animation)
	track.Looped = looped
	if priority then
		track.Priority = priority
	end
	ctx:OnCleanup(function()
		track:Stop(0)
		track:Destroy()
		animation:Destroy()
	end)
	return track
end

function Animation.Frame(ctx)
	for actorId in ctx:Registry("Animation") do
		local actor = ctx:GetActor(actorId)
		local idle = actor and actor.IdleSequence
		if idle and not actor.IdleTrack and Animation.UsesAnimator(ctx, actorId) then
			actor.IdleTrack = loadTrack(ctx, actorId, idle:GetAttribute("AnimationId"), true, Enum.AnimationPriority.Idle)
			if actor.IdleTrack then
				actor.IdleTrack:Play(0, 1, 1)
			end
		end
	end
end

function Animation.Prepare(clip, props, track, ctx)
	local sequence = clip:FindFirstChild("Keyframes")
	if not (sequence and sequence:IsA("KeyframeSequence")) then
		sequence = clip:FindFirstChildOfClass("KeyframeSequence")
	end
	local state = {
		Actor = track.Actor,
		Props = props,
		Order = track.Order,
		Sequence = sequence,
		Sampler = sequence and ctx:GetSampler(sequence),
		Weight = 0,
	}
	state.Blend = function(key, cframe)
		state.Rig:Blend(key, cframe, state.Weight)
	end
	table.insert(clips(ctx, track.Actor), state)
	return state
end

function Animation.Enter(state, ctx)
	if Animation.UsesAnimator(ctx, state.Actor) then
		state.Track = state.Track or loadTrack(ctx, state.Actor, state.Props.AnimationId, state.Props.Loop)
		if state.Track then
			state.Track:Play(0, 0.0001, state.Props.Speed)
		end
	end
end

function Animation.Update(state, localTime, alpha, ctx)
	local sampler = state.Sampler
	if not sampler then
		return
	end
	local props = state.Props
	local weight = fadeWeight(props, alpha * props.Duration)
	local time = sampleTime(state, localTime)
	if state.Track then
		state.Track:AdjustWeight(math.max(weight, 0.0001), 0)
		if math.abs(state.Track.TimePosition - time) > 0.15 then
			state.Track.TimePosition = time
		end
		return
	end
	if weight <= 0 then
		return
	end
	local rig = ctx:GetRig(state.Actor)
	if not rig then
		return
	end
	state.Rig = rig
	state.Weight = weight
	sampler:Sample(time, state.Blend, sampler:Skip(rig))
end

function Animation.Exit(state)
	if state.Track then
		state.Track:Stop(0)
	end
end

function Animation.PoseAt(ctx, actorId, time, pose)
	local rig = ctx:GetRig(actorId)
	local list = table.clone(clips(ctx, actorId))
	table.sort(list, function(a, b)
		if a.Order ~= b.Order then
			return a.Order < b.Order
		end
		return a.Props.Start < b.Props.Start
	end)
	for _, state in list do
		local props = state.Props
		local elapsed = time - props.Start
		if state.Sampler and elapsed >= 0 and elapsed < props.Duration then
			local weight = fadeWeight(props, elapsed)
			if weight > 0 then
				state.Sampler:Sample(sampleTime(state, elapsed * props.Speed), function(key, cframe)
					if weight >= 1 then
						pose[key] = cframe
					else
						pose[key] = (pose[key] or CFrame.identity):Lerp(cframe, weight)
					end
				end, rig and state.Sampler:Skip(rig))
			end
		end
	end
	return pose
end

return Animation
