local RunService = game:GetService("RunService")

local Gizmo = require(script.Parent.Gizmo)
local Markers = require(script.Parent.Markers)
local Live = require(script.Parent.Live)
local Picker = require(script.Parent.Picker)
local PoseMath = require(script.Parent.PoseMath)
local PosePanel = require(script.Parent.PosePanel)
local PoseDrag = require(script.Parent.PoseDrag)

local PoseTool = {}
PoseTool.__index = PoseTool

PoseTool.Colors = {
	Joint = Color3.fromRGB(64, 196, 255),
	Hover = Color3.fromRGB(255, 225, 150),
	Bone = Color3.fromRGB(64, 196, 255),
}

local function setUpConnections(self)
	local signals = self.App.Signals
	local connections = self.Connections
	for _, name in { "SelectionChanged", "DocumentChanged", "PreviewChanged" } do
		table.insert(connections, signals[name]:Connect(function()
			self:Sync()
		end))
	end
	table.insert(connections, signals.TimeChanged:Connect(function()
		self:_timeChanged()
	end))
	table.insert(connections, signals.ThemeChanged:Connect(function()
		self.Panel:Refresh()
	end))
	table.insert(connections, self.Frame:GetPropertyChangedSignal("Visible"):Connect(function()
		self:Sync(true)
	end))
	table.insert(connections, RunService.PreRender:Connect(function()
		self:_frame()
	end))
end

function PoseTool.new(app, frame)
	local self = setmetatable({}, PoseTool)
	self.App = app
	self.Frame = frame
	self.Connections = {}
	self.Mode = "Rotate"
	self.Step = app:GetSetting("PoseStep", 5)
	self.RoleScope = "Joint"
	self.AutoPick = app:GetSetting("PoseAutoPick", true) ~= false
	self.Picking = false
	self.Markers = Markers.new("CutsceneEditorPoseTool", true)
	self.Drag = PoseDrag.new(self)
	self.Gizmo = Gizmo.new({
		Name = "CutsceneEditorPoseGizmo",
		Mode = self.Mode,
		OnBegin = function()
			self.Drag:Begin()
		end,
		OnRotate = function(axis, angle)
			self.Drag:Rotate(axis, angle)
		end,
		OnMove = function(face, distance)
			self.Drag:Move(Gizmo.MoveDelta(face, distance))
		end,
		OnEnd = function()
			self.Drag:Finish()
		end,
	})
	self.Picker = Picker.new(app.Plugin, {
		OnClick = function(ray)
			if not self.Gizmo:IsHovered() then
				self:PickAt(ray)
			end
		end,
		OnHover = function(ray)
			self.HoverRay = ray
			self.Dirty = true
		end,
		OnChanged = function(active)
			if not active and self.Picking and self.Info and self:IsOpen() then
				self.AutoPick = false
			end
			self.Picking = active
			self.PanelDirty = true
		end,
	})
	self.Panel = PosePanel.new(self, frame)
	setUpConnections(self)
	self:Sync()
	return self
end

function PoseTool:IsOpen()
	return self.Frame.Visible
end

function PoseTool:Sync(opened)
	local app = self.App
	local document = app.Document
	local clip = app.Selection.Primary
	if not (document and clip and document:IsClip(clip) and document:KindOf(clip) == "Animation") then
		clip = nil
	end
	local changed = clip ~= (self.Info and self.Info.Clip)
	if changed then
		self.Drag:Cancel()
		self.HoverKey = nil
	end
	self.Info = if clip then PoseMath.Info(document, clip) else nil
	self.Keyed = if clip then PoseMath.Keyed(self.Info) else {}
	if clip and (changed or opened) and self:IsOpen() and not Live.Timeline(app) and not (app.Preview and app.Preview.Suspended) then
		Live.Ensure(app)
	end
	local rig = self:Rig()
	if self.Joint and rig and not rig.Joints[self.Joint] then
		self.Joint = nil
	end
	self:_updatePicker()
	self:_timeChanged()
end

function PoseTool:_updatePicker()
	self.Picker:SetActive(self.Info ~= nil and self:IsOpen() and self.AutoPick)
	self.Picking = self.Picker.Active
	self.PanelDirty = true
end

function PoseTool:_timeChanged()
	local info = self.Info
	self.ClipTime = info and PoseMath.ClipTime(info, self.App.Time)
	self.Keyframe = info and PoseMath.KeyframeAt(info, self.ClipTime)
	self.Dirty = true
	self.PanelDirty = true
end

function PoseTool:Rig()
	local info = self.Info
	return info and Live.Rig(self.App, info.Actor)
end

function PoseTool:JointFrame(key)
	local rig = self:Rig()
	return rig and Live.JointFrame(rig, key or self.Joint)
end

function PoseTool:StatusText()
	local info = self.Info
	if not info then
		return ""
	end
	local joint = self.Joint and string.match(self.Joint, "[^/]+$")
	local parts = {}
	if Live.Locked(info.Clip) then
		table.insert(parts, "This track is locked; unlock it in the lane header to edit.")
	end
	if not Live.Timeline(self.App) then
		table.insert(parts, "Start the preview to see the rig.")
	end
	if not self.ClipTime then
		table.insert(parts, "The playhead is outside this clip; click the strip or a keyframe to jump in.")
	elseif self.Keyframe then
		table.insert(parts, string.format("Keyframe %d at %.2fs.", table.find(info.Keyframes, self.Keyframe) or 0, self.Keyframe.Time))
	else
		table.insert(parts, string.format("No keyframe at %.2fs: dragging adds one for the joint.", self.ClipTime))
	end
	if joint then
		table.insert(parts, `Editing {joint}{if self.Keyed[self.Joint] then "" else " (not keyed in this clip yet)"}.`)
	elseif self.Picker.Active then
		table.insert(parts, "Click a joint on the rig in the viewport.")
	end
	if self.HoverKey and self.Picker.Active then
		table.insert(parts, "Hover: " .. string.match(self.HoverKey, "[^/]+$"))
	end
	return table.concat(parts, " ")
