return function(App)
	local Rows = require(script.Parent.Rows)

	function App:SnapToFrame(t)
		return math.round(t * App.FrameRate) / App.FrameRate
	end

	function App:SetView(view)
		local changed = false
		if view.PixelsPerSecond then
			local pps = math.clamp(view.PixelsPerSecond, App.MinPixelsPerSecond, App.MaxPixelsPerSecond)
			changed = changed or pps ~= self.PixelsPerSecond
			self.PixelsPerSecond = pps
		end
		if view.ScrollTime then
			local scroll = math.max(view.ScrollTime, 0)
			changed = changed or scroll ~= self.ScrollTime
			self.ScrollTime = scroll
		end
		if view.ScrollY then
			local _, total = self:GetRows()
			local visible = self.Shell:LaneViewportHeight()
			local scroll = math.clamp(view.ScrollY, 0, math.max(total - visible, 0))
			changed = changed or scroll ~= self.ScrollY
			self.ScrollY = scroll
		end
		if changed then
			self.Signals.ViewChanged:Fire(self:GetState())
		end
		return changed
	end

	function App:SetZoom(pixelsPerSecond, anchorTime)
		anchorTime = anchorTime or self.Time
		local anchorX = (anchorTime - self.ScrollTime) * self.PixelsPerSecond
		local pps = math.clamp(pixelsPerSecond, App.MinPixelsPerSecond, App.MaxPixelsPerSecond)
		return self:SetView({ PixelsPerSecond = pps, ScrollTime = anchorTime - anchorX / pps })
	end

	function App:SetScrollY(y)
		return self:SetView({ ScrollY = y })
	end

	function App:FitView()
		local width = self.Shell:TimelineWidth()
		local length = math.max(self:GetLength(), 5)
		if width > 40 then
			self:SetView({ PixelsPerSecond = (width - 40) / (length * 1.04), ScrollTime = 0 })
		end
	end

	function App:TimeToX(t)
		return (t - self.ScrollTime) * self.PixelsPerSecond
	end

	function App:XToTime(x)
		return self.ScrollTime + x / self.PixelsPerSecond
	end

	function App:SetSnap(enabled)
		self.Snap = enabled == true
		self:SetSetting("Snap", self.Snap)
		self.Signals.ViewChanged:Fire(self:GetState())
	end

	function App:GetRows()
		if not self.Rows then
			self.Rows = { Rows.Build(self) }
		end
		return self.Rows[1], self.Rows[2]
	end

	function App:IsCollapsed(actor)
		return self.Collapsed[actor or "Scene"] == true
	end

	function App:IsExpanded(track, group)
		local state = self.Expanded and self.Expanded[track]
		return state ~= nil and state[group or "_"] == true
	end

	function App:SetExpanded(track, group, expanded)
		self.Expanded = self.Expanded or setmetatable({}, { __mode = "k" })
		local state = self.Expanded[track]
		if not state then
			state = {}
			self.Expanded[track] = state
		end
		state[group or "_"] = expanded == true
		self.Rows = nil
		self:SetView({ ScrollY = self.ScrollY })
		self.Signals.ViewChanged:Fire(self:GetState())
	end

	function App:SetCollapsed(actor, collapsed)
		self.Collapsed[actor or "Scene"] = collapsed == true
		self.Rows = nil
		self:SetView({ ScrollY = self.ScrollY })
		self.Signals.ViewChanged:Fire(self:GetState())
	end
end
