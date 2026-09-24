local Model = {}

local PASS, STOP, SNAP = "Pass", "Stop", "Snap"
local Style = Enum.PoseEasingStyle

Model.Fades = {
	Animation = { "FadeIn", "FadeOut" },
	Sound = { "FadeIn", "FadeOut" },
	Overlay = { "FadeIn", "FadeOut" },
	PostFX = { "FadeIn", "FadeOut" },
	LookAt = { "FadeIn", "FadeOut" },
	Visibility = { "FadeIn", "FadeOut" },
	Attach = { "BlendIn" },
}

Model.Retime = { Animation = true, Camera = true, Move = true }

local SPEAKER_COLORS = {
	Color3.fromRGB(255, 160, 80),
	Color3.fromRGB(110, 190, 255),
	Color3.fromRGB(150, 225, 110),
	Color3.fromRGB(255, 120, 170),
	Color3.fromRGB(190, 150, 255),
	Color3.fromRGB(100, 225, 200),
	Color3.fromRGB(255, 225, 110),
	Color3.fromRGB(235, 130, 100),
}

local EXCERPT = 140

local roleCache = setmetatable({}, { __mode = "k" })

local function number(value, default)
	return if type(value) == "number" and value == value then value else default
end

local function text(value)
	return if type(value) == "string" then value else ""
end

local function hash(value)
	local total = 7
	for index = 1, #value do
		total = (total * 31 + string.byte(value, index)) % 1000003
	end
	return total
end

