local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")

local StandIns = require(script.StandIns)
local CameraLock = require(script.CameraLock)
local Provider = require(script.Provider)
local Outside = require(script.Outside)

local Preview = {}
Preview.__index = Preview

Preview.Provider = Provider
Preview.StandIns = StandIns
Preview.RestartGap = 0.3

local COMMIT = Enum.FinishRecordingOperation.Commit
local CANCEL = Enum.FinishRecordingOperation.Cancel

local function folder(name, parent)
	local instance = Instance.new("Folder")
	instance.Name = name
	instance.Archivable = false
	instance.Parent = parent
	return instance
end

function Preview.new(app)
	local self = setmetatable({}, Preview)
	self.App = app
	self.Active = false
	self.Playing = false
	self.Suspended = false
	self.Timeline = nil
	self.Session = nil
	self.Recording = nil
	self.CameraLock = app:GetSetting("CameraLock", false) == true
	self.StudentCount = app:GetSetting("StudentCount", StandIns.DefaultCount)
	self.LastGap = false
	return self
end

function Preview:GetState()
	local session = self.Session
	return {
		Active = self.Active,
		Playing = self.Playing,
		Suspended = self.Suspended,
		CameraLock = self.CameraLock,
		Engaged = session ~= nil and session.Lock.Engaged,
		InGap = self:InCameraGap(),
		Provider = session and session.ProviderInfo and session.ProviderInfo.Label,
		StandIns = session and #session.StandIns.Models or 0,
		Time = self.Timeline and self.Timeline.TimePosition,
	}
end

function Preview:_changed()
	local app = self.App
	if not app.Destroyed then
		app.Signals.PreviewChanged:Fire(self:GetState())
	end
end

function Preview:_begin()
	if self.Recording then
		return
	end
	local ok, id = pcall(ChangeHistoryService.TryBeginRecording, ChangeHistoryService, "CutsceneEditorPreview", "Cutscene preview")
	self.Recording = if ok then id else nil
	if self.Recording then
		self.Outside = Outside.new()
	end
end

function Preview:_finish()
	local id = self.Recording
	local outside = self.Outside
	self.Recording, self.Outside = nil, nil
	local document = self.App.Document
	local pending = document and document.Pending
	if outside and pending and next(pending.Instances) and not pending.Undo and not pending.Redo then
		outside:Mark("unflushed cutscene change")
	end
	local keep = outside == nil or outside.Changed
	self.LastOutside = outside and outside.Reason
	if outside then
		outside:Destroy()
	end
	if id and ChangeHistoryService:IsRecordingInProgress(id) then
		pcall(ChangeHistoryService.FinishRecording, ChangeHistoryService, id, if keep then COMMIT else CANCEL)
	end
end

function Preview:_openSession()
	local app = self.App
	local document = app.Document
	local container = folder("CutsceneEditorPreview", workspace)
	local session = {
		Container = container,
		Actors = folder("Actors", container),
		StandInFolder = folder("StandIns", container),
		GuiFolder = folder("CutsceneEditorPreview", CoreGui),
	}
	session.StandIns = StandIns.Build(document, self.StudentCount, session.StandInFolder)
	session.ProviderInfo = Provider.Resolve(document.Folder)
	session.Lock = CameraLock.new(container, function()
		self:_userMovedCamera()
	end)
	self.Session = session
	return session
end

function Preview:_closeSession()
	local session = self.Session
	self.Session = nil
	if not session then
		return
	end
	pcall(session.Lock.Destroy, session.Lock)
	pcall(StandIns.Release)
	pcall(game.Destroy, session.GuiFolder)
	pcall(game.Destroy, session.Container)
end

function Preview:_providerFailed(session, err)
	if self.Session ~= session or err == session.ProviderError then
		return
	end
	session.ProviderError = err
	self.App:Notify("Dialogue provider failed, using the built-in box: " .. err, "Warn")
	self:_changed()
end

function Preview:_buildBox()
	local session = self.Session
	local reported = false
	local box, gui, provider, err, pending = Provider.Build(session.ProviderInfo, self.App.Deps, session.GuiFolder, function(message)
		reported = true
		self:_providerFailed(session, message)
	end)
	session.Box, session.BoxGui, session.ProviderTable = box, gui, provider
	if err and pending then
		task.delay(0.25, function()
			if not reported then
				self:_providerFailed(session, err)
			end
		end)
	elseif err then
		self:_providerFailed(session, err)
	end
	return box
end

function Preview:_destroyBox()
	local session = self.Session
	if not session then
		return
	end
	if session.Box then
		pcall(session.Box.Destroy, session.Box)
	end
	if session.BoxGui then
		pcall(game.Destroy, session.BoxGui)
	end
	session.Box, session.BoxGui = nil, nil
