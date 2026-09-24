return function(Document)
	local function ordered(a, b)
		local ao, bo = a:GetAttribute("Order"), b:GetAttribute("Order")
		ao, bo = if type(ao) == "number" then ao else math.huge, if type(bo) == "number" then bo else math.huge
		if ao ~= bo then
			return ao < bo
		end
		return a.Name < b.Name
	end

	function Document:IsClip(instance)
		return typeof(instance) == "Instance"
			and instance:IsA("Configuration")
			and instance.Parent ~= nil
			and instance.Parent.Parent ~= nil
			and instance.Parent.Parent.Name == "Tracks"
			and instance.Parent.Parent.Parent == self.Folder
	end

	function Document:IsTrack(instance)
		return typeof(instance) == "Instance" and instance.Parent ~= nil and instance.Parent.Name == "Tracks" and instance.Parent.Parent == self.Folder
	end

	function Document:IsActor(instance)
		return typeof(instance) == "Instance" and instance:IsA("Configuration") and instance.Parent ~= nil and instance.Parent.Name == "Actors" and instance.Parent.Parent == self.Folder
	end

	function Document:IsKey(instance)
		return typeof(instance) == "Instance" and instance.Parent ~= nil and instance.Parent.Name == "Keys" and self:IsClip(instance.Parent.Parent)
	end

	function Document:TrackOf(clip)
		return clip and clip.Parent
	end

	function Document:KindOf(instance)
		if self:IsClip(instance) then
			return instance.Parent:GetAttribute("Kind")
		elseif self:IsTrack(instance) then
			return instance:GetAttribute("Kind")
		end
		return nil
	end

	function Document:ClipOf(key)
		if self:IsKey(key) then
			return key.Parent.Parent
		end
		local current = key
		while current and current ~= self.Folder do
			if self:IsClip(current) then
				return current
			end
			current = current.Parent
		end
		return nil
	end

	function Document:Read(instance, kind)
		kind = kind or self:KindOf(instance)
		if self.Schema and kind then
			return self.Schema.Read(instance, kind)
		end
		return instance:GetAttributes()
	end

	function Document:GetActors()
		local list = {}
		local actors = self.Folder:FindFirstChild("Actors")
		if actors then
			for _, child in actors:GetChildren() do
				if child:IsA("Configuration") then
					table.insert(list, child)
				end
			end
		end
		table.sort(list, ordered)
		return list
	end

	function Document:GetActor(id)
		local actors = self.Folder:FindFirstChild("Actors")
		local config = actors and type(id) == "string" and id ~= "" and actors:FindFirstChild(id)
		return if config and config:IsA("Configuration") then config else nil
	end

	function Document:GetRoles()
		local roles, seen = {}, {}
		for _, actor in self:GetActors() do
			if actor:GetAttribute("Source") == "Role" then
				local role = actor:GetAttribute("Role")
				role = if type(role) == "string" and role ~= "" then role else actor.Name
				if not seen[role] then
					seen[role] = true
					table.insert(roles, role)
				end
			end
		end
		table.sort(roles)
		return roles
	end

	function Document:GetClips(track)
		local clips = {}
		for _, child in track:GetChildren() do
			if child:IsA("Configuration") then
				table.insert(clips, child)
			end
		end
		table.sort(clips, function(a, b)
			local sa, sb = a:GetAttribute("Start") or 0, b:GetAttribute("Start") or 0
			if sa ~= sb then
				return sa < sb
			end
			return a.Name < b.Name
		end)
		return clips
	end

	function Document:GetTracks()
		local list = {}
		local tracks = self.Folder:FindFirstChild("Tracks")
		if tracks then
			for _, child in tracks:GetChildren() do
				local kind = child:GetAttribute("Kind")
				if (child:IsA("Folder") or child:IsA("Configuration")) and type(kind) == "string" and kind ~= "" then
					table.insert(list, child)
				end
			end
		end
		table.sort(list, ordered)
		return list
	end

	function Document:GetLanes()
		local groups, byActor, scene = {}, {}, nil
		for _, track in self:GetTracks() do
			local actorId = track:GetAttribute("Actor")
			local actor = self:GetActor(actorId)
			local entry = {
				Track = track,
				Name = track.Name,
				Kind = track:GetAttribute("Kind"),
				Order = track:GetAttribute("Order") or 0,
				Muted = track:GetAttribute("Muted") == true,
				Locked = track:GetAttribute("Locked") == true,
				Clips = self:GetClips(track),
			}
			local group
			if actor then
				group = byActor[actor]
				if not group then
					group = { Actor = actor, Tracks = {}, First = entry.Order }
					byActor[actor] = group
					table.insert(groups, group)
				end
			else
				if not scene then
					scene = { Actor = nil, Tracks = {}, First = math.huge }
				end
				group = scene
			end
			table.insert(group.Tracks, entry)
		end
		table.sort(groups, function(a, b)
			if a.First ~= b.First then
				return a.First < b.First
			end
			return a.Actor.Name < b.Actor.Name
		end)
		for _, actor in self:GetActors() do
			if not byActor[actor] then
				local group = { Actor = actor, Tracks = {}, First = math.huge }
				byActor[actor] = group
				table.insert(groups, group)
			end
		end
		if scene then
			table.insert(groups, scene)
		end
		return groups
	end

	function Document:GetLength()
		local deps = self.Deps
		if deps and deps.Timeline and deps.Timeline.GetLength then
			return deps.Timeline.GetLength(self.Folder)
		end
		local length = 0
		for _, track in self:GetTracks() do
			for _, clip in self:GetClips(track) do
				length = math.max(length, (clip:GetAttribute("Start") or 0) + (clip:GetAttribute("Duration") or 0))
			end
		end
		return length
	end

	function Document:GetKeys(clip)
		local folder = clip and clip:FindFirstChild("Keys")
		local keys = {}
		if folder then
			for _, child in folder:GetChildren() do
				if child:IsA("CFrameValue") then
					table.insert(keys, child)
				end
			end
		end
		local function timeOf(key)
			local value = key:GetAttribute("Time")
			return if type(value) == "number" then value else tonumber(key.Name) or 0
		end
		table.sort(keys, function(a, b)
			local ta, tb = timeOf(a), timeOf(b)
			if ta ~= tb then
				return ta < tb
			end
			return a.Name < b.Name
		end)
		return keys
	end

	function Document:GetKeyframes(clip)
		local sequence = clip and clip:FindFirstChild("Keyframes")
		if not sequence or not sequence:IsA("KeyframeSequence") then
			return {}
		end
		local list = sequence:GetKeyframes()
		table.sort(list, function(a, b)
			return a.Time < b.Time
		end)
		return list
	end
end
