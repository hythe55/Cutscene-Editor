local Schema = {}

local EASINGS = { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Circular", "Back", "Elastic", "Bounce", "Constant" }
local DIRECTIONS = { "In", "Out", "InOut" }

local TYPE_OF = {
	number = "number",
	string = "string",
	text = "string",
	bool = "boolean",
	enum = "string",
	Color3 = "Color3",
	Vector3 = "Vector3",
	CFrame = "CFrame",
	actor = "string",
	joint = "string",
	easing = "string",
	direction = "string",
}

local function field(name, fieldType, default, label, extra)
	local entry = { Name = name, Type = fieldType, Default = default, Label = label or name }
	if fieldType == "easing" then
		entry.Options = EASINGS
	elseif fieldType == "direction" then
		entry.Options = DIRECTIONS
	end
	if extra then
		for key, value in extra do
			entry[key] = value
		end
	end
	return entry
end

local function fade(name, default, label)
	return field(name, "number", default, label, { Min = 0, Max = 30, Step = 0.05 })
end

Schema.Easings = EASINGS
Schema.Directions = DIRECTIONS

Schema.Common = {
	field("Start", "number", 0, "Start (s)", { Min = 0, Step = 0.05 }),
	field("Duration", "number", 1, "Duration (s)", { Min = 0, Step = 0.05 }),
	field("Speed", "number", 1, "Speed", { Min = 0.05, Max = 10, Step = 0.05 }),
}

Schema.Track = {
	field("Kind", "enum", "", "Kind", { ReadOnly = true }),
	field("Actor", "actor", "", "Actor"),
	field("Order", "number", 0, "Lane", { Min = 0, Step = 1 }),
	field("Muted", "bool", false, "Muted"),
	field("Locked", "bool", false, "Locked"),
}

Schema.Actor = {
	field("Source", "enum", "Tag", "Source", { Options = { "Tag", "Template", "Role", "Group" } }),
	field("Tag", "string", "", "Tag", { When = { Source = "Tag" } }),
	field("Role", "string", "", "Role", { When = { Source = "Role" }, Options = { "Student1", "Student2", "Student3", "Student4" } }),
	field("Group", "enum", "Students", "Group", { When = { Source = "Group" }, Options = { "Students" } }),
	field("Mode", "enum", "Clone", "Mode", { Options = { "Clone", "Original" } }),
	field("DisplayName", "string", "", "Display name"),
	field("Portrait", "enum", "Viewport", "Portrait", { Options = { "Viewport", "Headshot", "None" } }),
	field("PortraitJoint", "joint", "Head", "Portrait joint"),
	field("TalkJoints", "string", "", "Talk joints (comma list)"),
	field("TalkOffset", "Vector3", Vector3.new(0.1, -0.2, 0), "Talk offset (in, up, back)"),
	field("Anchor", "bool", true, "Anchor root"),
}

Schema.Idle = {
	field("AnimationId", "string", "", "Animation id"),
	field("ExportedHash", "string", "", "Exported hash", { ReadOnly = true }),
}

Schema.KeyFields = {
	Move = {
		field("Time", "number", 0, "Time (s)", { Min = 0, Step = 0.05 }),
		field("Easing", "easing", "Linear", "Easing"),
		field("EasingDirection", "direction", "InOut", "Direction"),
	},
	Camera = {
		field("Time", "number", 0, "Time (s)", { Min = 0, Step = 0.05 }),
		field("FOV", "number", 70, "FOV", { Min = 1, Max = 120, Step = 1 }),
		field("Easing", "easing", "Linear", "Easing"),
		field("EasingDirection", "direction", "InOut", "Direction"),
	},
}

Schema.Kinds = {
	Animation = {
		Color = Color3.fromRGB(86, 140, 230),
		DefaultDuration = 3,
		UsesActor = true,
		Children = { Keyframes = "KeyframeSequence" },
		Fields = {
			fade("FadeIn", 0.25, "Fade in (s)"),
			fade("FadeOut", 0.25, "Fade out (s)"),
			field("Loop", "bool", false, "Loop"),
			field("Weight", "number", 1, "Weight", { Min = 0, Max = 1, Step = 0.05 }),
			field("ClipOffset", "number", 0, "Clip offset (s)", { Min = 0, Step = 0.05 }),
			field("AnimationId", "string", "", "Animation id"),
			field("ExportedHash", "string", "", "Exported hash", { ReadOnly = true }),
		},
	},
	Move = {
		Color = Color3.fromRGB(72, 186, 140),
		DefaultDuration = 2,
		UsesActor = true,
		Children = { Keys = "Folder" },
		Fields = {
			field("Interpolation", "enum", "Smooth", "Interpolation", { Options = { "Smooth", "Linear" } }),
		},
	},
	Attach = {
		Color = Color3.fromRGB(150, 196, 80),
		DefaultDuration = 2,
		UsesActor = true,
		Fields = {
			field("Target", "actor", "", "Target actor"),
			field("TargetJoint", "joint", "", "Target joint", { JointOf = "Target" }),
			field("Offset", "CFrame", CFrame.identity, "Offset"),
			fade("BlendIn", 0.15, "Blend in (s)"),
			field("OnExit", "enum", "Stay", "On exit", { Options = { "Stay", "Hide", "Return" } }),
		},
	},
	Camera = {
		Color = Color3.fromRGB(232, 170, 64),
		DefaultDuration = 4,
		UsesActor = false,
		Children = { Keys = "Folder" },
		Fields = {
			field("Anchor", "actor", "", "Anchor actor"),
			field("AnchorJoint", "joint", "", "Anchor joint", { JointOf = "Anchor" }),
			field("Interpolation", "enum", "Smooth", "Interpolation", { Options = { "Smooth", "Linear" } }),
			field("Shake", "number", 0, "Shake", { Min = 0, Max = 5, Step = 0.05 }),
			field("ShakeFrequency", "number", 1, "Shake frequency", { Min = 0, Max = 20, Step = 0.1 }),
			field("LookAtActor", "actor", "", "Look at actor"),
			field("LookAtJoint", "joint", "", "Look at joint", { JointOf = "LookAtActor" }),
			field("LookAtWeight", "number", 0, "Look at weight", { Min = 0, Max = 1, Step = 0.05 }),
			field("FocusActor", "actor", "", "Focus actor"),
			field("FocusJoint", "joint", "", "Focus joint", { JointOf = "FocusActor" }),
		},
	},
	Sound = {
		Color = Color3.fromRGB(214, 96, 176),
		DefaultDuration = 2,
		UsesActor = false,
		Children = { Sound = "Sound" },
		Fields = {
			fade("FadeIn", 0, "Fade in (s)"),
			fade("FadeOut", 0, "Fade out (s)"),
			field("StartOffset", "number", 0, "Start offset (s)", { Min = 0, Step = 0.05 }),
			field("Anchor", "actor", "", "Anchor actor"),
			field("AnchorJoint", "joint", "", "Anchor joint", { JointOf = "Anchor" }),
		},
	},
	VFX = {
		Color = Color3.fromRGB(170, 110, 240),
		DefaultDuration = 1,
		UsesActor = false,
		Children = { Template = "Attachment|BasePart|Model" },
		Fields = {
			field("Anchor", "actor", "", "Anchor actor"),
			field("AnchorJoint", "joint", "", "Anchor joint", { JointOf = "Anchor" }),
			field("Offset", "CFrame", CFrame.identity, "Offset"),
			field("Mode", "enum", "Burst", "Mode", { Options = { "Burst", "Continuous" } }),
			field("EmitScale", "number", 1, "Emit scale", { Min = 0, Max = 10, Step = 0.1 }),
		},
	},
	Dialogue = {
		Color = Color3.fromRGB(240, 214, 92),
		DefaultDuration = 3,
		UsesActor = false,
		Fields = {
			field("Speaker", "actor", "", "Speaker", { AllowRoles = true }),
			field("Text", "text", "", "Text"),
			field("TypeSpeed", "number", 0, "Type speed (0 = default)", { Min = 0, Max = 200, Step = 1 }),
			field("Blips", "bool", true, "Blips"),
			field("Mood", "enum", "Normal", "Mood", { Options = { "Normal", "Shout", "Whisper" } }),
		},
	},
	Overlay = {
		Color = Color3.fromRGB(120, 120, 130),
		DefaultDuration = 2,
		UsesActor = false,
		Fields = {
			field("Color", "Color3", Color3.new(0, 0, 0), "Color"),
			field("Opacity", "number", 1, "Opacity", { Min = 0, Max = 1, Step = 0.05 }),
			fade("FadeIn", 0.5, "Fade in (s)"),
			fade("FadeOut", 0.5, "Fade out (s)"),
			field("Text", "text", "", "Text"),
			field("SubText", "text", "", "Sub text"),
			field("Style", "enum", "Fade", "Style", { Options = { "Fade", "Title", "Clock" } }),
		},
	},
	PostFX = {
		Color = Color3.fromRGB(96, 200, 214),
		DefaultDuration = 2,
		UsesActor = false,
		Fields = {
			fade("FadeIn", 0.5, "Fade in (s)"),
			fade("FadeOut", 0.5, "Fade out (s)"),
			field("Blur", "number", 0, "Blur", { Min = 0, Max = 56, Step = 1 }),
			field("Saturation", "number", 0, "Saturation", { Min = -1, Max = 1, Step = 0.05 }),
			field("Contrast", "number", 0, "Contrast", { Min = -1, Max = 1, Step = 0.05 }),
			field("Brightness", "number", 0, "Brightness", { Min = -1, Max = 1, Step = 0.05 }),
			field("TintColor", "Color3", Color3.new(1, 1, 1), "Tint"),
		},
	},
	Property = {
		Color = Color3.fromRGB(230, 120, 90),
		DefaultDuration = 1,
		UsesActor = true,
		Fields = {
			field("Target", "actor", "", "Target actor (empty = lane actor)"),
			field("Path", "string", "", "Descendant path (a/b/c)"),
			field("Property", "string", "", "Property"),
			field("From", "value", nil, "From (empty = current)"),
			field("To", "value", nil, "To"),
			field("Easing", "easing", "Sine", "Easing"),
			field("EasingDirection", "direction", "InOut", "Direction"),
		},
	},
	Event = {
		Color = Color3.fromRGB(235, 80, 80),
		DefaultDuration = 0,
		UsesActor = false,
		Fields = {
			field("Name", "string", "", "Event name"),
			field("Side", "enum", "Client", "Side", { Options = { "Client", "Server", "Both" } }),
			field("Data", "string", "", "Data"),
		},
	},
	LookAt = {
		Color = Color3.fromRGB(110, 170, 255),
		DefaultDuration = 3,
		UsesActor = true,
		Fields = {
			field("Target", "actor", "", "Target (actor or Speaker)", { AllowSpeaker = true }),
			field("TargetJoint", "joint", "", "Target joint", { JointOf = "Target" }),
			field("Weight", "number", 1, "Weight", { Min = 0, Max = 1, Step = 0.05 }),
			fade("FadeIn", 0.4, "Fade in (s)"),
			fade("FadeOut", 0.4, "Fade out (s)"),
			field("MaxYaw", "number", 70, "Max yaw (deg)", { Min = 0, Max = 180, Step = 1 }),
			field("MaxPitch", "number", 35, "Max pitch (deg)", { Min = 0, Max = 90, Step = 1 }),
		},
	},
	Visibility = {
		Color = Color3.fromRGB(180, 180, 190),
		DefaultDuration = 2,
		UsesActor = true,
		Fields = {
			fade("FadeIn", 0, "Fade in (s)"),
			fade("FadeOut", 0, "Fade out (s)"),
		},
	},
}

for name, kind in Schema.Kinds do
	kind.Name = name
end

Schema.Order = { "Camera", "Dialogue", "Animation", "Move", "LookAt", "Attach", "Visibility", "Property", "Sound", "VFX", "Overlay", "PostFX", "Event" }

Schema.Track[1].Options = Schema.Order

local function coerce(value, entry)
	local expected = TYPE_OF[entry.Type]
	if entry.Type == "value" then
		return value
	end
	if value == nil then
		return entry.Default
	end
	local actual = typeof(value)
	if actual == expected then
		return value
	end
	if expected == "number" then
		return tonumber(value) or entry.Default
	elseif expected == "string" then
		return if actual == "number" or actual == "boolean" then tostring(value) else entry.Default
	elseif expected == "boolean" then
		if value == "true" or value == 1 then
			return true
		elseif value == "false" or value == 0 then
			return false
		end
	end
	return entry.Default
end

local function readFields(instance, fields, into)
	for _, entry in fields do
		into[entry.Name] = coerce(instance:GetAttribute(entry.Name), entry)
	end
	return into
end

function Schema.Get(kind)
	return Schema.Kinds[kind]
end

function Schema.Fields(kind)
	if kind == "Actor" then
		return Schema.Actor
	elseif kind == "Track" then
		return Schema.Track
	elseif kind == "Idle" then
		return Schema.Idle
	end
	local list = table.clone(Schema.Common)
	local definition = Schema.Kinds[kind]
	if definition then
		for _, entry in definition.Fields do
			table.insert(list, entry)
		end
	end
	return list
end

function Schema.Defaults(kind)
	local defaults = {}
	for _, entry in Schema.Fields(kind) do
		defaults[entry.Name] = entry.Default
	end
	local definition = Schema.Kinds[kind]
	if definition then
		defaults.Duration = definition.DefaultDuration
	end
	return defaults
end

function Schema.ReadCommon(clip)
	local props = readFields(clip, Schema.Common, {})
	props.Start = math.max(props.Start, 0)
	props.Duration = math.max(props.Duration, 0)
	if props.Speed <= 0 then
		props.Speed = 1
	end
	return props
end

function Schema.Read(instance, kind)
	if kind == "Actor" then
		return readFields(instance, Schema.Actor, {})
	elseif kind == "Track" then
		return readFields(instance, Schema.Track, {})
	elseif kind == "Idle" then
		return readFields(instance, Schema.Idle, {})
	end
	local props = Schema.ReadCommon(instance)
	local definition = Schema.Kinds[kind]
	if definition then
		readFields(instance, definition.Fields, props)
	end
	return props
end

function Schema.ReadKey(key, kind)
	local fields = Schema.KeyFields[kind]
	return fields and readFields(key, fields, {}) or {}
end

return Schema
