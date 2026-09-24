local Event = {}
Event.Priority = 100
Event.Seekable = false
Event.HoldOnPause = true

function Event.Prepare(_, props)
	return { Props = props, End = props.Start + props.Duration }
end

function Event.Enter(state, ctx)
	local props = state.Props
	if props.Side ~= "Server" and props.Name ~= "" then
		ctx:FireEvent(props.Name, "Start", props.Data)
	end
end

function Event.Exit(state, ctx)
	local props = state.Props
	if props.Side ~= "Server" and props.Name ~= "" and props.Duration > 0 and not ctx.Seeking and ctx.Time >= state.End then
		ctx:FireEvent(props.Name, "End", props.Data)
	end
end

return Event
