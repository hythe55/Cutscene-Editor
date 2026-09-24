local Players = game:GetService("Players")

local Overlay = {}
Overlay.Priority = 80
Overlay.Seekable = true

local FAMILY = "rbxasset://fonts/families/Merriweather.json"
local TITLE_FONT = Font.new(FAMILY, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
local BODY_FONT = Font.new(FAMILY, Enum.FontWeight.Regular, Enum.FontStyle.Italic)
local CLOCK_FONT = Font.new(FAMILY, Enum.FontWeight.Bold, Enum.FontStyle.Italic)
local LIGHT_TEXT = Color3.fromRGB(250, 243, 226)
local DARK_TEXT = Color3.fromRGB(34, 30, 36)
local ACCENT = Color3.fromRGB(242, 196, 104)
local FACE = Color3.fromRGB(252, 246, 232)
local FACE_EDGE = Color3.fromRGB(232, 220, 196)
local RIM = Color3.fromRGB(196, 146, 72)
local INK = Color3.fromRGB(46, 38, 40)
local HAND_RED = Color3.fromRGB(214, 70, 64)
local TYPE_RATE = 16
local BASE_DISPLAY_ORDER = 50
local MAX_ORDER = 49

local function clamp01(x)
	return math.clamp(x, 0, 1)
end

local function smooth(x)
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end

local function easeOutCubic(x)
	x = clamp01(x)
	return 1 - (1 - x) ^ 3
end

local function easeOutBack(x)
	x = clamp01(x)
	local c1 = 1.4
	return 1 + (c1 + 1) * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function new(className, parent, properties)
	local instance = Instance.new(className)
	for key, value in properties do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

local function frame(parent, properties)
	properties.BorderSizePixel = 0
	if properties.BackgroundTransparency == nil then
		properties.BackgroundTransparency = 1
	end
	return new("Frame", parent, properties)
end

local function round(parent)
	new("UICorner", parent, { CornerRadius = UDim.new(1, 0) })
	return parent
end

local function label(parent, properties, maxSize, minSize)
	properties.BackgroundTransparency = 1
	properties.TextScaled = true
	properties.TextWrapped = true
	local text = new("TextLabel", parent, properties)
	new("UITextSizeConstraint", text, { MaxTextSize = maxSize, MinTextSize = minSize })
	return text
end

local function textColorFor(color)
	local luminance = 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
	return if luminance > 0.6 then DARK_TEXT else LIGHT_TEXT
end

local function guiParentOf(ctx)
	if ctx.GuiParent then
		return ctx.GuiParent
	end
	local player = Players.LocalPlayer
	return player and player:FindFirstChildOfClass("PlayerGui") or game:GetService("CoreGui")
end

local function pivot(parent, zIndex)
	return frame(parent, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = zIndex,
	})
end

local function hand(parent, width, length, tail, color, zIndex)
	local holder = pivot(parent, zIndex)
	round(frame(holder, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.5 + tail),
		Size = UDim2.fromScale(width, length + tail),
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		ZIndex = zIndex,
	}))
	return holder
end

local function buildTitle(state, root, textColor)
	local props = state.Props
	local group = new("CanvasGroup", root, {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	local holder = frame(group, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromScale(0.82, 0.34),
	})
	local scale = new("UIScale", holder, { Scale = 0.94 })
	local title = label(holder, {
		Size = UDim2.fromScale(1, 0.52),
		Text = props.Text or "",
		FontFace = TITLE_FONT,
		TextColor3 = textColor,
	}, 110, 28)
	new("UIStroke", title, { Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.6 })
	local divider = round(frame(holder, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.new(0, 0, 0, 4),
		BackgroundColor3 = ACCENT,
		BackgroundTransparency = 0,
	}))
	local subText = label(holder, {
		Position = UDim2.fromScale(0, 0.68),
		Size = UDim2.fromScale(1, 0.26),
		Text = props.SubText or "",
		FontFace = BODY_FONT,
		TextColor3 = textColor,
	}, 58, 20)
	new("UIStroke", subText, { Color = Color3.new(0, 0, 0), Thickness = 1.5, Transparency = 0.7 })
	state.Parts = { Group = group, Scale = scale, Divider = divider, SubText = subText }
