local Editor = script.Parent

local Signal = require(Editor.Signal)
local Theme = require(Editor.Theme)
local UI = require(Editor.UI)
local Document = require(Editor.Document)
local JointGroups = require(Editor.JointGroups)
local Preview = require(Editor.Preview)
local Shell = require(script.Shell)
local Features = require(script.Features)
local Modal = require(script.Modal)
local Status = require(script.Status)

local App = {}
App.__index = App

App.RowHeight = 30
App.GroupHeight = 26
App.SubRowHeight = 22
App.RulerHeight = 28
App.ToolbarHeight = 40
App.StatusHeight = 24
App.TabHeight = 30
App.MinPixelsPerSecond = 2
App.MaxPixelsPerSecond = 2400
App.FrameRate = 30

local SIGNALS = { "DocumentChanged", "SelectionChanged", "TimeChanged", "ViewChanged", "PreviewChanged", "ThemeChanged" }

local function emptySelection()
	return { Clips = {}, Primary = nil, Track = nil, Actor = nil, Key = nil }
end

function App.new(plugin, container, deps)
	assert(typeof(container) == "Instance" and (container:IsA("LayerCollector") or container:IsA("GuiObject")), "App needs a GUI container")
	local self = setmetatable({}, App)
	self.Plugin = plugin
	self.Widget = container
	self.Deps = deps
	self.Destroyed = false
	self.Connections = {}
	self.Signals = {}
	for _, name in SIGNALS do
		self.Signals[name] = Signal.new()
	end
	Document.Deps = deps
	self.Theme = Theme.new(deps.Schema)
	UI.SetTheme(self.Theme)
	self.UI = UI
	table.insert(self.Connections, self.Theme.Changed:Connect(function()
		self.Signals.ThemeChanged:Fire(self.Theme)
	end))
	table.insert(self.Connections, self.Signals.SelectionChanged:Connect(function(selection)
		if self.Document and selection and selection.Primary then
			self.Document:WatchClip(selection.Primary)
		end
	end))
	self.Document = nil
	self.Selection = emptySelection()
	self.Time = 0
	self.PixelsPerSecond = 60
	self.ScrollTime = 0
	self.ScrollY = 0
	self.Snap = self:GetSetting("Snap", true) ~= false
	self.Collapsed = {}
	self.Features = {}
	self.Shell = Shell.new(self, container)
	UI.SetLayer(self.Shell.Layer)
	self.Status = Status.new(self, self.Shell.Status)
	self.Preview = Preview.new(self)
	Features.MountAll(self)
	self.Shell:Refresh()
	local last = self:GetSetting("LastCutscene")
	local list = Document.List()
	local initial = nil
	for _, folder in list do
		if folder.Name == last then
			initial = folder
		end
	end
	self:OpenCutscene(initial or list[1])
	return self
end

function App:GetSetting(name, default)
	local plugin = self.Plugin
	if not plugin then
		return default
	end
	local ok, value = pcall(plugin.GetSetting, plugin, "CutsceneEditor." .. name)
	if ok and value ~= nil then
		return value
	end
	return default
end

function App:SetSetting(name, value)
	local plugin = self.Plugin
	if plugin then
		pcall(plugin.SetSetting, plugin, "CutsceneEditor." .. name, value)
	end
end

function App:OpenCutscene(folder)
	if self.Destroyed then
		return nil
	end
	if self.Document and self.Document.Folder == folder then
		return self.Document
	end
	self:_stopWatching()
	self.Preview:Stop()
	if self.Document then
		self.Document:Destroy()
		self.Document = nil
	end
	for _, connection in self.DocumentConnections or {} do
		connection:Disconnect()
	end
	self.DocumentConnections = {}
	self.Selection = emptySelection()
	self.Collapsed = {}
	self.Expanded = setmetatable({}, { __mode = "k" })
	self.Rows = nil
	self.Time = 0
	self.ScrollTime = 0
	self.ScrollY = 0
	if folder then
		local document = Document.new(folder, self.Deps)
		self.Document = document
		self:SetSetting("LastCutscene", folder.Name)
		table.insert(self.DocumentConnections, document.Changed:Connect(function(changes)
			self:_documentChanged(changes)
		end))
		table.insert(self.DocumentConnections, document.Failed:Connect(function(name, err)
			self:Notify(`{name} failed: {err}`, "Error")
		end))
		document:OnBeforeWrite(function(name)
			return self.Preview:BeforeWrite(name)
		end)
		document:OnAfterWrite(function(name, ok)
			self.Preview:AfterWrite(name, ok)
		end)
		self:FitView()
	end
	self.Shell:Refresh()
	self.Signals.DocumentChanged:Fire(self.Document, { Opened = true, Structure = true, Instances = {} })
	self.Signals.SelectionChanged:Fire(self.Selection)
	self.Signals.TimeChanged:Fire(self.Time)
	self.Signals.ViewChanged:Fire(self:GetState())
	return self.Document
