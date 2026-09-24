local RETIME_KINDS = { Animation = true, Camera = true, Move = true }
local FADE_KINDS = { Animation = true, Sound = true, Overlay = true, PostFX = true, LookAt = true, Visibility = true }
local DEFAULT_NAMES = { Dialogue = "Line", Camera = "Shot", Animation = "Anim", Sound = "Sound", VFX = "Effect", Event = "Event" }
local KIND_LABELS = { Animation = "Anim", Visibility = "Visible", Property = "Props", VFX = "FX" }

local function round(value)
	return math.round(value * 10000) / 10000
end

local function unique(parent, base)
	local name, index = base, 1
	while parent:FindFirstChild(name) do
		index += 1
		name = base .. index
	end
	return name
end

local function list(clips)
	local result, seen = {}, {}
	if typeof(clips) == "Instance" then
		return { clips }
	end
	for key, value in clips or {} do
		local clip = if typeof(key) == "Instance" then key else value
		if typeof(clip) == "Instance" and not seen[clip] then
			seen[clip] = true
			table.insert(result, clip)
		end
	end
	return result
end

return function(Document)
	Document.Round = round
	Document.Unique = unique

	function Document:_set(instance, name, value)
		self:Touch(instance)
		if instance:GetAttribute(name) ~= value then
			instance:SetAttribute(name, value)
		end
	end

	function Document:_editable(clip)
		local track = clip and clip.Parent
		return self:IsClip(clip) and track:GetAttribute("Locked") ~= true
	end

	function Document:_writeDefaults(instance, kind, props)
		local schema = self.Schema
		for _, entry in schema.Fields(kind) do
			if entry.Default ~= nil and instance:GetAttribute(entry.Name) == nil then
				instance:SetAttribute(entry.Name, entry.Default)
			end
		end
		for key, value in props or {} do
			if key ~= "Name" and key ~= "Template" and typeof(value) ~= "Instance" then
				instance:SetAttribute(key, value)
			end
		end
	end

	function Document:MoveClips(clips, deltaTime, targetTrack)
		return self:_record("Move clips", function()
			local items = {}
			local earliest = math.huge
			for _, clip in list(clips) do
				if self:_editable(clip) then
					table.insert(items, clip)
					earliest = math.min(earliest, clip:GetAttribute("Start") or 0)
				end
			end
			if #items == 0 then
				return {}
			end
			local delta = math.max(deltaTime or 0, -earliest)
			local target = nil
			if targetTrack and self:IsTrack(targetTrack) and targetTrack:GetAttribute("Locked") ~= true then
				target = targetTrack
				for _, clip in items do
					if clip.Parent:GetAttribute("Kind") ~= targetTrack:GetAttribute("Kind") then
						target = nil
						break
					end
				end
			end
			for _, clip in items do
				self:_set(clip, "Start", round((clip:GetAttribute("Start") or 0) + delta))
				if target and clip.Parent ~= target then
					if target:FindFirstChild(clip.Name) then
						clip.Name = unique(target, clip.Name)
					end
					clip.Parent = target
				end
			end
			return items
		end)
	end

	function Document:SetClipTiming(clip, start, duration, trim)
		return self:_record("Retime clip", function()
			if not self:_editable(clip) then
				return nil
			end
			local kind = clip.Parent:GetAttribute("Kind")
			local oldStart = clip:GetAttribute("Start") or 0
			local oldDuration = clip:GetAttribute("Duration") or 0
			local speed = clip:GetAttribute("Speed") or 1
			start = round(math.max(start or oldStart, 0))
			duration = round(math.max(duration or oldDuration, 0))
			if trim then
				local shift = (start - oldStart) * speed
				if shift ~= 0 and kind == "Animation" then
					self:_set(clip, "ClipOffset", round(math.max((clip:GetAttribute("ClipOffset") or 0) + shift, 0)))
				elseif shift ~= 0 and kind == "Sound" then
					self:_set(clip, "StartOffset", round(math.max((clip:GetAttribute("StartOffset") or 0) + shift, 0)))
				end
			elseif RETIME_KINDS[kind] and oldDuration > 0 and duration > 0 and duration ~= oldDuration then
				self:_set(clip, "Speed", round(math.clamp(speed * oldDuration / duration, 0.05, 10)))
			end
			self:_set(clip, "Start", start)
			self:_set(clip, "Duration", duration)
			return clip
		end)
	end

	function Document:SetAttribute(instance, name, value)
		return self:_record("Set " .. tostring(name), function()
			self:_set(instance, name, value)
			return instance
		end)
	end

	function Document:SetAttributes(instance, values)
		return self:_record("Edit " .. instance.Name, function()
			for name, value in values do
				self:_set(instance, name, value)
			end
			return instance
		end)
	end

	function Document:Rename(instance, name)
		if self:IsActor(instance) then
			return self:RenameActor(instance, name)
		end
		return self:_record("Rename", function()
			if type(name) ~= "string" or name == "" then
				return instance
			end
			local parent = instance.Parent
			local sibling = parent and parent:FindFirstChild(name)
			self:Touch(instance)
			instance.Name = if sibling and sibling ~= instance then unique(parent, name) else name
			return instance
		end)
	end

	function Document:AddActor(props)
		props = props or {}
		return self:_record("Add actor", function()
			local folder = self.Folder:FindFirstChild("Actors")
			if not folder then
				folder = Instance.new("Folder")
				folder.Name = "Actors"
				folder.Parent = self.Folder
			end
			local config = Instance.new("Configuration")
			config.Name = unique(folder, props.Id or props.Name or "Actor")
			self.Touched[config] = true
			local attributes = table.clone(props)
			attributes.Id = nil
			self:_writeDefaults(config, "Actor", attributes)
			if typeof(props.Template) == "Instance" then
				local template = props.Template:Clone()
				template.Name = "Template"
				template.Parent = config
				config:SetAttribute("Source", "Template")
			end
			config.Parent = folder
			return config
		end)
	end

	function Document:AddTrack(kind, actorId, name)
		return self:_record("Add track", function()
			local folder = self.Folder:FindFirstChild("Tracks")
			if not folder then
				folder = Instance.new("Folder")
				folder.Name = "Tracks"
				folder.Parent = self.Folder
			end
			local order = -1
			for _, track in self:GetTracks() do
				order = math.max(order, track:GetAttribute("Order") or 0)
			end
			local label = KIND_LABELS[kind] or kind
			local base = name or (if actorId and actorId ~= "" then actorId .. " " .. label else label)
			local track = Instance.new("Folder")
			track.Name = unique(folder, base)
			self.Touched[track] = true
			track:SetAttribute("Kind", kind)
			track:SetAttribute("Actor", actorId or "")
			track:SetAttribute("Order", order + 1)
			track:SetAttribute("Muted", false)
			track:SetAttribute("Locked", false)
			track.Parent = folder
			return track
		end)
	end

	function Document:_newClip(track, start, props, template)
		local kind = track:GetAttribute("Kind")
		local schema = self.Schema
		local definition = schema.Kinds[kind]
		props = props or {}
		local clip = Instance.new("Configuration")
		clip.Name = unique(track, props.Name or DEFAULT_NAMES[kind] or kind or "Clip")
		self.Touched[clip] = true
		local duration = props.Duration
		if typeof(template) == "Instance" then
			local copy = template:Clone()
			if kind == "Animation" and copy:IsA("KeyframeSequence") then
				copy.Name = "Keyframes"
				if duration == nil then
					local length = 0
					for _, keyframe in copy:GetKeyframes() do
						length = math.max(length, keyframe.Time)
					end
					duration = if length > 0 then length else nil
				end
			elseif (kind == "Move" or kind == "Camera") and copy:IsA("Folder") then
				copy.Name = "Keys"
			elseif kind == "Sound" and copy:IsA("Sound") and duration == nil and copy.TimeLength > 0 then
				duration = copy.TimeLength / math.max(copy.PlaybackSpeed, 0.01)
			end
			copy.Parent = clip
		end
		for childName, className in (definition and definition.Children) or {} do
			if not clip:FindFirstChild(childName) and not string.find(className, "|") and className ~= "Sound" then
				local child = Instance.new(className)
				child.Name = childName
				child.Parent = clip
			end
		end
		if kind == "Animation" then
			local sequence = clip:FindFirstChild("Keyframes")
			if sequence and sequence:IsA("KeyframeSequence") and self._adopt then
				self:_adopt(clip, sequence)
			end
		end
		if kind == "Sound" and not clip:FindFirstChildWhichIsA("Sound") then
			local sound = Instance.new("Sound")
			sound.Name = "Sound"
			sound.Parent = clip
		end
		local values = table.clone(props)
		values.Name = nil
		values.Duration = nil
		self:_writeDefaults(clip, kind, values)
		clip:SetAttribute("Start", round(math.max(start or 0, 0)))
		clip:SetAttribute("Duration", round(math.max(duration or (definition and definition.DefaultDuration) or 1, 0)))
		if clip:GetAttribute("Speed") == nil then
			clip:SetAttribute("Speed", 1)
		end
		return clip
	end

	function Document:AddClip(track, start, props, template)
		return self:_record("Add clip", function()
			assert(self:IsTrack(track), "AddClip needs a track of this cutscene")
			local clip = self:_newClip(track, start, props, template)
			clip.Parent = track
			return clip
		end)
	end

	function Document:DeleteClips(clips)
		return self:_record("Delete clips", function()
			local count = 0
			for _, clip in list(clips) do
				if self:_editable(clip) then
					self:Touch(clip)
					clip.Parent = nil
					count += 1
				end
			end
			return count
		end)
	end

	function Document:DuplicateClips(clips)
		return self:_record("Duplicate clips", function()
			local items = {}
			local first, last = math.huge, -math.huge
			for _, clip in list(clips) do
				if self:IsClip(clip) then
					table.insert(items, clip)
					local start = clip:GetAttribute("Start") or 0
					first = math.min(first, start)
					last = math.max(last, start + (clip:GetAttribute("Duration") or 0))
				end
			end
			local span = if #items > 0 then math.max(last - first, 1 / 30) else 0
			local copies = {}
			for _, clip in items do
				local copy = clip:Clone()
				copy.Name = unique(clip.Parent, clip.Name)
				self.Touched[copy] = true
				copy:SetAttribute("Start", round((clip:GetAttribute("Start") or 0) + span))
				copy.Parent = clip.Parent
				if copy:GetAttribute("SourceId") then
					self:_fork(copy)
				end
				table.insert(copies, copy)
			end
			return copies
		end)
	end

	function Document:SplitClip(clip, t)
		return self:_record("Split clip", function()
			if not self:_editable(clip) then
				return nil
			end
			local kind = clip.Parent:GetAttribute("Kind")
			local start = clip:GetAttribute("Start") or 0
			local duration = clip:GetAttribute("Duration") or 0
			local speed = clip:GetAttribute("Speed") or 1
			local offset = t - start
			if offset <= 1e-3 or offset >= duration - 1e-3 then
				return nil
			end
			local source = offset * speed
			local second = clip:Clone()
			second.Name = unique(clip.Parent, clip.Name)
			self.Touched[second] = true
			self:_set(clip, "Duration", round(offset))
			second:SetAttribute("Start", round(t))
			second:SetAttribute("Duration", round(duration - offset))
			if kind == "Animation" then
				second:SetAttribute("ClipOffset", round((clip:GetAttribute("ClipOffset") or 0) + source))
			elseif kind == "Sound" then
				second:SetAttribute("StartOffset", round((clip:GetAttribute("StartOffset") or 0) + source))
			elseif kind == "Camera" or kind == "Move" then
				self:_splitKeys(clip, second, source)
			end
			if FADE_KINDS[kind] then
				if clip:GetAttribute("FadeOut") ~= nil then
					self:_set(clip, "FadeOut", 0)
				end
				if second:GetAttribute("FadeIn") ~= nil then
					second:SetAttribute("FadeIn", 0)
				end
			end
			second.Parent = clip.Parent
			if second:GetAttribute("SourceId") then
				self:_fork(second)
			end
			return second
		end)
	end
end
