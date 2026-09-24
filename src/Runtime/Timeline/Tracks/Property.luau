local TweenService = game:GetService("TweenService")

local Property = {}
Property.Priority = 60
Property.Seekable = true

local LERPABLE = {
	Vector3 = true,
	Vector2 = true,
	CFrame = true,
	Color3 = true,
	UDim2 = true,
}

local function descend(instance, parts, index)
	if index > #parts then
		return instance
	end
	local name = parts[index]
	for last = index, #parts do
		if last > index then
			name ..= "/" .. parts[last]
		end
		local child = instance:FindFirstChild(name)
		if child then
			local found = descend(child, parts, last + 1)
			if found then
				return found
			end
		end
	end
	return nil
end

local function resolve(ctx, props, trackActor)
	local actorId = if props.Target ~= "" then props.Target else trackActor
	local actor = ctx:GetActor(actorId)
	local instance = actor and actor.Model
	if not instance or props.Path == "" then
		return instance
	end
	return descend(instance, string.split(props.Path, "/"), 1)
end

local function enumOf(enum, name, default)
	local ok, value = pcall(function()
		return (enum :: any)[name]
	end)
	return if ok and value then value else default
end

local function lerp(a, b, t)
	local kind = typeof(b)
	if typeof(a) ~= kind then
		return if t >= 0.5 then b else a
	end
	if kind == "number" then
		return a + (b - a) * t
	elseif LERPABLE[kind] then
		return a:Lerp(b, t)
	elseif kind == "UDim" then
		return UDim.new(a.Scale + (b.Scale - a.Scale) * t, math.round(a.Offset + (b.Offset - a.Offset) * t))
	elseif kind == "NumberRange" then
		return NumberRange.new(a.Min + (b.Min - a.Min) * t, a.Max + (b.Max - a.Max) * t)
	end
	return if t >= 0.5 then b else a
end

function Property.Prepare(clip, props, track, ctx)
	local state = { Props = props }
	local instance = resolve(ctx, props, track.Actor)
	if instance and props.Property ~= "" then
		local ok = pcall(function()
			return instance[props.Property]
		end)
		if ok then
			state.Instance = instance
			state.Original = ctx:Remember(instance, props.Property)
		else
			warn(`Timeline: Property clip "{clip.Name}" has no property {props.Property} on {instance:GetFullName()}`)
		end
	end
	if props.Easing == "Constant" then
		state.Constant = true
	else
		state.Style = enumOf(Enum.EasingStyle, props.Easing, Enum.EasingStyle.Sine)
	end
	state.Direction = enumOf(Enum.EasingDirection, props.EasingDirection, Enum.EasingDirection.InOut)
	return state
end

function Property.Update(state, _, alpha)
	local instance = state.Instance
	if not instance or not instance.Parent then
		return
	end
	local props = state.Props
	local eased
	if state.Constant then
		eased = if alpha >= 1 then 1 else 0
	else
		eased = TweenService:GetValue(alpha, state.Style, state.Direction)
	end
	local from = if props.From ~= nil then props.From else state.Original
	local to = if props.To ~= nil then props.To else state.Original
	local value = lerp(from, to, eased)
	if value ~= state.Last then
		state.Last = value
		pcall(function()
			instance[props.Property] = value
		end)
	end
end

function Property.Exit(state, ctx)
	state.Last = nil
	if state.Instance and state.Instance.Parent then
		ctx:Restore(state.Instance, state.Props.Property)
	end
end

return Property
