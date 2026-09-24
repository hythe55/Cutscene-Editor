local Live = require(script.Parent.Live)
local PoseMath = require(script.Parent.PoseMath)
local PoseEdit = require(script.Parent.PoseEdit)

local PoseDrag = {}
PoseDrag.__index = PoseDrag

function PoseDrag.new(tool)
	local self = setmetatable({}, PoseDrag)
	self.Tool = tool
	self.Active = false
	self.State = nil
	return self
end

function PoseDrag:BaseValue(jointKey, clipTime)
	local tool = self.Tool
	local info = tool.Info
	local keyframe = PoseMath.KeyframeAt(info, clipTime)
	local pose = keyframe and PoseMath.PoseOf(keyframe, jointKey)
	if pose and pose.Weight > 0 then
		return pose.CFrame, keyframe
	end
	if tool.Keyed[jointKey] then
		local sampler = PoseMath.Sampler(tool.App.Deps, info)
		return (sampler and sampler:SampleKey(jointKey, clipTime)) or CFrame.identity, keyframe
	end
	local rig = tool:Rig()
	if rig and rig.Joints[jointKey] then
		return rig:TransformToPose(rig:Transform(jointKey)), keyframe
	end
	return CFrame.identity, keyframe
end

local function liveKeyframe(clone, time)
	for _, keyframe in clone:GetKeyframes() do
		if math.abs(keyframe.Time - time) < 1e-5 then
			return keyframe
		end
	end
	local keyframe = Instance.new("Keyframe")
	keyframe.Time = time
	keyframe.Parent = clone
	return keyframe
end

function PoseDrag:_liveCopy(state)
	local tool = self.Tool
	local info = tool.Info
	local track = Live.State(tool.App, info.Clip)
	if not track or not info.Sequence then
		return nil
	end
	local clone = info.Sequence:Clone()
	local time = if state.Keyframe then state.Keyframe.Time else state.ClipTime
	local pose, weighted = PoseEdit.Chain(clone, liveKeyframe(clone, time), state.Joint)
	if not weighted then
		pose.EasingStyle, pose.EasingDirection = PoseMath.InsertEasing(info, state.Joint, time)
	end
	if state.Hold then
		for _, holdTime in PoseEdit.HoldTimes(info, time) do
			local hold, existed = PoseEdit.Chain(clone, liveKeyframe(clone, holdTime), state.Joint)
			if not existed then
				hold.CFrame = state.Hold
				hold.EasingStyle, hold.EasingDirection = PoseMath.InsertEasing(info, state.Joint, holdTime)
			end
		end
	end
	return { Track = track, Original = track.Sampler, Clone = clone, Pose = pose, Dirty = false }
end

function PoseDrag:Begin()
	local tool = self.Tool
	if self.Active or not tool:_ready(true) then
		tool.Gizmo:Cancel()
		return false
	end
	local base, keyframe = self:BaseValue(tool.Joint, tool.ClipTime)
	local state = {
		Base = base,
		Joint = tool.Joint,
		ClipTime = tool.ClipTime,
		Keyframe = keyframe,
		Hold = if tool.Keyed[tool.Joint] then nil else base,
	}
	state.Live = self:_liveCopy(state)
	self.State = state
	self.Active = true
	return true
end

function PoseDrag:_set(value)
	local state = self.State
	if not state then
		return
	end
	state.Value = value
	local live = state.Live
	if live then
		live.Pose.CFrame = value
		live.Pose.Weight = 1
		live.Dirty = true
	end
	self.Tool.Dirty = true
end

function PoseDrag:Rotate(axis, angle)
	local state = self.State
	if state then
		self:_set(PoseMath.Rotate(state.Base, axis, angle))
	end
end

function PoseDrag:Move(offset)
	local state = self.State
	if state then
		local rig = self.Tool:Rig()
		self:_set(PoseMath.Translate(state.Base, offset, rig and rig.Scale or 1))
	end
end

function PoseDrag:Flush()
	local state = self.State
	local live = state and state.Live
	if not live or not live.Dirty then
		return
	end
	live.Dirty = false
	live.Track.Sampler = self.Tool.App.Deps.Sampler.new(live.Clone)
	Live.Reseek(self.Tool.App)
	self.Tool.Dirty = true
end

function PoseDrag:_restore(state)
	local live = state and state.Live
	if live then
		live.Track.Sampler = live.Original
		live.Clone:Destroy()
		Live.Reseek(self.Tool.App)
	end
end

function PoseDrag:Finish()
	local state = self.State
	if not self.Active or not state then
		return nil
	end
	self.Active = false
	self.State = nil
	if not state.Value then
		self:_restore(state)
		return nil
	end
	if state.Live then
		state.Live.Clone:Destroy()
	end
	local tool = self.Tool
	local result = PoseEdit.SetJoint(tool.App.Document, tool.Info, state.ClipTime, state.Joint, state.Value, state.Hold)
	if not result and state.Live then
		state.Live.Track.Sampler = state.Live.Original
		Live.Reseek(tool.App)
	end
	tool.Dirty = true
	return result
end

function PoseDrag:Cancel()
	local state = self.State
	self.Active = false
	self.State = nil
	if state then
		self:_restore(state)
	end
end

return PoseDrag
