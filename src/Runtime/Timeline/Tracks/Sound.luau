local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")

local Copy = require(script.Parent.Parent.Util.Copy)

local Sound = {}
Sound.Priority = 85
Sound.Seekable = false

local RESYNC = 0.3

local function named(value)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function envelope(props, alpha)
	local duration = props.Duration or 0
	local elapsed = alpha * duration
	local fadeIn, fadeOut = props.FadeIn or 0, props.FadeOut or 0
	local amount = 1
	if fadeIn > 0 then
		amount = math.min(amount, elapsed / fadeIn)
	end
	if fadeOut > 0 then
		amount = math.min(amount, (duration - elapsed) / fadeOut)
	end
	return math.clamp(amount, 0, 1)
end

local function new(className, parent, properties)
	local instance = Instance.new(className)
	instance.Archivable = false
	for key, value in properties or {} do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

local function wire(source, target, parent)
	return new("Wire", parent, { SourceInstance = source, TargetInstance = target })
end

local function soundGroupOf(state)
	local sounds = workspace:FindFirstChild("Sounds")
	if not sounds then
		return nil
	end
	local name = state.Clip:GetAttribute("SoundGroup") or state.Template:GetAttribute("SoundGroup")
	if type(name) ~= "string" or name == "" then
		if state.Template.SoundGroup then
			return nil
		end
		name = "SFX"
	end
	local group = sounds:FindFirstChild(name)
	if group and group:IsA("SoundGroup") then
		return group
	end
	return nil
end

local function containerOf(ctx)
	return ctx.Container or workspace
end

local function anchorCFrame(state, ctx)
	local cframe = ctx:GetJointCFrame(state.Anchor, named(state.Props.AnchorJoint))
	if typeof(cframe) == "CFrame" then
		state.LastAnchor = cframe
		return cframe
	end
	return state.LastAnchor
end

local function makeProxy(state, ctx, cframe)
	local part = new("Part", containerOf(ctx), {
		Name = "TimelineSoundProxy",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		Size = Vector3.one * 0.2,
		CFrame = cframe,
	})
	state.Proxy = part
	state.Attachment = new("Attachment", part)
end

local function follow(state, ctx)
	if not state.Proxy then
		return
	end
	local cframe = anchorCFrame(state, ctx)
	if cframe and state.Proxy.CFrame ~= cframe then
		state.Proxy.CFrame = cframe
	end
end

local function startPosition(state, ctx)
	local props = state.Props
	local start = props.Start or 0
	local localTime = math.max(((ctx.Time or start) - start) * (props.Speed or 1), 0)
	return (props.StartOffset or 0) + localTime * state.Template.PlaybackSpeed
end

local function enterGame(state, ctx)
	local sound = Copy.Clone(state.Template)
	if not sound then
		return
	end
	sound.Archivable = false
	sound.PlaybackSpeed = state.Template.PlaybackSpeed * (state.Props.Speed or 1)
	sound.Volume = 0
	local group = soundGroupOf(state)
	if group then
		sound.SoundGroup = group
	end
	sound.Parent = state.Attachment or SoundService
	sound.TimePosition = startPosition(state, ctx)
	sound:Play()
	state.Sound = sound
end

local function enterPreview(state, ctx)
	local template = state.Template
	local player = new("AudioPlayer", containerOf(ctx), {
		Name = "TimelineSoundPreview",
		Asset = template.SoundId,
		Volume = 0,
		Looping = template.Looped,
		PlaybackSpeed = template.PlaybackSpeed * (state.Props.Speed or 1),
	})
	state.Player = player
	local output = new("AudioDeviceOutput", player)
	if state.Attachment then
		local group = "TimelineSound" .. HttpService:GenerateGUID(false)
		local emitter = new("AudioEmitter", state.Attachment, { AudioInteractionGroup = group })
		local listener = new("AudioListener", ctx.Camera or workspace.CurrentCamera, { AudioInteractionGroup = group })
		state.Listener = listener
		wire(player, emitter, player)
		wire(listener, output, player)
	else
		wire(player, output, player)
	end
	player.TimePosition = startPosition(state, ctx)
	player:Play()
end

local function cleanup(state)
	if state.Sound then
		state.Sound:Stop()
		state.Sound:Destroy()
		state.Sound = nil
	end
	if state.Player then
		state.Player:Stop()
		state.Player:Destroy()
		state.Player = nil
	end
	if state.Listener then
		state.Listener:Destroy()
		state.Listener = nil
	end
	if state.Proxy then
		state.Proxy:Destroy()
		state.Proxy = nil
		state.Attachment = nil
	end
end

function Sound.Prepare(clip, props, _track, ctx)
	local state = {
		Clip = clip,
		Props = props,
		Template = clip:FindFirstChildWhichIsA("Sound"),
		Anchor = named(props.Anchor),
	}
	if ctx and state.Template then
		table.insert(ctx:Registry("SoundTemplates"), state.Template)
	end
	if ctx then
		ctx:OnCleanup(function()
			cleanup(state)
		end)
	end
	return state
end

function Sound.Warm(ctx)
	return table.clone(ctx:Registry("SoundTemplates"))
end

function Sound.Enter(state, ctx)
	cleanup(state)
	state.Synced = false
	if not state.Template then
		return
	end
	if state.Anchor then
		local cframe = anchorCFrame(state, ctx)
		if cframe then
			makeProxy(state, ctx, cframe)
		end
	end
	if ctx.Preview then
		enterPreview(state, ctx)
	else
		enterGame(state, ctx)
	end
end

function Sound.Update(state, localTime, alpha, ctx)
	follow(state, ctx)
	local media = state.Sound or state.Player
	if not media then
		return
	end
	local template = state.Template
	media.Volume = template.Volume * envelope(state.Props, alpha)
	local length = media.TimeLength
	if ctx.Seeking or length <= 0 then
		state.Synced = false
		return
	end
	local expected = (state.Props.StartOffset or 0) + localTime * template.PlaybackSpeed
	if template.Looped then
		expected %= length
	elseif expected >= length then
		return
	end
	if not state.Synced or math.abs(media.TimePosition - expected) > RESYNC then
		state.Synced = true
		media.TimePosition = expected
	end
end

function Sound.Exit(state, _ctx)
	cleanup(state)
end

function Sound.Halt(state, _ctx)
	cleanup(state)
end

function Sound.Destroy(state, _ctx)
	cleanup(state)
end

return Sound