end

local function buildClock(state, root, textColor)
	local props = state.Props
	local group = new("CanvasGroup", root, {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	local holder = frame(group, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(0.4, 0.4),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
	})
	local scale = new("UIScale", holder, { Scale = 0.85 })
	for index, size in { 1.4, 1.3, 1.21, 1.13, 1.06 } do
		round(frame(holder, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(size, size),
			BackgroundColor3 = ACCENT,
			BackgroundTransparency = 0.985 - index * 0.012,
			ZIndex = 1,
		}))
	end
	local rim = round(frame(holder, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = RIM,
		BackgroundTransparency = 0,
		ZIndex = 2,
	}))
	new("UIGradient", rim, {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(236, 192, 112), Color3.fromRGB(150, 102, 44)),
	})
	local face = round(frame(holder, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.88, 0.88),
		BackgroundColor3 = FACE,
		BackgroundTransparency = 0,
		ZIndex = 3,
	}))
	new("UIGradient", face, { Rotation = 90, Color = ColorSequence.new(FACE, FACE_EDGE) })
	for index = 0, 59 do
		local major = index % 5 == 0
		local tick = pivot(face, 4)
		tick.Rotation = index * 6
		round(frame(tick, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.035),
			Size = if major then UDim2.fromScale(0.03, 0.085) else UDim2.fromScale(0.012, 0.035),
			BackgroundColor3 = INK,
			BackgroundTransparency = if major then 0 else 0.35,
			ZIndex = 4,
		}))
	end
	for index, numeral in { "12", "3", "6", "9" } do
		local angle = (index - 1) * math.pi / 2
		label(face, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + math.sin(angle) * 0.3, 0.5 - math.cos(angle) * 0.3),
			Size = UDim2.fromScale(0.16, 0.13),
			Text = numeral,
			FontFace = TITLE_FONT,
			TextColor3 = INK,
			ZIndex = 4,
		}, 200, 8)
	end
	local hour = hand(face, 0.055, 0.24, 0.06, INK, 5)
	local minute = hand(face, 0.035, 0.36, 0.07, INK, 6)
	local second = hand(face, 0.014, 0.4, 0.1, HAND_RED, 7)
	round(frame(face, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.085, 0.085),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0,
		ZIndex = 8,
	}))
	round(frame(face, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.04, 0.04),
		BackgroundColor3 = HAND_RED,
		BackgroundTransparency = 0,
		ZIndex = 9,
	}))
	local caption = label(group, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.67),
		Size = UDim2.fromScale(0.86, 0.1),
		Text = props.Text or "",
		FontFace = CLOCK_FONT,
		TextColor3 = textColor,
		MaxVisibleGraphemes = 0,
		ZIndex = 3,
	}, 92, 30)
	local subText = label(group, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.79),
		Size = UDim2.fromScale(0.7, 0.055),
		Text = props.SubText or "",
		FontFace = BODY_FONT,
		TextColor3 = textColor,
		TextTransparency = 1,
		ZIndex = 3,
	}, 52, 18)
	state.Parts = {
		Group = group,
		Scale = scale,
		Hour = hour,
		Minute = minute,
		Second = second,
		Caption = caption,
		SubText = subText,
	}
end

local function timing(state, alpha)
	local props = state.Props
	local duration = props.Duration or 0
	local elapsed = alpha * duration
	local fadeIn, fadeOut = props.FadeIn or 0, props.FadeOut or 0
	local fadeInAmount = if fadeIn > 0 then clamp01(elapsed / fadeIn) else 1
	local fadeOutAmount = if fadeOut > 0 then clamp01((duration - elapsed) / fadeOut) else 1
	return elapsed, fadeIn, fadeOut, smooth(math.min(fadeInAmount, fadeOutAmount)), smooth(fadeOutAmount)
end

