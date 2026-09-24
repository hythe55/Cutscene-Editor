return function(Preview)
	function Preview:Rebuild()
		if not self.Active or self.Suspended then
			return
		end
		local timeline = self.Timeline
		local t = if timeline then timeline.TimePosition else self.App.Time
		local playing = self.Playing
		self:_teardownTimeline()
		self:_finish()
		self:_begin()
		if not self:_buildTimeline(t) then
			self:Stop()
			return
		end
		if playing then
			self.Timeline:Play()
		end
		self:_changed()
	end

	function Preview:BeforeWrite(_name)
		if not self.Active then
			return true
		end
		if self.Playing then
			self.App:Notify("Pause the preview before editing", "Warn")
			return false
		end
		self:_teardownTimeline()
		self:_finish()
		self.Suspended = true
		return true
	end

	function Preview:AfterWrite(_name, _ok)
		if not self.Suspended then
			return
		end
		self.Suspended = false
		if not self.Active then
			return
		end
		self:_begin()
		if not self:_buildTimeline(self.App.Time) then
			self:Stop()
			return
		end
		self:_changed()
	end

	function Preview:Reload()
		if not self.Active or self.Suspended then
			return
		end
		local timeline = self.Timeline
		local t = if timeline then timeline.TimePosition else self.App.Time
		local playing = self.Playing
		self:_teardownTimeline()
		if not self:_buildTimeline(t) then
			self:Stop()
			return
		end
		if playing then
			self.Timeline:Play()
		end
		self:_changed()
	end

	function Preview:DocumentChanged(changes)
		if not self.Active or self.Suspended or not changes.External then
			return
		end
		if changes.Undo or changes.Redo then
			self:Reload()
			return
		end
		if self.Outside then
			self.Outside:Mark("cutscene edited outside the editor")
		end
		self:Rebuild()
	end
end
