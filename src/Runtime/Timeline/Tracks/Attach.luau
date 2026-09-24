local Attach = {}
Attach.Priority = 50
Attach.Seekable = true

function Attach.Prepare(clip, props, track, ctx)
	local state = {
		Actor = track.Actor,
		Props = props,
		Start = props.Start,
		End = props.Start + props.Duration,
	}
	local registry = ctx:Registry("Attach")
	local list = registry[track.Actor]
	if not list then
		list = {}
		registry[track.Actor] = list
	end
	table.insert(list, state)
	table.sort(list, function(a, b)
		return a.Start < b.Start
	end)
	return state
end

local function smooth(x)
	return x * x * (3 - 2 * x)
end

local function underlying(ctx, actor, t)
	return ctx:PivotAt(actor.Id, t)
end

local function goal(state, ctx)
	local props = state.Props
	local cframe = ctx:GetJointCFrame(props.Target, props.TargetJoint)
	return cframe and cframe * props.Offset
end

local LIVE_WINDOW = 0.25

local function canProbe(ctx, actorId)
	local animation = ctx.Timeline.Modules.Animation
	return not (animation and animation.CanProbe) or animation.CanProbe(ctx, actorId)
end

local function exitPivot(state, ctx)
	if state.ExitPivot == nil then
		local props = state.Props
		local live = state.LivePivot ~= nil and state.End - state.LiveTime <= LIVE_WINDOW
		local cframe
		if (live and not ctx.Preview) or not canProbe(ctx, props.Target) then
			cframe = state.LivePivot
		else
			local joint = ctx:ProbeJointCFrame(props.Target, props.TargetJoint, state.End)
			cframe = joint and joint * props.Offset
		end
		state.ExitPivot = cframe or false
	end
	return state.ExitPivot or nil
end

function Attach.Frame(ctx)
	local t = ctx.Time
	local move = ctx.Timeline.Modules.Move
	for actorId, list in ctx:Registry("Attach") do
		local actor = ctx:GetActor(actorId)
		local model = actor and actor.Model
		if model and model.Parent then
			local pivot, base, hidden, controlled = nil, nil, false, false
			local moveStart = move and move.LastStart(ctx, actorId, t)
			for _, state in list do
				if state.Start > t then
					break
				end
				controlled = true
				if t < state.End then
					local target = goal(state, ctx)
					if target then
						local from = base or underlying(ctx, actor, state.Start) or target
						local blendIn = state.Props.BlendIn
						local blend = if blendIn > 0 then smooth(math.clamp((t - state.Start) / blendIn, 0, 1)) else 1
						pivot = from:Lerp(target, blend)
						state.LivePivot = pivot
						state.LiveTime = t
					end
					hidden = false
				elseif moveStart and moveStart >= state.End then
					pivot, base, hidden, controlled = nil, nil, false, false
				else
					local onExit = state.Props.OnExit
					if onExit == "Stay" then
						base = exitPivot(state, ctx) or base
						hidden = false
					elseif onExit == "Hide" then
						hidden = true
					else
						hidden = false
					end
					pivot = base
				end
			end
			if not pivot and (controlled or (actor.Kind ~= "Player" and actor.Kind ~= "Group")) then
				pivot = underlying(ctx, actor, t)
			end
			if pivot and model:GetPivot() ~= pivot then
				model:PivotTo(pivot)
			end
			ctx:SetHidden(actorId, "Attach", if hidden then 1 else 0)
		end
	end
end

return Attach
