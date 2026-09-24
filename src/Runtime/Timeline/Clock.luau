local RunService = game:GetService("RunService")

local Phases = require(script.Parent.Phases)

local Clock = {}

local function realtime(timeline)
	return timeline.Preview or not RunService:IsRunning()
end

function Clock.Now(timeline)
	if realtime(timeline) then
		return os.clock()
	end
	return workspace:GetServerTimeNow()
end

function Clock.Elapsed(timeline)
	return Clock.Now(timeline) - timeline.Origin
end

local function tick(timeline, phase, t)
	if phase.Done then
		return
	end
	if t < 0 then
		if not phase.Primed then
			phase.Primed = true
			Phases.Process(timeline, phase, 0, true)
			phase.Inclusive = true
		end
		return
	end
	local finished = t >= timeline.Length
	if finished then
		t = timeline.Length
	end
	timeline.TimePosition = t
	Phases.Process(timeline, phase, t, false)
	if finished then
		phase.Done = true
		for _, other in timeline.Phases do
			if not other.Done then
				return
			end
		end
		timeline:_complete()
	end
end

local function releaseRigs(timeline, phase)
	if phase.Done or (phase.Primed and Clock.Elapsed(timeline) < 0) then
		return
	end
	for _, rig in timeline.Context.RigList do
		rig:Release()
	end
end

function Clock.Connect(timeline)
	local connections = timeline.Connections
	local simulation, render = timeline.Phases[1], timeline.Phases[2]
	if realtime(timeline) then
		connections.Step = RunService.PreRender:Connect(function()
			local t = Clock.Elapsed(timeline)
			tick(timeline, simulation, t)
			tick(timeline, render, t)
		end)
		return
	end
	connections.Release = RunService.PreAnimation:Connect(function()
		releaseRigs(timeline, simulation)
	end)
	if RunService:IsClient() then
		connections.Step = RunService.PreSimulation:Connect(function()
			tick(timeline, simulation, Clock.Elapsed(timeline))
		end)
		RunService:BindToRenderStep(timeline.BindName, Enum.RenderPriority.Camera.Value, function()
			tick(timeline, render, Clock.Elapsed(timeline))
		end)
		timeline.Bound = true
	else
		connections.Step = RunService.PreSimulation:Connect(function()
			local t = Clock.Elapsed(timeline)
			tick(timeline, simulation, t)
			tick(timeline, render, t)
		end)
	end
end

function Clock.Disconnect(timeline)
	for _, connection in timeline.Connections do
		connection:Disconnect()
	end
	table.clear(timeline.Connections)
	if timeline.Bound then
		timeline.Bound = false
		RunService:UnbindFromRenderStep(timeline.BindName)
	end
end

return Clock
