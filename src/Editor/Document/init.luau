local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")

local Signal = require(script.Parent.Signal)

local Document = {}
Document.__index = Document

Document.Deps = nil
Document.Debounce = 0.05

local function sequenceOf(instance, root)
	local current = instance.Parent
	while current and current ~= root do
		if current:IsA("KeyframeSequence") then
			return current
		end
		current = current.Parent
	end
	return nil
end

function Document.new(folder, deps)
	assert(typeof(folder) == "Instance", "Document.new needs a cutscene folder")
	deps = deps or Document.Deps
	local self = setmetatable({}, Document)
	self.Folder = folder
	self.Deps = deps
	self.Schema = deps and deps.Schema
	self.Changed = Signal.new()
	self.Failed = Signal.new()
	self.Connections = {}
	self.Wired = {}
	self.Watched = {}
	self.Touched = {}
	self.Pending = nil
	self.Hooks = { Before = {}, After = {} }
	self.Destroyed = false
	self:_watch()
	return self
end

function Document.Create(name, deps)
	deps = deps or Document.Deps
	local folder
	local id = ChangeHistoryService:TryBeginRecording("CutsceneEditorCreate", "Create cutscene")
	local ok, err = pcall(function()
		local root = ReplicatedStorage:FindFirstChild("Cutscenes")
		if not root then
			root = Instance.new("Folder")
			root.Name = "Cutscenes"
			root.Parent = ReplicatedStorage
		end
		local base = if type(name) == "string" and name ~= "" then name else "Cutscene"
		local unique, index = base, 1
		while root:FindFirstChild(unique) do
			index += 1
			unique = base .. index
		end
		folder = Instance.new("Folder")
		folder.Name = unique
		folder:SetAttribute("Timeline", true)
		local actors = Instance.new("Folder")
		actors.Name = "Actors"
		actors.Parent = folder
		local tracks = Instance.new("Folder")
		tracks.Name = "Tracks"
		tracks.Parent = folder
		folder.Parent = root
	end)
	if id then
		ChangeHistoryService:FinishRecording(id, if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	end
	if not ok then
		error(err, 0)
	end
	return Document.new(folder, deps)
end

function Document.List()
	local list = {}
	local root = ReplicatedStorage:FindFirstChild("Cutscenes")
	if root then
		for _, child in root:GetChildren() do
			if child:IsA("Folder") and child:GetAttribute("Timeline") == true then
				table.insert(list, child)
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)
	return list
end

function Document:_flush()
	local pending = self.Pending
	self.Pending = nil
	if not pending or self.Destroyed then
		return
	end
	for instance in pending.Instances do
		if instance == self.Folder or instance:IsDescendantOf(self.Folder) then
			if not self:_ours(instance) then
				pending.External = true
				break
			end
		elseif not pending.Wrote then
			pending.External = true
			break
		end
	end
	table.clear(self.Touched)
	self.Changed:Fire(pending)
end

function Document:_ours(instance)
	local current = instance
	while current do
		if self.Touched[current] then
			return true
		end
		if current == self.Folder then
			return false
		end
		current = current.Parent
	end
	return false
end

function Document:_mark(instance, structure, flags)
	if self.Destroyed then
		return
	end
	local pending = self.Pending
	if not pending then
		pending = { Instances = {}, Structure = false, External = false, Undo = false, Wrote = false, Document = self }
		self.Pending = pending
		task.delay(Document.Debounce, function()
			self:_flush()
		end)
	end
	if instance then
		pending.Instances[instance] = true
	end
	if structure then
		pending.Structure = true
	end
	for key, value in flags or {} do
		pending[key] = value
	end
end

function Document:_wire(instance, force)
	if self.Wired[instance] then
		return
	end
	if not force then
		local sequence = sequenceOf(instance, self.Folder)
		if sequence and not self.Watched[sequence] then
			return
		end
	end
	self.Wired[instance] = {
		instance.AttributeChanged:Connect(function()
			self:_mark(instance, false)
		end),
		instance.Changed:Connect(function(property)
			if property ~= "Parent" then
				self:_mark(instance, property == "Name")
			end
		end),
	}
