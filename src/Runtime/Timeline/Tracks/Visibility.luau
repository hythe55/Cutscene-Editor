local Visibility = {}
Visibility.Priority = 55
Visibility.Seekable = true

function Visibility.Prepare(clip, props, track, ctx)
	local state = {
		Actor = track.Actor,
		Start = props.Start,
		End = props.Start + props.Duration,
		FadeIn = props.FadeIn,
		FadeOut = props.FadeOut,
	}
	local registry = ctx:Registry("Visibility")
	local list = registry[track.Actor]
	if not list then
		list = {}
		registry[track.Actor] = list
	end
	table.insert(list, state)
	return state
end

local function visibleAt(state, t)
	if t < state.Start or t >= state.End then
		return 0
	end
	local value = 1
	if state.FadeIn > 0 then
		value = math.min(value, (t - state.Start) / state.FadeIn)
	end
	if state.FadeOut > 0 then
		value = math.min(value, (state.End - t) / state.FadeOut)
	end
	return math.clamp(value, 0, 1)
end

function Visibility.Frame(ctx)
	local t = ctx.Time
	for actorId, list in ctx:Registry("Visibility") do
		local visible = 0
		for _, state in list do
			visible = math.max(visible, visibleAt(state, t))
		end
		ctx:SetHidden(actorId, "Visibility", 1 - visible)
	end
end

return Visibility