function Model.SpeakerColor(base, speaker)
	if speaker == "" then
		return base
	end
	return base:Lerp(SPEAKER_COLORS[hash(speaker) % #SPEAKER_COLORS + 1], 0.5)
end

local function poseRole(pose)
	local style = pose.EasingStyle
	if style == Style.Linear then
		return PASS
	elseif style == Style.Cubic or (style == Style.CubicV2 and pose.EasingDirection == Enum.PoseEasingDirection.InOut) then
		return STOP
	end
	return SNAP
end

local function keyframeRole(keyframe, smooth)
	if not smooth then
		return STOP
	end
	local pass, stop, snap = 0, 0, 0
	for _, pose in keyframe:GetDescendants() do
		if pose:IsA("Pose") and pose.Weight > 0 then
			local role = poseRole(pose)
			if role == PASS then
				pass += 1
			elseif role == STOP then
				stop += 1
			else
				snap += 1
			end
		end
	end
	if snap > 0 and snap >= stop and snap >= pass then
		return SNAP
	elseif pass > stop then
		return PASS
	end
	return STOP
end

function Model.Invalidate(sequence)
	if sequence then
		roleCache[sequence] = nil
	else
		table.clear(roleCache)
	end
end

local function sequenceKeys(sequence)
	local keyframes = sequence:GetKeyframes()
	table.sort(keyframes, function(a, b)
		return a.Time < b.Time
	end)
	local smooth = sequence:GetAttribute("Interpolation") == "Smooth"
	local cached = roleCache[sequence]
	if cached and cached.Count == #keyframes and cached.Smooth == smooth then
		local same = true
		for index, keyframe in cached.Instances do
			if keyframes[index] ~= keyframe or keyframe.Time ~= cached.Keys[index].Source then
				same = false
				break
			end
		end
		if same then
			return cached.Keys, cached.Length
		end
	end
	local keys, length = {}, 0
	for index, keyframe in keyframes do
		keys[index] = { Source = keyframe.Time, Role = keyframeRole(keyframe, smooth), Instance = keyframe }
		length = math.max(length, keyframe.Time)
	end
	roleCache[sequence] = { Count = #keyframes, Smooth = smooth, Instances = keyframes, Keys = keys, Length = length }
	return keys, length
end

local function splineKeys(clip)
	local folder = clip:FindFirstChild("Keys")
	local keys = {}
	if not folder then
		return keys
	end
	for _, key in folder:GetChildren() do
		if key:IsA("CFrameValue") then
			local easing = key:GetAttribute("Easing")
			local role = if easing == nil or easing == "Linear" then PASS elseif easing == "Constant" then SNAP else STOP
			table.insert(keys, { Source = number(key:GetAttribute("Time"), tonumber(key.Name) or 0), Role = role, Instance = key })
		end
	end
	table.sort(keys, function(a, b)
		return a.Source < b.Source
	end)
	return keys
end

local function excerpt(value)
	value = string.gsub(value, "%s+", " ")
	if #value > EXCERPT then
		value = string.sub(value, 1, EXCERPT) .. "..."
	end
	return value
end

local function speakerName(document, id)
	local actor = document:GetActor(id)
	local display = actor and actor:GetAttribute("DisplayName")
	return if type(display) == "string" and display ~= "" then display else id
end

function Model.Substitute(document, value)
	return (string.gsub(value, "{([%w_]+)}", function(id)
		return speakerName(document, id)
	end))
end

local function soundName(clip)
	local sound = clip:FindFirstChildWhichIsA("Sound")
	if not sound then
		return nil
	end
	local asset = sound:GetAttribute("AssetName")
	if type(asset) == "string" and asset ~= "" then
		return asset
	end
	if sound.Name ~= "Sound" then
		return sound.Name
	end
	return if sound.SoundId ~= "" then sound.SoundId else nil
end

local function describe(document, item, clip)
	local kind, name = item.Kind, clip.Name
	local get = function(attribute)
		return text(clip:GetAttribute(attribute))
	end
	if kind == "Dialogue" then
		local speaker = get("Speaker")
		item.Speaker = speaker
		item.SpeakerName = if speaker ~= "" then speakerName(document, speaker) else ""
		item.Text = get("Text")
		item.Spoken = Model.Substitute(document, item.Text)
		item.TypeSpeed = number(clip:GetAttribute("TypeSpeed"), 0)
		item.Mood = get("Mood")
		local line = excerpt(item.Spoken)
		if line == "" then
			return if item.SpeakerName ~= "" then item.SpeakerName .. ": ..." else name
		end
		return line
	elseif kind == "Animation" then
		local suffix = if clip:GetAttribute("Loop") == true then " (loop)" else ""
		if item.Speed ~= 1 then
			suffix ..= string.format(" x%.3g", item.Speed)
		end
		return name .. suffix
	elseif kind == "Sound" then
		local sound = soundName(clip)
		return if sound then name .. " · " .. sound else name
	elseif kind == "VFX" then
		local template = clip:FindFirstChildWhichIsA("PVInstance") or clip:FindFirstChildWhichIsA("Attachment")
		return if template then name .. " · " .. template.Name else name
	elseif kind == "Camera" or kind == "Move" then
		local count = #item.Keys
		return name .. " · " .. count .. (if count == 1 then " key" else " keys")
	elseif kind == "Event" then
		local event = get("Name")
		return if event ~= "" and event ~= name then name .. " · " .. event else name
	elseif kind == "Property" then
		local property = get("Property")
		return if property ~= "" then name .. " · " .. property else name
	elseif kind == "Overlay" then
		local caption = get("Text")
		return if caption ~= "" then name .. " · " .. excerpt(caption) else name
	elseif kind == "LookAt" or kind == "Attach" then
		local target = get("Target")
		return if target ~= "" then name .. " -> " .. target else name
	end
	return name
end

function Model.Empty()
	return { Rows = {}, Total = 0, Items = {}, ByClip = {}, ByTrack = {}, TrackRows = {}, Length = 0 }
end

function Model.Item(view, clip, info, row)
	local app = view.App
	local document = app.Document
	local schema = app.Deps.Schema
	local kind = info.Kind
	local definition = schema.Kinds[kind]
	local item = {
		Clip = clip,
		Track = info.Track,
		Info = info,
		Row = row,
		Kind = kind,
		Start = math.max(number(clip:GetAttribute("Start"), 0), 0),
		Duration = math.max(number(clip:GetAttribute("Duration"), 0), 0),
		Speed = number(clip:GetAttribute("Speed"), 1),
		ClipOffset = math.max(number(clip:GetAttribute("ClipOffset"), 0), 0),
		Loop = clip:GetAttribute("Loop") == true,
		Locked = info.Locked == true,
		Muted = info.Muted == true,
		Keys = {},
		SourceLength = 0,
		Color = definition and definition.Color or Color3.fromRGB(150, 150, 160),
	}
	if item.Speed <= 0 then
		item.Speed = 1
	end
	item.End = item.Start + item.Duration
	local fades = Model.Fades[kind]
	if fades then
		item.Fades = {}
		for _, name in fades do
			item.Fades[name] = math.max(number(clip:GetAttribute(name), 0), 0)
		end
	end
	if kind == "Animation" then
		local sequence = clip:FindFirstChild("Keyframes")
		if sequence and sequence:IsA("KeyframeSequence") then
			item.Keys, item.SourceLength = sequenceKeys(sequence)
			item.Sequence = sequence
		end
	elseif kind == "Camera" or kind == "Move" then
		item.Keys = splineKeys(clip)
		item.Anchor = text(clip:GetAttribute("Anchor"))
		item.AnchorJoint = text(clip:GetAttribute("AnchorJoint"))
	end
	item.Label = describe(document, item, clip)
	if kind == "Dialogue" then
		item.Color = Model.SpeakerColor(item.Color, item.Speaker)
	end
	return item
end

function Model.KeyTimes(item, start, duration, speed, offset, fn)
	local finish = start + duration + 1e-6
	if item.Kind == "Animation" then
		local length = item.SourceLength
		for _, key in item.Keys do
			local offsetTime = key.Source - offset
			if item.Loop and length > 0 then
				offsetTime %= length
				local t = start + offsetTime / speed
				while t <= finish do
					if fn(t, key) == false then
						return
					end
					t += length / speed
				end
			else
				local t = start + offsetTime / speed
				if offsetTime >= -1e-6 and t <= finish then
					if fn(t, key) == false then
						return
					end
				end
			end
		end
	else
		for _, key in item.Keys do
			local t = start + key.Source / speed
			if key.Source >= -1e-6 and t <= finish then
				if fn(t, key) == false then
					return
				end
			end
		end
	end
end

function Model.Build(view)
	local app = view.App
	local model = Model.Empty()
	if not app.Document then
		return model
	end
	local rows, total = app:GetRows()
	model.Rows, model.Total = rows, total
	model.Length = app:GetLength()
	for _, row in rows do
		if row.Type == "Track" then
			model.TrackRows[row.Track] = row
		end
	end
	for _, row in rows do
		if row.Type == "Group" and row.Lane then
			for _, info in row.Lane.Tracks do
				local trackRow = model.TrackRows[info.Track]
				local list = {}
				for _, clip in info.Clips do
					local ok, item = pcall(Model.Item, view, clip, info, trackRow)
					if ok then
						table.insert(list, item)
						table.insert(model.Items, item)
						model.ByClip[clip] = item
					else
						warn(`CutsceneEditor: timeline could not read {clip:GetFullName()}: {item}`)
					end
				end
				model.ByTrack[info.Track] = list
			end
		end
	end
	return model
end

function Model.Describe(item)
	local lines = { item.Clip.Name .. "  ·  " .. item.Kind }
	local finish = item.Start + item.Duration
	local timing = string.format("%.2f to %.2f s  (%.2f s)", item.Start, finish, item.Duration)
	if item.Speed ~= 1 then
		timing ..= string.format("  speed %.2f", item.Speed)
	end
	table.insert(lines, timing)
	if item.Kind == "Dialogue" and item.Text ~= "" then
		table.insert(lines, (if item.SpeakerName ~= "" then item.SpeakerName .. ": " else "") .. item.Spoken)
	end
	if item.Locked then
		table.insert(lines, "Track is locked")
	end
	for _, warning in item.Warnings or {} do
		table.insert(lines, "Warning: " .. warning)
	end
	return table.concat(lines, "\n")
end

Model.PASS, Model.STOP, Model.SNAP = PASS, STOP, SNAP

return Model
