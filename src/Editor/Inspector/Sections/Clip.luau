local Layout = require(script.Parent.Parent.Layout)
local Fields = require(script.Parent.Parent.Fields)
local Context = require(script.Parent.Parent.Context)
local Ripple = require(script.Parent.Parent.Parent.ScriptPanel.Ripple)

local Clip = {}

local STRETCH = { Camera = true, Move = true, Animation = true }
local HANDLED = {
	Dialogue = { Speaker = true, Text = true, TypeSpeed = true, Blips = true, Mood = true },
	Animation = { AnimationId = true, ExportedHash = true },
}
local EXTRAS = { Dialogue = "Dialogue", Sound = "Sound", VFX = "Template", Animation = "Animation" }
local OFFSET_ANCHOR = { Attach = { "Target", "TargetJoint" }, VFX = { "Anchor", "AnchorJoint" } }

function Clip.Stretches(clip, kind)
	return STRETCH[kind] == true and not (kind == "Animation" and clip:GetAttribute("Loop") == true)
end

local function durationTip(clip, kind)
	if kind == "Dialogue" then
		return "Ripple in the Script tab shifts later lines when this grows"
	elseif kind == "Animation" then
		return "Stretches the animation (Speed follows), like dragging the block edge. Looping clips keep their speed and repeat instead."
	elseif STRETCH[kind] then
		return "Changing the duration stretches the keys (Speed follows)"
	end
	return "Duration"
end

local function timingCommit(app, clip, kind, name)
	local document = app.Document
	if name == "Start" then
		return function(value)
			document:SetClipTiming(clip, value, nil)
		end
	elseif name == "Duration" then
		return function(value)
			if kind == "Dialogue" then
				Ripple.SetDurations(app, { { Clip = clip, Duration = value } }, "Retime line")
			else
				document:SetClipTiming(clip, nil, value, not Clip.Stretches(clip, kind))
			end
		end
	end
	return nil
end

function Clip.OffsetTransform(app, clip, kind)
	local anchor = OFFSET_ANCHOR[kind]
	if not anchor then
		return nil
	end
	return function(world)
		local actor = clip:GetAttribute(anchor[1])
		if type(actor) ~= "string" or actor == "" then
			if kind == "Attach" then
				app:Notify("Pick a Target actor first; the offset is relative to it", "Warn")
				return nil
			end
			return world
		end
		local base, source = Context.JointWorld(app, actor, clip:GetAttribute(anchor[2]))
		if not base then
			app:Notify(`Can't find {actor} in the scene to measure the offset from`, "Warn")
			return nil
		end
		if source ~= "Preview" then
			app:Notify(`Measured against {actor} as it stands in the place. Scrub the preview to measure against the posed rig.`, "Info")
		end
		return base:Inverse() * world
	end
end

function Clip.JointActor(clip, entry)
	return function()
		local value = clip:GetAttribute(entry.JointOf)
		if type(value) ~= "string" or value == "" then
			value = clip.Parent:GetAttribute("Actor")
		end
		if value == "Speaker" then
			return nil
		end
		return value
	end
end

function Clip.FieldOptions(inspector, clip, kind, entry, locked)
	local options = { ReadOnly = locked }
	if entry.Type == "joint" then
		options.JointActor = Clip.JointActor(clip, entry)
	elseif entry.Type == "CFrame" then
		options.Transform = Clip.OffsetTransform(inspector.App, clip, kind)
		options.FromCamera = if kind == "Attach" then false else nil
		options.Tooltip = if kind == "Attach" then "Offset from the target joint. From selection measures the selected model against it, posed as the preview shows it." elseif kind == "VFX" then "Offset from the anchor joint, or a world CFrame without an anchor." else nil
	end
	return options
end

function Clip.Build(inspector, clip, order)
	local app = inspector.App
	local document = app.Document
	local schema = app.Deps.Schema
	local kind = document:KindOf(clip)
	local locked = clip.Parent:GetAttribute("Locked") == true
	local _, timing = Layout.Section(inspector, order, "Timing", "Timing")
	for index, entry in schema.Common do
		Fields.Attribute(inspector, timing, index, clip, entry, {
			ReadOnly = locked,
			Commit = timingCommit(app, clip, kind, entry.Name),
			Tooltip = if entry.Name == "Duration" then durationTip(clip, kind) else entry.Name,
		})
	end
	local ends = Layout.Text(timing, 10, "", { Name = "Ends" })
	inspector:Bind(function()
		local start = clip:GetAttribute("Start") or 0
		local duration = clip:GetAttribute("Duration") or 0
		ends.Text = `Plays {Layout.FormatTime(start)} to {Layout.FormatTime(start + duration)}`
	end)
	local extra = EXTRAS[kind]
	if extra == "Dialogue" then
		require(script.Parent.Dialogue).Build(inspector, clip, order + 1, locked)
		return order + 10
	end
	local definition = schema.Kinds[kind]
	local handled = HANDLED[kind] or {}
	local visible = {}
	for _, entry in if definition then definition.Fields else {} do
		if not handled[entry.Name] then
			table.insert(visible, entry)
		end
	end
	if #visible > 0 then
		local _, body = Layout.Section(inspector, order + 1, "Kind" .. tostring(kind), tostring(kind))
		for index, entry in visible do
			Fields.Attribute(inspector, body, index, clip, entry, Clip.FieldOptions(inspector, clip, kind, entry, locked))
		end
	end
	if extra then
		require(script.Parent[extra]).Build(inspector, clip, order + 2, locked)
	end
	return order + 10
end

return Clip
