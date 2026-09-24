local Move = {}
Move.Priority = 10
Move.Seekable = true

local function spline()
	return require(script.Parent.Parent:FindFirstChild("Spline"))
end

function Move.Prepare(clip, props, track, ctx)
	local Spline = spline()
	local state = {
		Actor = track.Actor,
		Keys = Spline.ReadKeys(clip:FindFirstChild("Keys")),
		Interpolation = props.Interpolation,
		Start = props.Start,
		End = props.Start + props.Duration,
		Duration = props.Duration,
		Speed = props.Speed,
		Order = track.Order,
		Spline = Spline,
	}
	if #state.Keys > 0 then
		local registry = ctx:Registry("Move")
		local list = registry[track.Actor]
		if not list then
			list = {}
			registry[track.Actor] = list
		end
		table.insert(list, state)
		table.sort(list, function(a, b)
			if a.Start ~= b.Start then
				return a.Start < b.Start
			end
			return a.Order < b.Order
		end)
	end
	return state
end

local function latest(ctx, actorId, t)
	local list = ctx:Registry("Move")[actorId]
	local chosen
	if list then
		for _, state in list do
			if state.Start > t then
				break
			end
			chosen = state
		end
	end
	return chosen
end

function Move.LastStart(ctx, actorId, t)
	local state = latest(ctx, actorId, t)
	return state and state.Start
end

function Move.PivotAt(ctx, actorId, t)
	local state = latest(ctx, actorId, t)
	if not state then
		return nil
	end
	local localTime = (math.min(t, state.End) - state.Start) * state.Speed
	return (state.Spline.Evaluate(state.Keys, localTime, state.Interpolation))
end

function Move.Frame(ctx)
	local t = ctx.Time
	for actorId in ctx:Registry("Move") do
		local actor = ctx:GetActor(actorId)
		if actor and actor.Model then
			local pivot
			if actor.Kind == "Player" or actor.Kind == "Group" then
				local state = latest(ctx, actorId, t)
				if state and t < state.End then
					pivot = Move.PivotAt(ctx, actorId, t)
				end
			else
				pivot = Move.PivotAt(ctx, actorId, t) or actor.SourcePivot
			end
			if pivot then
				for _, model in actor.Models do
					if model.Parent and model:GetPivot() ~= pivot then
						model:PivotTo(pivot)
					end
				end
			end
		end
	end
end

return Move
