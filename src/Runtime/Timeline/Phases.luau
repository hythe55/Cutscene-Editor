local Schema = require(script.Parent.Schema)
local Data = require(script.Parent.Data)

local Phases = {}

local RIG_APPLY = 40
local RENDER_PRIORITY = 70

local warned = {}

local function warnOnce(key, message)
	if not warned[key] then
		warned[key] = true
		warn(message)
	end
end

local function loadKind(kind)
	local tracks = script.Parent:FindFirstChild("Tracks")
	local module = tracks and tracks:FindFirstChild(kind)
	if not module or not module:IsA("ModuleScript") then
		warnOnce("missing" .. kind, `Timeline: no track module for kind "{kind}"; its clips are skipped`)
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok or type(result) ~= "table" then
		warnOnce("error" .. kind, `Timeline: track module "{kind}" failed to load: {result}`)
		return nil
	end
	return result
end

local function call(entry, name, ...)
	local fn = entry.Module[name]
	if not fn then
		return
	end
	local ok, err = pcall(fn, ...)
	if not ok and not entry.Failed then
		entry.Failed = true
		warn(`Timeline: {entry.Kind} clip "{entry.Name}" {name} failed: {err}`)
	end
end

local function newEntry(kind, name, module, state, props, track)
	return {
		Kind = kind,
		Name = name,
		Module = module,
		State = state,
		Props = props,
		Track = track,
		Start = props.Start,
		Duration = props.Duration,
		End = props.Start + props.Duration,
		Speed = props.Speed,
		Order = if track then track.Order else math.huge,
		Seekable = module.Seekable ~= false,
		Active = false,
		Suppressed = false,
	}
end

local function eachEntry(timeline, fn)
	for _, phase in timeline.Phases do
		for _, group in phase.Groups do
			for _, entry in group.Entries do
				fn(entry, group)
			end
		end
	end
end

function Phases.Module(timeline, kind)
	local module = timeline.Modules[kind]
	if module == nil then
		module = loadKind(kind) or false
		timeline.Modules[kind] = module
	end
	return module or nil
end

function Phases.Prepare(timeline)
	local ctx = timeline.Context
	local groups = {}
	local function add(kind, module, entry)
		local group = groups[kind]
		if not group then
			group = { Kind = kind, Module = module, Priority = module.Priority or 50, Entries = {} }
			groups[kind] = group
		end
		table.insert(group.Entries, entry)
	end
	local function prepare(kind, module, clip, props, track, label)
		local ok, state = pcall(module.Prepare, clip, props, track, ctx)
		if ok then
			add(kind, module, newEntry(kind, if clip then clip.Name else label, module, state, props, track))
		else
			warn(`Timeline: {kind} "{if clip then clip:GetFullName() else label}" failed to prepare: {state}`)
		end
	end
	for _, track in Data.Tracks(timeline.Folder) do
		if not track.Muted then
			if track.Kind == "Dialogue" then
				for _, clip in Data.Clips(track.Instance) do
					ctx:AddLine(Schema.Read(clip, "Dialogue"))
				end
			end
			local module = Phases.Module(timeline, track.Kind)
			if module then
				for _, clip in Data.Clips(track.Instance) do
					prepare(track.Kind, module, clip, Schema.Read(clip, track.Kind), track)
				end
			end
		end
	end
	for id, actor in timeline.Actors do
		if actor.Attributes.TalkJoints ~= "" and actor.Model then
			local module = Phases.Module(timeline, "Talk")
			if module then
				prepare("Talk", module, nil, { Start = 0, Duration = math.huge, Speed = 1, Actor = id }, nil, id)
			end
		end
	end
	local simulation = { Groups = {}, Rig = true }
	local render = { Groups = {} }
	for _, group in groups do
		table.sort(group.Entries, function(a, b)
			if a.Order ~= b.Order then
				return a.Order < b.Order
			end
			return a.Start < b.Start
		end)
		table.insert(if group.Priority < RENDER_PRIORITY then simulation.Groups else render.Groups, group)
	end
	for _, phase in { simulation, render } do
		table.sort(phase.Groups, function(a, b)
			return a.Priority < b.Priority
		end)
	end
	timeline.Phases = { simulation, render }
end

local function enter(timeline, entry)
	entry.Active = true
	call(entry, "Enter", entry.State, timeline.Context)
end