local function renderTitle(parts, localTime, fadeIn, outAmount)
	local start = fadeIn * 0.45
	local appear = smooth((localTime - start) / 0.7)
	parts.Group.GroupTransparency = 1 - math.min(appear, outAmount)
	parts.Scale.Scale = 0.94 + 0.06 * easeOutCubic((localTime - start) / 1.1)
	local grow = easeOutCubic((localTime - start - 0.2) / 0.9)
	parts.Divider.Size = UDim2.new(0.22 * grow, 0, 0, 4)
	parts.Divider.Visible = grow > 0
	parts.SubText.TextTransparency = 1 - smooth((localTime - start - 0.45) / 0.7)
end

local function renderClock(state, parts, localTime, fadeIn, fadeOut, outAmount)
	local props = state.Props
	local total = (props.Duration or 0) * (props.Speed or 1)
	local start = fadeIn * 0.3
	parts.Group.GroupTransparency = 1 - math.min(smooth((localTime - start) / 0.5), outAmount)
	parts.Scale.Scale = 0.85 + 0.15 * easeOutBack((localTime - start) / 0.8)
	local spinEnd = math.max(total - fadeOut * 0.6, start + 0.5)
	local spinLength = spinEnd - start
	local progress = clamp01((localTime - start) / spinLength)
	local eased = (1 - math.cos(math.pi * progress)) / 2
	local turns = math.max(1, math.floor(spinLength / 1.4 + 0.5))
	parts.Minute.Rotation = eased * turns * 360
	parts.Hour.Rotation = 60 + eased * turns * 30
	parts.Second.Rotation = eased * turns * 360 * 3 + 90
	local typeStart = start + 0.45
	local length = utf8.len(parts.Caption.Text) or #parts.Caption.Text
	local typed = math.clamp(math.floor((localTime - typeStart) * TYPE_RATE), 0, length)
	parts.Caption.MaxVisibleGraphemes = if typed >= length then -1 else typed
	local typedEnd = typeStart + length / TYPE_RATE
	parts.SubText.TextTransparency = 1 - smooth((localTime - typedEnd - 0.2) / 0.6)
end

local function destroyGui(state)
	if state.Gui then
		state.Gui:Destroy()
		state.Gui = nil
		state.Parts = nil
	end
end

function Overlay.Prepare(clip, props, track, ctx)
	local order = track and tonumber(track.Order) or 0
	local state = {
		Clip = clip,
		Props = props,
		DisplayOrder = BASE_DISPLAY_ORDER + math.clamp(math.floor(order), 0, MAX_ORDER),
	}
	if ctx then
		ctx:OnCleanup(function()
			destroyGui(state)
		end)
	end
	return state
end

function Overlay.Build(state, parent)
	destroyGui(state)
	local props = state.Props
	local color = props.Color or Color3.new(0, 0, 0)
	local gui = new("ScreenGui", nil, {
		Name = "TimelineOverlay",
		Archivable = false,
		DisplayOrder = state.DisplayOrder or BASE_DISPLAY_ORDER,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.None,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local backdrop = frame(gui, {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		ZIndex = 1,
	})
	state.Backdrop = backdrop
	local style = props.Style or "Fade"
	if style == "Title" then
		buildTitle(state, gui, textColorFor(color))
	elseif style == "Clock" then
		buildClock(state, gui, textColorFor(color))
	end
	state.Style = style
	gui.Parent = parent
	state.Gui = gui
	return gui
end

function Overlay.Enter(state, ctx)
	Overlay.Build(state, guiParentOf(ctx))
	Overlay.Update(state, 0, 0, ctx)
end

function Overlay.Update(state, localTime, alpha, _ctx)
	if not state.Gui then
		return
	end
	local _, fadeIn, fadeOut, amount, outAmount = timing(state, alpha)
	state.Backdrop.BackgroundTransparency = 1 - clamp01(state.Props.Opacity or 1) * amount
	local parts = state.Parts
	if state.Style == "Title" then
		renderTitle(parts, localTime, fadeIn, outAmount)
	elseif state.Style == "Clock" then
		renderClock(state, parts, localTime, fadeIn, fadeOut, outAmount)
	end
end

function Overlay.Exit(state, _ctx)
	destroyGui(state)
end

function Overlay.Destroy(state, _ctx)
	destroyGui(state)
end

return Overlay