end

function Preview:_buildTimeline(t)
	local app = self.App
	local session = self.Session
	local document = app.Document
	if not session or not document then
		return false
	end
	local box = self:_buildBox()
	local standIns = session.StandIns
	local ok, timeline = pcall(app.Deps.Timeline.new, document.Folder, {
		Preview = true,
		Container = session.Actors,
		GuiParent = session.GuiFolder,
		DialogueBox = box,
		Characters = standIns.Characters,
		Roles = standIns.Roles,
		Students = standIns.Students,
	})
	if not ok then
		self:_destroyBox()
		app:Notify("Preview failed: " .. tostring(timeline), "Error")
		return false
	end
	session.Lock:Attach(timeline)
	self.Timeline = timeline
	timeline.Ended:Connect(function(reason)
		if reason == "Completed" and self.Timeline == timeline then
			self.Playing = false
			app:SetTime(timeline.TimePosition, "Preview")
			self:_changed()
		end
	end)
	timeline:Seek(math.clamp(t or 0, 0, timeline.Length))
	session.Lock:Write()
	return true
end

function Preview:_teardownTimeline()
	local timeline = self.Timeline
	self.Timeline = nil
	if self.Session then
		self.Session.Lock:Detach()
	end
	if timeline then
		local ok, err = pcall(timeline.Destroy, timeline)
		if not ok then
			warn("CutsceneEditor: preview cleanup failed: " .. tostring(err))
		end
	end
	self:_destroyBox()
end

function Preview:_step()
	local session = self.Session
	local timeline = self.Timeline
	if timeline and self.Playing then
		self.App:SetTime(timeline.TimePosition, "Preview")
	end
	if session then
		session.Lock:Write()
	end
	local gap = self:InCameraGap()
	if gap ~= self.LastGap then
		self.LastGap = gap
		self:_changed()
	end
end

function Preview:Start(t)
	if self.Active then
		return true
	end
	local app = self.App
	if not app.Document then
		return false
	end
	if RunService:IsRunning() then
		app:Notify("Preview works in edit mode only", "Warn")
		return false
	end
	local sinceStop = os.clock() - (self.LastStop or 0)
	if sinceStop < Preview.RestartGap then
		task.wait(Preview.RestartGap - sinceStop)
		if self.Active or not app.Document then
			return self.Active
		end
	end
	local ok, err = pcall(self._openSession, self)
	if not ok then
		self:_closeSession()
		app:Notify("Preview failed: " .. tostring(err), "Error")
		return false
	end
	self.Active = true
	self:_begin()
	if not self:_buildTimeline(t or app.Time) then
		self:Stop()
		return false
	end
	if self.CameraLock then
		self.Session.Lock:Engage()
	end
	app:SetTime(self.Timeline.TimePosition, "Preview")
	self.StepConnection = RunService.PreRender:Connect(function()
		self:_step()
	end)
	self:_changed()
	return true
end

function Preview:Play()
	if not self.Active and not self:Start(self.App.Time) then
		return false
	end
	local timeline = self.Timeline
	if not timeline or self.Playing then
		return false
	end
	if timeline.TimePosition >= timeline.Length - 1e-3 then
		timeline:Seek(0)
	end
	timeline:Play()
	self.Playing = true
	self:_changed()
	return true
end

function Preview:Pause()
	local timeline = self.Timeline
	if not self.Playing or not timeline then
		return
	end
	timeline:Pause()
	self.Playing = false
	self.App:SetTime(timeline.TimePosition, "Preview")
	self:_changed()
end

function Preview:Toggle()
	if self.Playing then
		self:Pause()
	else
		self:Play()
	end
end

function Preview:Seek(t)
	if self.Suspended then
		return
	end
	if not self.Active and not self:Start(t) then
		return
	end
	local timeline = self.Timeline
	if timeline then
		timeline:Seek(math.clamp(t, 0, timeline.Length))
		self.Session.Lock:Write()
	end
end

function Preview:Stop()
	if not self.Active then
		return
	end
	if self.StepConnection then
		self.StepConnection:Disconnect()
		self.StepConnection = nil
	end
	self.Playing = false
	self.Suspended = false
	self:_teardownTimeline()
	self:_closeSession()
	self:_finish()
	self.Active = false
	self.LastGap = false
	self.LastStop = os.clock()
	self:_changed()
end

function Preview:Restart()
	if not self.Active then
		return
	end
	local t = self.App.Time
	self:Stop()
	self:Start(t)
end

function Preview:Destroy()
	self:Stop()
	StandIns.Clear()
end

for _, name in { "Options", "Edits" } do
	require(script[name])(Preview)
end

return Preview
