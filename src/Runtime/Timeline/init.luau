local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Signal = require(script.Util.Signal)
local Schema = require(script.Schema)
local Sampler = require(script.Sampler)
local Actors = require(script.Actors)
local Context = require(script.Context)
local Data = require(script.Data)
local Phases = require(script.Phases)
local Clock = require(script.Clock)

local Timeline = {}
Timeline.__index = Timeline

Timeline.Schema = Schema
Timeline.Sampler = Sampler
Timeline.Version = require(script.Version)
Timeline.FallbackDialogueBox = require(script.Fallback.DialogueBox)
Timeline.GetLength = Data.Length
Timeline.GetServerEvents = Data.ServerEvents
Timeline.ComputeHash = Sampler.Hash
Timeline.Bake = Sampler.Bake
Timeline.Sources = require(script.Sources)

Timeline._process = Phases.Process
Timeline._exitAll = Phases.ExitAll

function Timeline.new(folder, options)
	options = options or {}
	local self = setmetatable({}, Timeline)
	self.Folder = folder
	self.Options = options
	self.Preview = options.Preview == true
	self.TimePosition = 0
	self.Playing = false
	self.HasEnded = false
	self.Destroyed = false
	self.Ended = Signal.new()
	self.Connections = {}
	self.Modules = {}
	self.BindName = "Timeline" .. HttpService:GenerateGUID(false)
	self.Length = Timeline.GetLength(folder)
	self.Context = Context.new(self)
	self.Actors, self.Context.Roles = Actors.Build(folder, options, self.Context.Container)
	Phases.Prepare(self)
	self.Context.Prepared = true
	for id, actor in self.Actors do
		if actor.Kind == "Rig" then
			self.Context:GetRig(id)
		end
	end
	local simulation = self.Phases[1]
	Phases.Process(self, simulation, 0, true)
	simulation.Inclusive = true
	return self
end

function Timeline:_complete()
	self.Playing = false
	self.Context.Playing = false
	Clock.Disconnect(self)
	self.TimePosition = self.Length
	self.HasEnded = true
	self.Ended:Fire("Completed")
end

function Timeline:OnEvent(name, fn)
	local handlers = self.Context.Handlers
	handlers[name] = handlers[name] or {}
	table.insert(handlers[name], fn)
	return {
		Disconnect = function()
			local index = table.find(handlers[name], fn)
			if index then
				table.remove(handlers[name], index)
			end
		end,
	}
end

function Timeline:Play()
	if self.Destroyed or self.Playing then
		return
	end
	if self.HasEnded or self.TimePosition >= self.Length then
		self.HasEnded = false
		self:Seek(0)
	end
	local startAt = self.Options.StartAt
	if not self.Started and startAt and not self.Preview and RunService:IsRunning() then
		self.Origin = startAt
	else
		self.Origin = Clock.Now(self) - self.TimePosition
	end
	self.Started = true
	self.Playing = true
	self.Context.Playing = true
	for _, phase in self.Phases do
		phase.Previous = self.TimePosition
		phase.Inclusive = true
		phase.Done = false
		phase.Primed = false
	end
	Clock.Connect(self)
end

function Timeline:Pause()
	if not self.Playing then
		return
	end
	self.Playing = false
	self.Context.Playing = false
	Clock.Disconnect(self)
	Phases.Halt(self, "Pause")
	Phases.Pause(self)
end

function Timeline:Seek(t)
	if self.Destroyed then
		return
	end
	t = math.clamp(t, 0, self.Length)
	self.TimePosition = t
	for _, phase in self.Phases do
		Phases.Process(self, phase, t, true)
		phase.Previous = t
		phase.Inclusive = true
		phase.Done = false
	end
	if self.Playing then
		self.Origin = Clock.Now(self) - t
	end
	if t < self.Length then
		self.HasEnded = false
	end
end

function Timeline:Stop()
	if self.Destroyed then
		return
	end
	local ended = self.HasEnded
	self.Playing = false
	self.Context.Playing = false
	Clock.Disconnect(self)
	Phases.Halt(self, "Stop")
	Phases.ExitAll(self)
	self.Context.Stopping = true
	self:Seek(0)
	self.Context.Stopping = false
	self.HasEnded = true
	if not ended then
		self.Ended:Fire("Stopped")
	end
end

function Timeline:Wait()
	if self.HasEnded or self.Destroyed then
		return
	end
	self.Ended:Wait()
end

function Timeline:PlayAndWait()
	self:Play()
	self:Wait()
end

function Timeline:Destroy()
	if self.Destroyed then
		return
	end
	self.Playing = false
	self.Context.Playing = false
	Clock.Disconnect(self)
	Phases.ExitAll(self)
	Phases.DestroyAll(self)
	local ctx = self.Context
	ctx:Destroy()
	for _, actor in self.Actors do
		local ok, err = pcall(Actors.Destroy, actor)
		if not ok then
			warn("Timeline: actor restore failed: " .. tostring(err))
		end
	end
	if ctx.OwnsContainer and ctx.Container then
		ctx.Container:Destroy()
	end
	self.Destroyed = true
	if not self.HasEnded then
		self.HasEnded = true
		self.Ended:Fire("Destroyed")
	end
	self.Ended:Destroy()
end

return Timeline
