local Lines = require(script.Parent.Parent.Lines)

local Dialogue = {}
Dialogue.Priority = 95
Dialogue.Seekable = true

local CHAIN_GRACE = 0.25
local LATE_ENTRY = 0.25
local DEFAULT_SPEED = 40
local EXTRA_PREFIX = "X_"

local EMPTY = table.freeze({})

local owners = setmetatable({}, { __mode = "k" })
local speakers = setmetatable({}, { __mode = "k" })
local waiting = setmetatable({}, { __mode = "k" })
local lines = setmetatable({}, { __mode = "k" })

local function keyOf(ctx)
	return ctx.Timeline or ctx
end

local function listOf(ctx)
	return lines[keyOf(ctx)] or EMPTY
end

local function read(object, field)
	local ok, value = pcall(function()
		return object[field]
	end)
	return if ok then value else nil
end

local function extrasOf(clip)
	local extra = {}
	if typeof(clip) ~= "Instance" then
		return extra
	end
	for name, value in clip:GetAttributes() do
		if #name > #EXTRA_PREFIX and string.sub(name, 1, #EXTRA_PREFIX) == EXTRA_PREFIX then
			extra[string.sub(name, #EXTRA_PREFIX + 1)] = value
		end
	end
	return extra
end

local function graphemeCount(text)
	local count = 0
	local ok = pcall(function()
		for _ in utf8.graphemes(text) do
			count += 1
		end
	end)
	return if ok then count else utf8.len(text) or #text
end

local function speakerOf(state, ctx)
	return Lines.Speaker(ctx, state.Props.Speaker)
end

local function visibleCount(state, box)
	local elapsed = state.LocalTime or 0
	local typing = state.Typing
	if typing.Method then
		local ok, count = pcall(typing.Method, box, state.Line, elapsed)
		if ok and type(count) == "number" and count == count then
			return math.clamp(math.floor(count), 0, state.Count)
		end
	end
	local typed = elapsed - typing.Delay
	if typed < 0 then
		return 0
	end
	return math.min(math.floor(typed * (state.Line.TypeSpeed or DEFAULT_SPEED)) + 1, state.Count)
end

local function setTalking(state, ctx, talking)
	if state.Talking == talking or speakers[keyOf(ctx)] ~= state then
		return
	end
	state.Talking = talking
	if ctx.SetActiveSpeaker then
		ctx:SetActiveSpeaker(state.ActorId, talking)
	end
end

local function closeBox(state)
	state.Pending = nil
	local box = state.Box
	if box and owners[box] == state then
		owners[box] = nil
		state.Box = nil
		box:Close()
	end
end

local function hold(state, ctx)
	local box = state.Box
	if not box or owners[box] ~= state then
		return
	end
	local timelineKey = keyOf(ctx)
	local token = {}
	state.Pending = token
	waiting[timelineKey] = state
	task.delay(math.max(state.Gap or Lines.ChainGap, 0) + CHAIN_GRACE, function()
		if state.Pending == token then
			if waiting[timelineKey] == state then
				waiting[timelineKey] = nil
			end
			closeBox(state)
		end
	end)
end

local function release(state, ctx, close)
	local timelineKey = keyOf(ctx)
	if speakers[timelineKey] == state then
		speakers[timelineKey] = nil
		if ctx.SetActiveSpeaker then
			ctx:SetActiveSpeaker(nil)
		end
	end
	state.Handle = nil
	if close then
		if waiting[timelineKey] == state then
			waiting[timelineKey] = nil
		end
		closeBox(state)
	end
end

local function localTimeOf(state, ctx)
	return math.max(((ctx.Time or state.Start) - state.Start) * (state.Props.Speed or 1), 0)
end

local function buildLine(state, ctx, box)
	local props = state.Props
	local speaker, actorId = speakerOf(state, ctx)
	local typeSpeed = props.TypeSpeed
	state.ActorId = actorId
	state.Line = {
		Speaker = speaker,
		Text = Lines.Substitute(props.Text or "", ctx),
		TypeSpeed = if typeSpeed and typeSpeed > 0 then typeSpeed else nil,
		Mood = props.Mood or "Normal",
		Blips = props.Blips ~= false,
		Extra = table.clone(state.Extra),
	}
	state.Count = graphemeCount(state.Line.Text)
	local method = box and read(box, "VisibleCharacters")
	local delay = box and read(box, "StartDelay")
	state.Typing = {
		Method = if type(method) == "function" then method else nil,
		Delay = if type(delay) == "number" then delay else 0,
	}
end

local function predict(state, ctx)
	local line = state.Line
	if line.StartDelay ~= nil or line.PreviousSpeaker ~= nil then
		return
	end
	local before = Lines.Previous(listOf(ctx), state)
	if before then
		line.PreviousSpeaker = (speakerOf(before, ctx))
	end
end

local function render(state, box)
	state.Mode = "Render"
	state.Handle = nil
	state.Rendered = visibleCount(state, box)
	box:Render(state.Line, state.Rendered)
end

local function mayClaim(state, box, ctx, entering)
	if ctx.Stopping then
		return false
	end
	local owner = owners[box]
	if owner == nil or owner == state then
		return true
	end
	if not table.find(listOf(ctx), owner) then
		return entering
	end
	local t = ctx.Time or state.Start
	if owner.Pending or t < owner.Start or t >= owner.Finish then
		return true
	end
	return if entering then state.Start >= owner.Start else state.Start > owner.Start
end

local function own(state, ctx, box)
	local previous = owners[box]
	if previous and previous ~= state then
		previous.Pending = nil
	end
	waiting[keyOf(ctx)] = nil
	owners[box] = state
	state.Box = box
	state.Pending = nil
	box:Open()
end

local function claim(state, ctx, box)
	speakers[keyOf(ctx)] = state
	state.Talking = nil
	own(state, ctx, box)
end

local function holdAt(state, ctx)
	local box = ctx:Dialogue()
	if not box then
		return
	end
	if not state.Line then
		buildLine(state, ctx, box)
	end
	own(state, ctx, box)
	state.Pending = {}
	waiting[keyOf(ctx)] = state
	state.LocalTime = localTimeOf(state, ctx)
	predict(state, ctx)
	render(state, box)
end

function Dialogue.Prepare(clip, props, _track, ctx)
	local start = props.Start or 0
	local state = {
		Clip = clip,
		Props = props,
		Start = start,
		Finish = start + (props.Duration or 0),
		KeepOpen = false,
		Extra = extrasOf(clip),
	}
	if ctx then
		local timelineKey = keyOf(ctx)
		lines[timelineKey] = lines[timelineKey] or {}
		table.insert(lines[timelineKey], state)
		Lines.Link(lines[timelineKey])
	end
	return state
end

function Dialogue.Frame(ctx)
	local timelineKey = keyOf(ctx)
	local list = listOf(ctx)
	local t = ctx.Time
	if ctx.Seeking and t and not ctx.Stopping then
		local held = Lines.HeldAt(list, t)
		if held then
			holdAt(held, ctx)
			return
		end
	end
	local state = waiting[timelineKey]
	if not state then
		return
	end
	local box = state.Box
	if not box or owners[box] ~= state or not state.Pending then
		waiting[timelineKey] = nil
		return
	end
	t = t or state.Finish
	local away = ctx.Seeking or t < state.Finish - 1e-3 or t > state.Finish + (state.Gap or Lines.ChainGap) + 1e-3
	if away and not Lines.Covered(list, t) then
		waiting[timelineKey] = nil
		closeBox(state)
	elseif not away and state.Mode == "Render" then
		state.LocalTime = localTimeOf(state, ctx)
		local count = visibleCount(state, box)
		if count ~= state.Rendered then
			state.Rendered = count
			box:Render(state.Line, count)
		end
	end
end

function Dialogue.Enter(state, ctx)
	local box = ctx:Dialogue()
	buildLine(state, ctx, box)
	state.Rendered = nil
	state.Handle = nil
	state.Mode = "Render"
	state.Pending = nil
	state.LocalTime = localTimeOf(state, ctx)
	if ctx.Stopping or (box and not mayClaim(state, box, ctx, true)) then
		return
	end
	if not box then
		speakers[keyOf(ctx)] = state
		state.Talking = nil
		setTalking(state, ctx, true)
		return
	end
	claim(state, ctx, box)
	setTalking(state, ctx, true)
	if ctx.Seeking or state.LocalTime > LATE_ENTRY then
		predict(state, ctx)
		render(state, box)
	else
		state.Mode = "Say"
		state.Handle = box:Say(state.Line)
		local actual = state.Handle and read(state.Handle, "StartDelay")
		if type(actual) == "number" then
			state.Line.StartDelay = actual
			state.Typing.Delay = actual
		end
	end
end

function Dialogue.Update(state, localTime, _alpha, ctx)
	state.LocalTime = localTime
	if not state.Line then
		return
	end
	local box = state.Box
	local owned = box ~= nil and owners[box] == state
	if not owned then
		box = box or ctx:Dialogue()
		if box and mayClaim(state, box, ctx, false) then
			claim(state, ctx, box)
			predict(state, ctx)
			state.Mode = "Render"
			state.Handle = nil
			state.Rendered = nil
			owned = true
		end
	end
	if ctx.Seeking then
		state.Mode = "Render"
	end
	if owned and state.Mode == "Say" then
		setTalking(state, ctx, not (state.Handle and state.Handle.Done))
		return
	end
	local count = visibleCount(state, box)
	if owned and count ~= state.Rendered then
		state.Rendered = count
		box:Render(state.Line, count)
	end
	setTalking(state, ctx, count < state.Count)
end

function Dialogue.Halt(state, ctx, reason)
	local box = state.Box
	if not box or owners[box] ~= state then
		return
	end
	if reason ~= "Pause" then
		release(state, ctx, true)
		return
	end
	if state.Pending then
		state.Pending = {}
		waiting[keyOf(ctx)] = state
	end
	if state.Mode == "Say" or state.Pending then
		state.LocalTime = localTimeOf(state, ctx)
		render(state, box)
	end
end

function Dialogue.Exit(state, ctx)
	local t = ctx.Time
	if ctx.Seeking and state.KeepOpen and t and t >= state.Finish and t < state.Next.Start then
		release(state, ctx, false)
		return
	end
	local keep = state.KeepOpen and ctx.Playing == true and not ctx.Seeking
	release(state, ctx, not keep)
	if keep then
		hold(state, ctx)
	end
end

function Dialogue.Destroy(state, ctx)
	release(state, ctx, true)
	local list = lines[keyOf(ctx)]
	local index = list and table.find(list, state)
	if index then
		table.remove(list, index)
	end
end

return Dialogue
