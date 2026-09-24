local StandIns = require(script.Parent.StandIns)
local Provider = require(script.Parent.Provider)

return function(Preview)
	function Preview:SetCameraLock(enabled)
		enabled = enabled == true
		self.CameraLock = enabled
		self.App:SetSetting("CameraLock", enabled)
		local session = self.Session
		if enabled then
			if not self.Active then
				self:Start(self.App.Time)
			elseif session then
				session.Lock:Engage()
			end
		elseif session then
			session.Lock:Disengage(true)
		end
		self:_changed()
	end

	function Preview:ToggleCameraLock()
		self:SetCameraLock(not self.CameraLock)
	end

	function Preview:_userMovedCamera()
		self.CameraLock = false
		self.App:SetSetting("CameraLock", false)
		self.App:Notify("Camera unlocked because the view was moved", "Info")
		self:_changed()
	end

	function Preview:InCameraGap()
		local session = self.Session
		return session ~= nil and self.Timeline ~= nil and session.Lock:InGap()
	end

	function Preview:SetStudentCount(count)
		count = math.clamp(math.floor(tonumber(count) or StandIns.DefaultCount), 1, 16)
		self.StudentCount = count
		self.App:SetSetting("StudentCount", count)
		self:Restart()
		self:_changed()
	end

	function Preview:GetProviderInfo()
		local document = self.App.Document
		local info = Provider.Resolve(document and document.Folder)
		local session = self.Session
		if session and session.ProviderError and info.Kind == "Game" then
			info.Error = session.ProviderError
			info.Kind = "Error"
		end
		return info
	end
end