end

function App:CreateCutscene(name)
	self.Preview:Stop()
	local ok, result = pcall(Document.Create, name, self.Deps)
	if not ok then
		self:Notify("Could not create the cutscene: " .. tostring(result), "Error")
		return nil
	end
	result:Destroy()
	self:OpenCutscene(result.Folder)
	self:Notify(`Created {result.Folder:GetFullName()}`, "Info")
	return self.Document
end

function App:_documentChanged(changes)
	local document = self.Document
	if not document then
		return
	end
	if changes.Removed then
		local name = document.Folder.Name
		local view = { Time = self.Time, PixelsPerSecond = self.PixelsPerSecond, ScrollTime = self.ScrollTime, ScrollY = self.ScrollY }
		self:Notify(`"{name}" was removed from the place; it reopens if it comes back`, "Warn")
		self:OpenCutscene(nil)
		self:_watchReopen(name, view)
		return
	end
	self.Rows = nil
	JointGroups.Invalidate()
	self:_pruneSelection()
	self.Preview:DocumentChanged(changes)
	self.Signals.DocumentChanged:Fire(document, changes)
end

function App:GetLength()
	return if self.Document then self.Document:GetLength() else 0
end

function App:SetTime(t, source)
	if type(t) ~= "number" or t ~= t then
		return
	end
	t = math.max(t, 0)
	if source ~= "Preview" and self.Document then
		self.Preview:Seek(t)
		if self.Preview.Timeline then
			t = self.Preview.Timeline.TimePosition
		end
	end
	if t == self.Time then
		return
	end
	self.Time = t
	self.Signals.TimeChanged:Fire(t)
end

function App:ShowTab(name)
	return self.Shell:ShowTab(name, true)
end

function App:Notify(text, kind)
	if self.Status then
		self.Status:Notify(text, kind or "Info")
	end
end

function App:Modal(props)
	return Modal.Show(self, props)
end

function App:GetState()
	local selection = {}
	for clip in self.Selection.Clips do
		table.insert(selection, clip)
	end
	local preview = self.Preview
	return {
		Document = self.Document and self.Document.Folder,
		Time = self.Time,
		Length = self:GetLength(),
		PixelsPerSecond = self.PixelsPerSecond,
		ScrollTime = self.ScrollTime,
		ScrollY = self.ScrollY,
		Snap = self.Snap,
		Selection = selection,
		Primary = self.Selection.Primary,
		Track = self.Selection.Track,
		Actor = self.Selection.Actor,
		Key = self.Selection.Key,
		PreviewActive = preview and preview.Active or false,
		Playing = preview and preview.Playing or false,
		CameraLocked = preview and preview.CameraLock or false,
		Theme = self.Theme.Name,
	}
end

function App:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self:_stopWatching()
	if self.Preview then
		self.Preview:Destroy()
	end
	Features.DestroyAll(self)
	if self.Document then
		self.Document:Destroy()
		self.Document = nil
	end
	for _, connection in self.DocumentConnections or {} do
		connection:Disconnect()
	end
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	if self.Status then
		self.Status:Destroy()
	end
	if self.Shell then
		self.Shell:Destroy()
	end
	for _, signal in self.Signals do
		signal:Destroy()
	end
	self.Theme:Destroy()
end

for _, name in { "Selection", "View", "Reopen" } do
	require(script[name])(App)
end

return App