end

function Document:_unwire(instance)
	local connections = self.Wired[instance]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
		self.Wired[instance] = nil
	end
end

function Document:WatchSequence(sequence)
	if typeof(sequence) ~= "Instance" or self.Destroyed or self.Watched[sequence] or not sequence:IsDescendantOf(self.Folder) then
		return
	end
	self.Watched[sequence] = true
	for _, descendant in sequence:GetDescendants() do
		self:_wire(descendant, true)
	end
end

function Document:WatchClip(clip)
	if typeof(clip) ~= "Instance" then
		return
	end
	for _, child in clip:GetChildren() do
		if child:IsA("KeyframeSequence") then
			self:WatchSequence(child)
		end
	end
end

function Document:_wireSelection()
	local folder = self.Folder
	for _, instance in Selection:Get() do
		if not self.Wired[instance] and instance:IsDescendantOf(folder) then
			self:_wire(instance, true)
		end
	end
end

function Document:_watch()
	local folder = self.Folder
	self:_wire(folder)
	for _, descendant in folder:GetDescendants() do
		self:_wire(descendant)
	end
	local connections = self.Connections
	table.insert(connections, folder.DescendantAdded:Connect(function(descendant)
		self:_wire(descendant)
		self:_mark(descendant, true)
	end))
	table.insert(connections, folder.DescendantRemoving:Connect(function(descendant)
		self:_unwire(descendant)
		self.Watched[descendant] = nil
		self:_mark(descendant, true)
	end))
	table.insert(connections, Selection.SelectionChanged:Connect(function()
		self:_wireSelection()
	end))
	self:_wireSelection()
	table.insert(connections, folder.AncestryChanged:Connect(function()
		self:_mark(folder, true, { Removed = not folder:IsDescendantOf(game) })
	end))
	table.insert(connections, ChangeHistoryService.OnUndo:Connect(function(name)
		self:_mark(nil, true, { Undo = true, Waypoint = name })
	end))
	table.insert(connections, ChangeHistoryService.OnRedo:Connect(function(name)
		self:_mark(nil, true, { Redo = true, Waypoint = name })
	end))
end

function Document:Touch(instance)
	if instance then
		self.Touched[instance] = true
		self:_mark(instance, false)
	end
	return instance
end

function Document:OnBeforeWrite(fn)
	table.insert(self.Hooks.Before, fn)
end

function Document:OnAfterWrite(fn)
	table.insert(self.Hooks.After, fn)
end

function Document:_record(name, fn, ...)
	if self.Destroyed then
		return nil
	end
	for _, hook in self.Hooks.Before do
		local ok, allowed = pcall(hook, name)
		if ok and allowed == false then
			return nil
		end
	end
	local id = ChangeHistoryService:TryBeginRecording("CutsceneEditor" .. (string.gsub(name, "%W", "")), name)
	self.Writing = (self.Writing or 0) + 1
	local results = table.pack(pcall(fn, self, ...))
	self.Writing -= 1
	if id then
		ChangeHistoryService:FinishRecording(id, if results[1] then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	end
	self.LastRecorded = id ~= nil
	for _, hook in self.Hooks.After do
		task.spawn(hook, name, results[1])
	end
	self:_mark(nil, true, { Wrote = true })
	if not results[1] then
		warn(`CutsceneEditor: {name} failed: {results[2]}`)
		self.Failed:Fire(name, results[2])
		return nil
	end
	return table.unpack(results, 2, results.n)
end

function Document:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	for instance in self.Wired do
		self:_unwire(instance)
	end
	table.clear(self.Connections)
	self.Changed:Destroy()
	self.Failed:Destroy()
end

for _, name in { "Read", "Edit", "Keys" } do
	local module = script:FindFirstChild(name)
	if module then
		require(module)(Document)
	end
end

return Document
