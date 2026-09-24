local SourceLookup = require(script.Parent.Sources)
local UI = require(script.Parent.UI)
local Layout = require(script.Layout)
local Context = require(script.Context)
local Audition = require(script.Audition)
local Header = require(script.Sections.Header)
local Clip = require(script.Sections.Clip)
local Scene = require(script.Sections.Scene)
local Hashes = require(script.Parent.Export.Hashes)

local Inspector = {}
Inspector.__index = Inspector

local ids = setmetatable({}, { __mode = "k" })
local nextId = 0

local function idOf(instance)
	if not instance then
		return "nil"
	end
	local id = ids[instance]
	if not id then
		nextId += 1
		id = nextId
		ids[instance] = id
	end
	return tostring(id)
end

local function childList(instance)
	local parts = {}
	for _, child in instance:GetChildren() do
		table.insert(parts, idOf(child) .. child.ClassName)
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

function Inspector.new(app, frame)
	local self = setmetatable({}, Inspector)
	self.App = app
	self.Frame = frame
	self.Connections = {}
	self.Bindings = {}
	self.Local = {}
	self.Cleanup = {}
	self.Fields = {}
	self.Signature = nil
	self.Target = nil
	self.Pending = false
	self.Hashes = Hashes.new(app.Deps)
	self.Scroll = UI.Create("ScrollingFrame", {
		Name = "Inspector",
		Parent = frame,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = "ScrollBar",
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		BorderSizePixel = 0,
	})
	self.Content = UI.Create("Frame", {
		Name = "Content",
		Parent = self.Scroll,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = { Bottom = 16 },
		List = { Padding = 0 },
	})
	local signals = app.Signals
	table.insert(self.Connections, signals.SelectionChanged:Connect(function()
		self:Schedule()
	end))
	table.insert(self.Connections, signals.DocumentChanged:Connect(function(_, changes)
		self.Hashes:Invalidate(changes)
		self:Schedule()
	end))
	self:Render(true)
	return self
end

function Inspector:Schedule()
	if self.Pending or self.Destroyed then
		return
	end
	self.Pending = true
	task.defer(function()
		self.Pending = false
		if not self.Destroyed then
			self:Render(false)
		end
	end)
end

function Inspector:GetTarget()
	local app = self.App
	local document = app.Document
	if not document then
		return nil, nil
	end
	local selection = app.Selection
	if selection.Primary and document:IsClip(selection.Primary) then
		return "Clip", selection.Primary
	elseif selection.Track and document:IsTrack(selection.Track) then
		return "Track", selection.Track
	elseif selection.Actor and document:IsActor(selection.Actor) then
		return "Actor", selection.Actor
	end
	return "Cutscene", document.Folder
end

function Inspector:_signature(kind, target)
	if not kind then
		return "none"
	end
	local app = self.App
	local parts = { kind, idOf(target) }
	if kind == "Clip" then
		local track = target.Parent
		table.insert(parts, idOf(track) .. tostring(track:GetAttribute("Kind")) .. tostring(track:GetAttribute("Locked")))
		table.insert(parts, childList(target))
		local sequence = SourceLookup.Sequence(target)
		if sequence and sequence ~= target then
			table.insert(parts, tostring(#sequence:GetKeyframes()))
		end
		if track:GetAttribute("Kind") == "Dialogue" then
			local _, info = Context.Provider(app)
			table.insert(parts, info.Kind .. tostring(info.ModulePath) .. #Context.Roles(app))
		end
	elseif kind == "Track" then
		table.insert(parts, tostring(target:GetAttribute("Kind")))
	elseif kind == "Actor" then
		table.insert(parts, tostring(target:GetAttribute("Source")))
		table.insert(parts, childList(target))
	elseif kind == "Cutscene" then
		table.insert(parts, tostring(Context.Registry()))
	end
	return table.concat(parts, "|")
end

function Inspector:Bind(fn)
	table.insert(self.Bindings, fn)
end

function Inspector:OnClear(fn)
	table.insert(self.Cleanup, fn)
end

function Inspector:Connect(signal, fn)
	local connection = signal:Connect(fn)
	table.insert(self.Local, connection)
	return connection
end

function Inspector:Refresh()
	for _, fn in self.Bindings do
		local ok, err = pcall(fn)
		if not ok then
			warn("CutsceneEditor inspector: " .. tostring(err))
		end
	end
end

function Inspector:Commit(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		self.App:Notify("Edit failed: " .. tostring(err), "Error")
	end
	self:Schedule()
end

function Inspector:_clear()
	for _, fn in self.Cleanup do
		pcall(fn)
	end
	for _, connection in self.Local do
		connection:Disconnect()
	end
	table.clear(self.Cleanup)
	table.clear(self.Local)
	table.clear(self.Bindings)
	table.clear(self.Fields)
	UI.Clear(self.Content, { UIListLayout = true, UIPadding = true })
end

function Inspector:_empty()
	local holder = UI.Create("Frame", {
		Name = "Empty",
		Parent = self.Content,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = 16,
	})
	Layout.Text(holder, 1, "Open a cutscene to inspect it.", { TextSize = 13 })
end

function Inspector:Render(force)
	local kind, target = self:GetTarget()
	local signature = self:_signature(kind, target)
	if not force and signature == self.Signature then
		self:Refresh()
		return
	end
	local sameTarget = self.Target == target
	local scroll = self.Scroll.CanvasPosition
	self:_clear()
	self.Signature = signature
	self.Target = target
	self.Kind = kind
	if not kind then
		self:_empty()
		return
	end
	local ok, err = pcall(function()
		Header.Build(self, kind, target, 1)
		if kind == "Clip" then
			Clip.Build(self, target, 10)
		elseif kind == "Track" then
			Scene.Track(self, target, 10)
		elseif kind == "Actor" then
			Scene.Actor(self, target, 10)
		else
			Scene.Cutscene(self, target, 10)
		end
	end)
	if not ok then
		warn("CutsceneEditor inspector: " .. tostring(err))
		Layout.Text(self.Content, 999, "The inspector failed to draw this selection: " .. tostring(err), { Color = "Error" })
	end
	self:Refresh()
	if sameTarget then
		task.defer(function()
			if self.Scroll.Parent then
				self.Scroll.CanvasPosition = scroll
			end
		end)
	else
		self.Scroll.CanvasPosition = Vector2.zero
	end
end

function Inspector:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self:_clear()
	self.Hashes:Destroy()
	Audition.Stop()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Scroll:Destroy()
end

return Inspector
