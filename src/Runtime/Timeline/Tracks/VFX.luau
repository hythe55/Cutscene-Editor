local Copy = require(script.Parent.Parent.Util.Copy)

local VFX = {}
VFX.Priority = 90
VFX.Seekable = false

local MAX_RATE = 1000

local function named(value)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function isToggle(instance)
	return instance:IsA("Beam") or instance:IsA("Trail") or instance:IsA("Light") or instance:IsA("Fire")
		or instance:IsA("Smoke") or instance:IsA("Sparkles")
end

local function templateOf(clip)
	for _, child in clip:GetChildren() do
		if child:IsA("Attachment") or child:IsA("BasePart") or child:IsA("Model") then
			return child
		end
	end
	return nil
end

local function prepareClone(clone)
	local parts = if clone:IsA("BasePart") then { clone } else {}
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	for _, part in parts do
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
	end
	local emitters, toggles = {}, {}
	local all = clone:GetDescendants()
	table.insert(all, clone)
	for _, instance in all do
		if instance:IsA("ParticleEmitter") then
			instance.Enabled = false
			local count, delay, duration = instance:GetAttribute("EmitCount"), instance:GetAttribute("EmitDelay"), instance:GetAttribute("EmitDuration")
			table.insert(emitters, {
				Instance = instance,
				Rate = instance.Rate,
				Count = if type(count) == "number" then count else nil,
				Delay = if type(delay) == "number" then delay else 0,
				Duration = if type(duration) == "number" then duration else nil,
				Emitted = false,
				On = false,
			})
		elseif isToggle(instance) then
			(instance :: any).Enabled = false
			table.insert(toggles, instance)
		end
	end
	return emitters, toggles
end

local function longestLifetime(emitters)
	local longest = 0
	for _, entry in emitters do
		local emitter = entry.Instance
		longest = math.max(longest, emitter.Lifetime.Max / math.max(emitter.TimeScale, 0.01))
	end
	return longest
end

local function targetCFrame(state, ctx)
	local props = state.Props
	local offset = props.Offset or CFrame.identity
	local anchor = named(props.Anchor)
	if anchor then
		local cframe = ctx:GetJointCFrame(anchor, named(props.AnchorJoint))
		if typeof(cframe) == "CFrame" then
			state.LastAnchor = cframe
		end
		return state.LastAnchor and state.LastAnchor * offset
	end
	if state.Rest and offset == CFrame.identity then
		return state.Rest
	end
	return offset
end

local function follow(state, ctx)
	local cframe = targetCFrame(state, ctx)
	if not cframe then
		return
	end
	if state.Proxy then
		state.Proxy.CFrame = cframe
	elseif state.Clone:IsA("Model") then
		state.Clone:PivotTo(cframe)
	else
		state.Clone.CFrame = cframe
	end
end

local function setEmitter(entry, on)
	if entry.On == on then
		return
	end
	entry.On = on
	entry.Instance.Enabled = on and entry.Rate <= MAX_RATE
end

local function burstCount(entry, scale)
	local count = entry.Count or math.clamp(math.round(entry.Rate / 5), 1, 20)
	return math.max(math.round(count * scale), 0)
end

local function stepEmitters(state, elapsed)
	local props = state.Props
	local scale = props.EmitScale or 1
	local continuous = props.Mode == "Continuous"
	for _, entry in state.Emitters do
		local started = elapsed >= entry.Delay
		if continuous and entry.Rate <= MAX_RATE then
			entry.Instance.Rate = math.min(entry.Rate * scale, MAX_RATE)
			setEmitter(entry, started)
		else
			if started and not entry.Emitted then
				entry.Emitted = true
				local count = burstCount(entry, scale)
				if count > 0 then
					entry.Instance:Emit(count)
				end
			end
			if entry.Duration then
				setEmitter(entry, started and elapsed < entry.Delay + entry.Duration)
			end
		end
	end
end

local function finish(state, immediate)
	state.Waiting = false
	local clone, proxy = state.Clone, state.Proxy
	state.Clone, state.Proxy = nil, nil
	if not clone then
		return
	end
	for _, entry in state.Emitters do
		entry.Instance.Enabled = false
	end
	for _, toggle in state.Toggles do
		(toggle :: any).Enabled = false
	end
	local root = proxy or clone
	local linger = longestLifetime(state.Emitters)
	if immediate or linger <= 0 then
		root:Destroy()
	else
		state.Lingering[root] = true
		task.delay(linger, function()
			state.Lingering[root] = nil
			root:Destroy()
		end)
	end
end

local function spawnClone(state, ctx)
	local template = state.Template
	if not targetCFrame(state, ctx) then
		return false
	end
	local clone = Copy.Clone(template)
	if not clone then
		return false
	end
	clone.Archivable = false
	state.Emitters, state.Toggles = prepareClone(clone)
	state.Rest = nil
	if clone:IsA("Attachment") then
		local proxy = Instance.new("Part")
		proxy.Name = "TimelineVFX"
		proxy.Archivable = false
		proxy.Anchored = true
		proxy.CanCollide = false
		proxy.CanTouch = false
		proxy.CanQuery = false
		proxy.CastShadow = false
		proxy.Transparency = 1
		proxy.Size = Vector3.one * 0.2
		clone.Parent = proxy
		state.Proxy = proxy
	elseif clone:IsA("Model") then
		state.Rest = template:GetPivot()
	else
		state.Rest = template.CFrame
	end
	state.Clone = clone
	follow(state, ctx)
	local root = state.Proxy or clone
	root.Parent = ctx.Container or workspace
	for _, toggle in state.Toggles do
		(toggle :: any).Enabled = true
	end
	return true
end

function VFX.Prepare(clip, props, _track, ctx)
	local state = {
		Clip = clip,
		Props = props,
		Template = templateOf(clip),
		Emitters = {},
		Toggles = {},
		Lingering = {},
		Waiting = false,
	}
	if ctx then
		ctx:OnCleanup(function()
			VFX.Destroy(state, ctx)
		end)
	end
	return state
end

function VFX.Enter(state, ctx)
	finish(state, true)
	if not state.Template then
		return
	end
	local start = state.Props.Start or 0
	if spawnClone(state, ctx) then
		stepEmitters(state, math.max((ctx.Time or start) - start, 0))
	else
		state.Waiting = true
	end
end

function VFX.Update(state, _localTime, alpha, ctx)
	local elapsed = alpha * (state.Props.Duration or 0)
	if state.Waiting then
		if not spawnClone(state, ctx) then
			return
		end
		state.Waiting = false
	end
	if not state.Clone then
		return
	end
	follow(state, ctx)
	stepEmitters(state, elapsed)
end

function VFX.Exit(state, ctx)
	finish(state, ctx.Seeking)
end

local function clear(state)
	finish(state, true)
	for root in state.Lingering do
		root:Destroy()
	end
	table.clear(state.Lingering)
end

function VFX.Halt(state, _ctx)
	clear(state)
end

function VFX.Destroy(state, _ctx)
	clear(state)
end

return VFX
