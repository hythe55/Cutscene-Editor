local Players = game:GetService("Players")

local Actors = require(script.Parent.Actors)
local Rig = require(script.Parent.Rig)
local Sampler = require(script.Parent.Sampler)
local Speech = require(script.Parent.Speech)

local Context = {}
Context.__index = Context

for name, method in Speech do
	Context[name] = method
end

local EMPTY = table.freeze({})

local function defaultGuiParent(preview)
	if preview then
		return game:GetService("CoreGui")
	end
	local player = Players.LocalPlayer
	return player and player:FindFirstChildOfClass("PlayerGui")
end

function Context.new(timeline)
	local options = timeline.Options
	local self = setmetatable({}, Context)
	self.Timeline = timeline
	self.Preview = timeline.Preview
	self.Seeking = false
	self.Playing = false
	self.Stopping = false
	self.Prepared = false
	self.Time = 0
	self.DeltaTime = 0
	self.Camera = workspace.CurrentCamera
	self.Container = options.Container
	if not self.Container then
		local folder = Instance.new("Folder")
		folder.Name = "Timeline_" .. timeline.Folder.Name
		folder.Archivable = false
		folder.Parent = workspace
		self.Container = folder
		self.OwnsContainer = true
	end
	self.GuiParent = options.GuiParent or defaultGuiParent(self.Preview)
	self.Roles = {}
	self.Rigs = {}
	self.RigList = {}
	self.Registries = {}
	self.Samplers = {}
	self.Cleanups = {}
	self.Tracked = {}
	self.Remembered = {}
	self.RememberedList = {}
	self.Handlers = {}
	self.Lines = {}
	return self
end

function Context:Registry(name)
	local registry = self.Registries[name]
	if not registry then
		registry = {}
		self.Registries[name] = registry
	end
	return registry
end

function Context:GetSampler(keyframeSequence)
	local sampler = self.Samplers[keyframeSequence]
	if not sampler then
		sampler = Sampler.new(keyframeSequence)
		self.Samplers[keyframeSequence] = sampler
	end
	return sampler
end

function Context:GetActor(id)
	local actor = id and self.Timeline.Actors[id]
	if actor and actor.Kind == "Player" then
		Actors.Refresh(actor)
	end
	return actor
end

function Context:_rigFor(model, mode)
	local rig = self.Rigs[model]
	if not rig or rig.Mode ~= mode then
		if rig then
			rig:Reset()
			table.remove(self.RigList, table.find(self.RigList, rig))
		end
		rig = Rig.new(model, mode)
		self.Rigs[model] = rig
		table.insert(self.RigList, rig)
	end
	return rig
end

function Context:_rigMode(actor)
	if actor.Kind == "Player" or actor.Kind == "Group" then
		return "Animator"
	end
	local animation = self.Timeline.Modules.Animation
	if animation and animation.UsesAnimator and animation.UsesAnimator(self, actor.Id) then
		return "Animator"
	end
	return "Direct"
end

local function rigsValid(self, cache, actor, mode)
	if cache.Mode ~= mode or cache.Models ~= actor.Models then
		return false
	end
	local parented = 0
	for _, model in actor.Models do
		if model.Parent then
			parented += 1
		end
	end
	if parented ~= #cache.List then
		return false
	end
	for _, rig in cache.List do
		if not rig.Model.Parent or self.Rigs[rig.Model] ~= rig then
			return false
		end
	end
	return true
end

function Context:GetRigs(id)
	local actor = self:GetActor(id)
	if not actor or actor.Kind == "Prop" then
		return EMPTY
	end
	local mode = self:_rigMode(actor)
	local cache = actor.RigCache
	if cache and rigsValid(self, cache, actor, mode) then
		return cache.List
	end
	local rigs = {}
	for _, model in actor.Models do
		if model.Parent then
			table.insert(rigs, self:_rigFor(model, mode))
		end
	end
	actor.RigCache = { Mode = mode, Models = actor.Models, List = rigs }
	return rigs
end

function Context:GetRig(id)
	local actor = self:GetActor(id)
	if not actor or actor.Kind == "Prop" or not actor.Model or not actor.Model.Parent then
		return nil
	end
	return self:_rigFor(actor.Model, self:_rigMode(actor))
end

function Context:GetAnimator(id)
	local actor = self:GetActor(id)
	local model = actor and actor.Model
	if not model then
		return nil
	end
	local host = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildOfClass("AnimationController")
	if not host then
		host = Instance.new("AnimationController")
		host.Archivable = false
		host.Parent = model
		self:Track(host)
	end
	local animator = host:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Archivable = false
		animator.Parent = host
		self:Track(animator)
	end
	return animator
end

