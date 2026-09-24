local PostFX = {}
PostFX.Priority = 75
PostFX.Seekable = true

local WHITE = Color3.new(1, 1, 1)

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
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
	return smooth(amount)
end

local function destroyEffects(state)
	for _, effect in state.Effects do
		effect:Destroy()
	end
	table.clear(state.Effects)
end

function PostFX.Prepare(clip, props, _track, ctx)
	local state = {
		Clip = clip,
		Props = props,
		Effects = {},
	}
	if ctx then
		ctx:OnCleanup(function()
			destroyEffects(state)
		end)
	end
	return state
end

function PostFX.Enter(state, ctx)
	destroyEffects(state)
	local camera = ctx.Camera or workspace.CurrentCamera
	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "TimelinePostFX"
	correction.Archivable = false
	correction.Parent = camera
	state.Effects.Correction = correction
	if (state.Props.Blur or 0) > 0 then
		local blur = Instance.new("BlurEffect")
		blur.Name = "TimelinePostFX"
		blur.Archivable = false
		blur.Size = 0
		blur.Parent = camera
		state.Effects.Blur = blur
	end
	PostFX.Update(state, 0, 0, ctx)
end

function PostFX.Update(state, _localTime, alpha, _ctx)
	local correction = state.Effects.Correction
	if not correction then
		return
	end
	local props = state.Props
	local amount = envelope(props, alpha)
	correction.Saturation = (props.Saturation or 0) * amount
	correction.Contrast = (props.Contrast or 0) * amount
	correction.Brightness = (props.Brightness or 0) * amount
	correction.TintColor = WHITE:Lerp(props.TintColor or WHITE, amount)
	local blur = state.Effects.Blur
	if blur then
		blur.Size = (props.Blur or 0) * amount
	end
end

function PostFX.Exit(state, _ctx)
	destroyEffects(state)
end

function PostFX.Destroy(state, _ctx)
	destroyEffects(state)
end

return PostFX