local function update(timeline, entry, t)
	local elapsed = t - entry.Start
	local alpha = if entry.Duration > 0 then math.clamp(elapsed / entry.Duration, 0, 1) else 1
	call(entry, "Update", entry.State, elapsed * entry.Speed, alpha, timeline.Context)
end

local function exit(timeline, entry)
	entry.Active = false
	call(entry, "Exit", entry.State, timeline.Context)
end

local function advance(timeline, entry, t, previous, seeking, inclusive)
	if t < entry.Start or (seeking and t == entry.Start) then
		entry.Suppressed = false
	end
	if t < entry.Start then
		return
	end
	if t < entry.End then
		if not entry.Active then
			if entry.Suppressed then
				return
			end
			if seeking and not entry.Seekable then
				entry.Suppressed = t > entry.Start
				return
			end
			enter(timeline, entry)
		end
		update(timeline, entry, t)
	elseif not seeking and previous and not entry.Active and not entry.Suppressed then
		if entry.Start > previous or (inclusive and entry.Start >= previous) then
			enter(timeline, entry)
			update(timeline, entry, entry.End)
			exit(timeline, entry)
		end
	end
end

local function beginRigs(timeline, t)
	local ctx = timeline.Context
	for _, rig in ctx.RigList do
		rig:Begin()
	end
	for id, actor in timeline.Actors do
		local idle = actor.Idle
		if idle and idle.Length > 0 and actor.Model then
			local rig = ctx:GetRig(id)
			if rig and rig.Mode == "Direct" then
				if not rig.Building then
					rig:Begin()
				end
				if actor.IdleRig ~= rig then
					actor.IdleRig = rig
					actor.IdleSet = function(key, cframe)
						rig:Set(key, cframe)
					end
				end
				idle:Sample(t % idle.Length, actor.IdleSet, idle:Skip(rig))
			end
		end
	end
end

local function applyRigs(timeline)
	for _, rig in timeline.Context.RigList do
		rig:Apply()
	end
end

function Phases.Process(timeline, phase, t, seeking)
	local ctx = timeline.Context
	local previous = phase.Previous
	ctx.Time = t
	ctx.Seeking = seeking
	ctx.DeltaTime = if previous and not seeking then math.max(t - previous, 0) else 0
	for _, group in phase.Groups do
		for _, entry in group.Entries do
			if entry.Active and (t < entry.Start or t >= entry.End or (seeking and not entry.Seekable)) then
				if seeking and not entry.Seekable then
					entry.Suppressed = t > entry.Start and t < entry.End
				end
				exit(timeline, entry)
			end
		end
	end
	if phase.Rig then
		beginRigs(timeline, t)
	end
	local applied = not phase.Rig
	for _, group in phase.Groups do
		if not applied and group.Priority >= RIG_APPLY then
			applied = true
			applyRigs(timeline)
		end
		local frame = group.Module.Frame
		if frame then
			local ok, err = pcall(frame, ctx)
			if not ok then
				warnOnce("frame" .. group.Kind .. tostring(err), `Timeline: {group.Kind} frame failed: {err}`)
			end
		end
		for _, entry in group.Entries do
			advance(timeline, entry, t, previous, seeking, phase.Inclusive)
		end
	end
	if not applied then
		applyRigs(timeline)
	end
	if phase.Rig then
		ctx:_flushHidden()
	end
	phase.Previous = t
	phase.Inclusive = false
	ctx.Seeking = false
end

function Phases.Halt(timeline, reason)
	local ctx = timeline.Context
	ctx.Time = timeline.TimePosition
	ctx.Seeking = false
	eachEntry(timeline, function(entry, group)
		if group.Module.Halt then
			call(entry, "Halt", entry.State, ctx, reason)
		end
	end)
end

function Phases.Pause(timeline)
	local position = timeline.TimePosition
	timeline.Context.Time = position
	eachEntry(timeline, function(entry, group)
		if not group.Module.HoldOnPause and entry.Active and not entry.Seekable then
			entry.Suppressed = position > entry.Start
			exit(timeline, entry)
		end
	end)
end

function Phases.ExitAll(timeline)
	local ctx = timeline.Context
	ctx.Time = timeline.TimePosition
	ctx.Seeking = false
	eachEntry(timeline, function(entry)
		entry.Suppressed = false
		if entry.Active then
			exit(timeline, entry)
		end
	end)
end

function Phases.DestroyAll(timeline)
	local ctx = timeline.Context
	eachEntry(timeline, function(entry)
		call(entry, "Destroy", entry.State, ctx)
	end)
end

return Phases