function Context:GetJointCFrame(id, jointName)
	local actor = self:GetActor(id)
	local model = actor and actor.Model
	if not model then
		return nil
	end
	if not jointName or jointName == "" then
		return model:GetPivot()
	end
	local rig = self:GetRig(id)
	if rig then
		local cframe = rig:WorldCFrame(jointName)
		if cframe then
			return cframe
		end
	end
	local found = model:FindFirstChild(jointName, true)
	if found then
		if found:IsA("BasePart") then
			return found.CFrame
		elseif found:IsA("Bone") then
			return found.TransformedWorldCFrame
		elseif found:IsA("Attachment") then
			return found.WorldCFrame
		end
	end
	return model:GetPivot()
end

function Context:PoseAt(id, time)
	local actor = self:GetActor(id)
	local rig = self:GetRig(id)
	local pose = {}
	if actor and actor.Idle and actor.Idle.Length > 0 then
		actor.Idle:Sample(time % actor.Idle.Length, function(key, cframe)
			pose[key] = cframe
		end, rig and actor.Idle:Skip(rig))
	end
	local animation = self.Timeline.Modules.Animation
	if animation and animation.PoseAt then
		animation.PoseAt(self, id, time, pose)
	end
	return pose
end

function Context:PivotAt(id, time)
	local actor = self:GetActor(id)
	local move = self.Timeline.Modules.Move
	local pivot = move and move.PivotAt and move.PivotAt(self, id, time)
	return pivot or (actor and actor.SourcePivot)
end

function Context:ProbeJointCFrame(id, jointName, time)
	local pivot = self:PivotAt(id, time)
	if not jointName or jointName == "" then
		return pivot
	end
	local rig = self:GetRig(id)
	if not rig or not pivot then
		return pivot
	end
	return rig:WorldCFrame(jointName, self:PoseAt(id, time), pivot)
end

function Context:Track(instance)
	table.insert(self.Tracked, instance)
	return instance
end

function Context:OnCleanup(fn)
	table.insert(self.Cleanups, fn)
	return fn
end

function Context:Remember(instance, property)
	local record = self.Remembered[instance]
	if not record then
		record = {}
		self.Remembered[instance] = record
	end
	if not record[property] then
		record[property] = { Value = instance[property] }
		table.insert(self.RememberedList, { instance, property })
	end
	return record[property].Value
end

function Context:Recall(instance, property)
	local record = self.Remembered[instance]
	return record and record[property] and record[property].Value
end

function Context:Restore(instance, property)
	local record = self.Remembered[instance]
	local entry = record and record[property]
	if entry and instance[property] ~= entry.Value then
		instance[property] = entry.Value
	end
end

function Context:FireEvent(name, phase, data)
	for _, fn in self.Handlers[name] or {} do
		task.spawn(fn, phase, data)
	end
	for _, fn in self.Handlers["*"] or {} do
		task.spawn(fn, name, phase, data)
	end
end

function Context:ClaimCamera(state)
	local camera = self.Camera
	if not self.CameraSaved then
		self.CameraSaved = {
			CameraType = camera.CameraType,
			CFrame = camera.CFrame,
			Focus = camera.Focus,
			FieldOfView = camera.FieldOfView,
			CameraSubject = camera.CameraSubject,
		}
	end
	self.CameraOwner = state
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
end

function Context:_restoreCamera()
	local saved, camera = self.CameraSaved, self.Camera
	if not saved or not camera then
		return
	end
	camera.CameraType = saved.CameraType
	camera.FieldOfView = saved.FieldOfView
	if self.Preview then
		camera.CFrame = saved.CFrame
		camera.Focus = saved.Focus
	elseif saved.CameraSubject and saved.CameraSubject.Parent then
		camera.CameraSubject = saved.CameraSubject
	else
		local player = Players.LocalPlayer
		local character = player and player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

function Context:ReleaseCamera(state)
	if self.CameraOwner ~= state then
		return
	end
	self.CameraOwner = nil
	self:_restoreCamera()
end

function Context:SetHidden(id, source, amount)
	local actor = self.Timeline.Actors[id]
	if actor then
		actor.HideSources[source] = amount
		actor.HideDirty = true
	end
end

function Context:_flushHidden()
	for _, actor in self.Timeline.Actors do
		if actor.HideDirty then
			actor.HideDirty = false
			local amount = 0
			for _, value in actor.HideSources do
				amount = math.max(amount, value)
			end
			Actors.SetTransparency(actor, amount)
		end
	end
end

function Context:Destroy()
	for i = #self.Cleanups, 1, -1 do
		local ok, err = pcall(self.Cleanups[i])
		if not ok then
			warn("Timeline cleanup failed: " .. tostring(err))
		end
	end
	table.clear(self.Cleanups)
	for _, rig in self.RigList do
		pcall(rig.Reset, rig)
	end
	for i = #self.RememberedList, 1, -1 do
		local instance, property = self.RememberedList[i][1], self.RememberedList[i][2]
		pcall(self.Restore, self, instance, property)
	end
	for i = #self.Tracked, 1, -1 do
		pcall(game.Destroy, self.Tracked[i])
	end
	table.clear(self.Tracked)
	if self.CameraSaved then
		pcall(self._restoreCamera, self)
	end
	table.clear(self.Handlers)
end

return Context
