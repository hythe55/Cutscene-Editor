local ACTOR_FIELDS = { "Target", "Anchor", "LookAtActor", "FocusActor", "Speaker" }

local function timeOf(key)
	local value = key:GetAttribute("Time")
	return if type(value) == "number" then value else tonumber(key.Name) or 0
end

local function poseEasing(sequence, jointName)
	for _, keyframe in sequence:GetKeyframes() do
		local found = keyframe:FindFirstChild(jointName, true)
		if found and found:IsA("Pose") and found.Weight > 0 then
			return found.EasingStyle, found.EasingDirection
		end
	end
	return Enum.PoseEasingStyle.CubicV2, Enum.PoseEasingDirection.InOut
end

local function rootName(sequence)
	for _, keyframe in sequence:GetKeyframes() do
		local pose = keyframe:FindFirstChildOfClass("Pose")
		if pose then
			return pose.Name
		end
	end
	return "HumanoidRootPart"
end

return function(Document)
	local round = Document.Round
	local unique = Document.Unique

	function Document:_keysFolder(clip, create)
		local folder = clip:FindFirstChild("Keys")
		if not folder and create then
			folder = Instance.new("Folder")
			folder.Name = "Keys"
			folder.Parent = clip
		end
		return folder
	end

	function Document:_autoEase(clip)
		local keys = self:GetKeys(clip)
		local count = #keys
		for index, key in keys do
			if key:GetAttribute("AutoEase") == true then
				local easing, direction = nil, nil
				if count == 2 and index == 1 then
					easing, direction = "Sine", "InOut"
				elseif count >= 3 and index == 1 then
					easing, direction = "Sine", "In"
				elseif count >= 3 and index == count - 1 then
					easing, direction = "Sine", "Out"
				end
				if key:GetAttribute("Easing") ~= easing then
					self:_set(key, "Easing", easing)
				end
				if key:GetAttribute("EasingDirection") ~= direction then
					self:_set(key, "EasingDirection", direction)
				end
			end
		end
	end

	function Document:_addKey(clip, time, cframe, attrs)
		local folder = self:_keysFolder(clip, true)
		local key = Instance.new("CFrameValue")
		key.Name = unique(folder, "Key")
		key.Value = cframe or CFrame.identity
		self.Touched[key] = true
		key:SetAttribute("Time", round(math.max(time or 0, 0)))
		local kind = clip.Parent and clip.Parent:GetAttribute("Kind")
		if kind == "Camera" and (not attrs or attrs.FOV == nil) then
			key:SetAttribute("FOV", 70)
		end
		for name, value in attrs or {} do
			key:SetAttribute(name, value)
		end
		if not attrs or (attrs.Easing == nil and attrs.EasingDirection == nil) then
			key:SetAttribute("AutoEase", true)
		end
		key.Parent = folder
		return key
	end

	function Document:AddKey(clip, time, cframe, attrs)
		return self:_record("Add key", function()
			assert(self:IsClip(clip), "AddKey needs a clip")
			local key = self:_addKey(clip, time, cframe, attrs)
			self:_autoEase(clip)
			return key
		end)
	end

	function Document:SetKey(key, cframe, attrs)
		return self:_record("Edit key", function()
			self:Touch(key)
			if cframe then
				key.Value = cframe
			end
			for name, value in attrs or {} do
				if name == "Time" and type(value) == "number" then
					value = round(math.max(value, 0))
				end
				key:SetAttribute(name, value)
			end
			if attrs and (attrs.Easing ~= nil or attrs.EasingDirection ~= nil) then
				key:SetAttribute("AutoEase", nil)
			end
			local clip = self:ClipOf(key)
			if clip then
				self:_autoEase(clip)
			end
			return key
		end)
	end

	function Document:DeleteKey(key)
		return self:_record("Delete key", function()
			local clip = self:ClipOf(key)
			self:Touch(key)
			key.Parent = nil
			if clip then
				self:_autoEase(clip)
			end
			return true
		end)
	end

	function Document:_splitKeys(first, second, source)
		local spline = self.Deps and self.Deps.Spline
		local keys = self:GetKeys(first)
		if #keys == 0 then
			return
		end
		local cframe, fov
		if spline then
			local ok, a, b = pcall(function()
				return spline.Evaluate(spline.ReadKeys(first:FindFirstChild("Keys")), source, first:GetAttribute("Interpolation") or "Smooth")
			end)
			if ok then
				cframe, fov = a, b
			end
		end
		local secondFolder = second:FindFirstChild("Keys")
		for _, child in if secondFolder then secondFolder:GetChildren() else {} do
			child:Destroy()
		end
		local exact = false
		for _, key in keys do
			local t = timeOf(key)
			if math.abs(t - source) < 1e-4 then
				exact = true
			end
			if t >= source - 1e-4 then
				local copy = key:Clone()
				copy:SetAttribute("Time", round(math.max(t - source, 0)))
				copy.Parent = secondFolder
			end
			if t > source + 1e-4 then
				self:Touch(key)
				key.Parent = nil
			end
		end
		if not exact and cframe then
			local camera = first.Parent and first.Parent:GetAttribute("Kind") == "Camera"
			local attrs = if camera and fov then { FOV = fov } else {}
			self:_addKey(first, source, cframe, attrs)
			self:_addKey(second, 0, cframe, attrs)
		end
		self:_autoEase(first)
	end

	function Document:_sequence(clip)
		local sequence = clip:FindFirstChild("Keyframes")
		if not sequence then
			sequence = Instance.new("KeyframeSequence")
			sequence.Name = "Keyframes"
			sequence.Parent = clip
		end
		return sequence
	end

	function Document:_setPose(clip, keyframe, jointKey, cframe, weight)
		local sequence = self:_sequence(clip)
		assert(keyframe:IsDescendantOf(sequence), "SetPose needs a keyframe of this clip")
		self:Touch(sequence)
		local root = keyframe:FindFirstChildOfClass("Pose")
		if not root then
			root = Instance.new("Pose")
			root.Name = rootName(sequence)
			root.Weight = 0
			root.Parent = keyframe
		end
		local parent = root
		local segments = string.split(jointKey, "/")
		for index, segment in segments do
			local pose = parent:FindFirstChild(segment)
			if not pose or not pose:IsA("Pose") then
				pose = Instance.new("Pose")
				pose.Name = segment
				pose.Weight = 0
				local style, direction = poseEasing(sequence, segment)
				pose.EasingStyle = style
				pose.EasingDirection = direction
				pose.Parent = parent
			end
			if index == #segments then
				pose.CFrame = cframe
				pose.Weight = weight or 1
			end
			parent = pose
		end
		return parent
	end

	function Document:SetPose(clip, keyframe, jointKey, cframe)
		return self:_record("Edit pose", function()
			return self:_setPose(clip, keyframe, jointKey, cframe)
		end)
	end

	function Document:ResetPose(clip, keyframe, jointKey)
		return self:_record("Reset joint", function()
			return self:_setPose(clip, keyframe, jointKey, CFrame.identity)
		end)
	end

	function Document:AddKeyframe(clip, time, poseTable)
		return self:_record("Add keyframe", function()
			local sequence = self:_sequence(clip)
			self:Touch(sequence)
			local keyframe
			for _, existing in sequence:GetKeyframes() do
				if math.abs(existing.Time - time) < 1e-4 then
					keyframe = existing
				end
			end
			if not keyframe then
				keyframe = Instance.new("Keyframe")
				keyframe.Time = round(math.max(time, 0))
				keyframe.Parent = sequence
			end
			for jointKey, cframe in poseTable or {} do
				self:_setPose(clip, keyframe, jointKey, cframe)
			end
			return keyframe
		end)
	end

	function Document:DeleteKeyframe(keyframe)
		return self:_record("Delete keyframe", function()
			self:Touch(keyframe.Parent)
			keyframe.Parent = nil
			return true
		end)
	end

	function Document:SetKeyframeTime(keyframe, time)
		return self:_record("Move keyframe", function()
			self:Touch(keyframe.Parent)
			keyframe.Time = round(math.max(time, 0))
			return keyframe
		end)
	end

	function Document:RenameActor(config, name)
		return self:_record("Rename actor", function()
			assert(self:IsActor(config), "RenameActor needs an actor")
			local old = config.Name
			if type(name) ~= "string" or name == "" or name == old then
				return config
			end
			local new = if config.Parent:FindFirstChild(name) then unique(config.Parent, name) else name
			self:Touch(config)
			config.Name = new
			for _, track in self:GetTracks() do
				if track:GetAttribute("Actor") == old then
					self:_set(track, "Actor", new)
				end
				for _, clip in self:GetClips(track) do
					for _, field in ACTOR_FIELDS do
						if clip:GetAttribute(field) == old then
							self:_set(clip, field, new)
						end
					end
				end
			end
			return config
		end)
	end

	function Document:DeleteTrack(track)
		return self:_record("Delete track", function()
			assert(self:IsTrack(track), "DeleteTrack needs a track")
			self:Touch(track)
			track.Parent = nil
			return true
		end)
	end

	function Document:DeleteActor(config)
		return self:_record("Delete actor", function()
			assert(self:IsActor(config), "DeleteActor needs an actor")
			self:Touch(config)
			config.Parent = nil
			return true
		end)
	end

	function Document:Batch(name, fn, ...)
		return self:_record(name, fn, ...)
	end

	function Document:WriteAttribute(instance, name, value)
		return self:_set(instance, name, value)
	end

	function Document:WriteKey(clip, time, cframe, attrs)
		return self:_addKey(clip, time, cframe, attrs)
	end

	function Document:WritePose(clip, keyframe, jointKey, cframe, weight)
		return self:_setPose(clip, keyframe, jointKey, cframe, weight)
	end

	function Document:AutoEase(clip)
		return self:_autoEase(clip)
	end

	function Document:EnsureSequence(clip)
		return self:_sequence(clip)
	end

	function Document:WriteClip(track, start, props, template)
		return self:_newClip(track, start, props, template)
	end
end