end

function PoseTool:JointOptions()
	local rig = self:Rig()
	local options = {}
	if not rig then
		return options
	end
	for _, joint in rig.List do
		local keyed = self.Keyed[joint.Key] == true
		table.insert(options, {
			Text = joint.Name,
			Value = joint.Key,
			Hint = if keyed then "keyed" else nil,
			Order = if keyed then 0 else 1,
		})
	end
	table.sort(options, function(a, b)
		if a.Order ~= b.Order then
			return a.Order < b.Order
		end
		return a.Text:lower() < b.Text:lower()
	end)
	return options
end

function PoseTool:SelectJoint(key)
	local rig = self:Rig()
	if key and rig and not rig.Joints[key] then
		key = rig.Names[key]
	end
	self.Joint = key
	self.Dirty = true
	self.PanelDirty = true
	return key
end

function PoseTool:SelectParent()
	local rig = self:Rig()
	local joint = rig and self.Joint and rig.Joints[self.Joint]
	if joint and joint.Parent then
		self:SelectJoint(joint.Parent)
	end
end

function PoseTool:SetPicking(active)
	self.AutoPick = active == true
	self.App:SetSetting("PoseAutoPick", self.AutoPick)
	self:_updatePicker()
end

function PoseTool:PickAt(ray)
	local rig = self:Rig()
	local key = Picker.Nearest(rig, ray, self.Keyed)
	if key then
		self:SelectJoint(key)
	end
	return key
end

function PoseTool:SetMode(mode)
	self.Mode = if mode == "Move" then "Move" else "Rotate"
	self.Gizmo:SetMode(self.Mode)
	self.PanelDirty = true
end

function PoseTool:SetStep(step)
	self.Step = step
	self.App:SetSetting("PoseStep", step)
	self.PanelDirty = true
end

function PoseTool:SetRoleScope(scope)
	self.RoleScope = if scope == "Keyframe" then "Keyframe" else "Joint"
	self.PanelDirty = true
end

function PoseTool:ScrubClip(clipTime)
	local info = self.Info
	local t = info and PoseMath.CutsceneTime(info, clipTime, self.App.Time)
	if t then
		self.App:SetTime(t)
	else
		self.App:Notify("That part of the clip is not played in the cutscene", "Warn")
	end
end

function PoseTool:JumpToKeyframe(keyframe)
	self:ScrubClip(keyframe.Time)
end

function PoseTool:StepKeyframe(direction)
	local info = self.Info
	if not info then
		return
	end
	local keyframe = PoseMath.Neighbour(info, self.ClipTime or 0, direction)
	if keyframe then
		self:JumpToKeyframe(keyframe)
	end
end

function PoseTool:_frame()
	if self.PanelDirty and self:IsOpen() then
		self.PanelDirty = false
		self.Panel:Refresh()
	end
	self.Drag:Flush()
	if self.Joint and self.Info and Gizmo.CameraMoved(self) then
		self.Dirty = true
	end
	if not self.Dirty then
		return
	end
	self.Dirty = false
	self:Redraw()
end

function PoseTool:Redraw()
	local markers = self.Markers
	markers:Begin()
	local rig = self:Rig()
	local open = self:IsOpen() and self.Info ~= nil and rig ~= nil
	local colors = PoseTool.Colors
	if open and self.Picker.Active and self.HoverRay then
		local key = Picker.Nearest(rig, self.HoverRay, self.Keyed)
		if key ~= self.HoverKey then
			self.HoverKey = key
			self.PanelDirty = true
		end
		local frame = key and key ~= self.Joint and Live.JointFrame(rig, key)
		if frame then
			markers:Sphere(frame.Position, Gizmo.SizeFor(frame.Position, 0.01), colors.Hover, 0.2)
		end
	end
	local frame = open and self.Joint and Live.JointFrame(rig, self.Joint)
	if frame then
		local size = Gizmo.SizeFor(frame.Position, 0.008)
		markers:Sphere(frame.Position, size, colors.Joint, 0)
		for key, joint in rig.Joints do
			if joint.Parent == self.Joint then
				local child = Live.JointFrame(rig, key)
				if child then
					markers:Line(frame.Position, child.Position, colors.Bone, 2, 0.2)
				end
			end
		end
	end
	markers:End()
	local playing = self.App.Preview and self.App.Preview.Playing
	if frame and not playing and self.ClipTime and (self.Drag.Active or not Live.Locked(self.Info.Clip)) then
		if self.Drag.Active then
			self.Gizmo:SetCFrame(frame)
		else
			self.Gizmo:Show(frame, Gizmo.SizeFor(frame.Position, 0.05))
		end
	elseif not self.Drag.Active then
		self.Gizmo:Hide()
	end
end

function PoseTool:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	self.Drag:Cancel()
	self.Picker:Destroy()
	self.Gizmo:Destroy()
	self.Markers:Destroy()
	self.Panel:Destroy()
end

require(script.Parent.PoseActions)(PoseTool)

return PoseTool
