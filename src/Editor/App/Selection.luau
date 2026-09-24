return function(App)
	function App:_pruneSelection()
		local document = self.Document
		local selection = self.Selection
		local changed = false
		for clip in selection.Clips do
			if not document or not document:IsClip(clip) then
				selection.Clips[clip] = nil
				changed = true
			end
		end
		if selection.Primary and not selection.Clips[selection.Primary] then
			selection.Primary = next(selection.Clips)
			changed = true
		end
		if selection.Track and (not document or not document:IsTrack(selection.Track)) then
			selection.Track = nil
			changed = true
		end
		if selection.Actor and (not document or not document:IsActor(selection.Actor)) then
			selection.Actor = nil
			changed = true
		end
		if selection.Key and (not document or not selection.Key:IsDescendantOf(document.Folder)) then
			selection.Key = nil
			changed = true
		end
		if changed then
			self.Signals.SelectionChanged:Fire(selection)
		end
	end

	function App:_classify(target)
		local document = self.Document
		if not document or typeof(target) ~= "Instance" then
			return nil
		end
		if document:IsClip(target) then
			return "Clip"
		elseif document:IsTrack(target) then
			return "Track"
		elseif document:IsActor(target) then
			return "Actor"
		elseif document:IsKey(target) then
			return "Key"
		end
		return nil
	end

	function App:_setContext(clip)
		local selection = self.Selection
		local document = self.Document
		if clip and document then
			selection.Track = clip.Parent
			selection.Actor = document:GetActor(clip.Parent:GetAttribute("Actor"))
		end
	end

	function App:Select(target, mode)
		mode = mode or "Replace"
		local selection = self.Selection
		local kind = self:_classify(target)
		if kind == "Key" then
			return self:SelectKey(target)
		elseif kind == "Track" or kind == "Actor" then
			selection.Clips = {}
			selection.Primary = nil
			selection.Key = nil
			selection.SubKey = nil
			if kind == "Track" then
				selection.Track = target
				selection.Actor = self.Document:GetActor(target:GetAttribute("Actor"))
			else
				selection.Track = nil
				selection.Actor = target
			end
			self.Signals.SelectionChanged:Fire(selection)
			return selection
		end
		local clips = {}
		if kind == "Clip" then
			clips = { target }
		elseif type(target) == "table" then
			for key, value in target do
				local clip = if typeof(key) == "Instance" then key else value
				if self:_classify(clip) == "Clip" then
					table.insert(clips, clip)
				end
			end
		end
		selection.SubKey = nil
		if mode == "Replace" then
			selection.Clips = {}
			selection.Primary = nil
			selection.Key = nil
			selection.Track = nil
			selection.Actor = nil
		end
		for _, clip in clips do
			if mode == "Toggle" and selection.Clips[clip] then
				selection.Clips[clip] = nil
				if selection.Primary == clip then
					selection.Primary = nil
				end
			else
				selection.Clips[clip] = true
				selection.Primary = clip
			end
		end
		if not selection.Primary then
			selection.Primary = next(selection.Clips)
		end
		if selection.Key and self.Document:ClipOf(selection.Key) ~= selection.Primary then
			selection.Key = nil
		end
		if selection.Primary then
			self:_setContext(selection.Primary)
		end
		self.Signals.SelectionChanged:Fire(selection)
		return selection
	end

	function App:SelectSubKey(subKey)
		local selection = self.Selection
		if subKey then
			selection.Clips = { [subKey.Clip] = true }
			selection.Primary = subKey.Clip
			selection.Key = nil
			self:_setContext(subKey.Clip)
		end
		selection.SubKey = subKey
		self.Signals.SelectionChanged:Fire(selection)
		return selection
	end

	function App:SelectKey(key)
		local selection = self.Selection
		selection.SubKey = nil
		if key == nil then
			selection.Key = nil
			self.Signals.SelectionChanged:Fire(selection)
			return selection
		end
		local clip = self.Document and self.Document:ClipOf(key)
		if clip and not selection.Clips[clip] then
			selection.Clips = { [clip] = true }
		end
		if clip then
			selection.Primary = clip
			self:_setContext(clip)
		end
		selection.Key = key
		self.Signals.SelectionChanged:Fire(selection)
		return selection
	end

	function App:GetSelectedClips()
		local list = {}
		for clip in self.Selection.Clips do
			table.insert(list, clip)
		end
		table.sort(list, function(a, b)
			return (a:GetAttribute("Start") or 0) < (b:GetAttribute("Start") or 0)
		end)
		return list
	end
end
