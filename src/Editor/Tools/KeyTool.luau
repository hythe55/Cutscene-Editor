local RunService = game:GetService("RunService")

local Gizmo = require(script.Parent.Gizmo)
local Markers = require(script.Parent.Markers)
local Live = require(script.Parent.Live)
local KeyMath = require(script.Parent.KeyMath)
local KeyPanel = require(script.Parent.KeyPanel)

local KeyTool = {}
KeyTool.__index = KeyTool

KeyTool.Colors = {
	Path = Color3.fromRGB(255, 190, 70),
	Key = Color3.fromRGB(255, 225, 150),
	Selected = Color3.fromRGB(64, 196, 255),
	Playhead = Color3.fromRGB(255, 72, 72),
	Frustum = Color3.fromRGB(255, 210, 120),
}

local function setUpConnections(self)
	local app = self.App
	local signals = app.Signals
	local connections = self.Connections
	table.insert(connections, signals.SelectionChanged:Connect(function()
		self:Sync()
	end))
	table.insert(connections, signals.DocumentChanged:Connect(function()
		self:Sync()
	end))
	table.insert(connections, signals.PreviewChanged:Connect(function()
		self.PathDirty = true
	end))
	table.insert(connections, signals.TimeChanged:Connect(function()
		self.Dirty = true
	end))
	table.insert(connections, self.Frame:GetPropertyChangedSignal("Visible"):Connect(function()
		self:Sync(true)
	end))
	table.insert(connections, RunService.PreRender:Connect(function()
		self:_frame()
	end))
end

function KeyTool.new(app, frame)
	local self = setmetatable({}, KeyTool)
	self.App = app
	self.Frame = frame
	self.Connections = {}
	self.Mode = app:GetSetting("KeyToolMode", "Move")
	self.ShowPath = app:GetSetting("KeyToolPath", true) ~= false
	self.Keys = {}
	self.Markers = Markers.new("CutsceneEditorKeyTool")
	self.Gizmo = Gizmo.new({
		Name = "CutsceneEditorKeyGizmo",
		Mode = self.Mode,
		OnBegin = function()
			self:_beginDrag()
		end,
		OnRotate = function(axis, angle)
			local drag = self.Drag
			if drag then
				self:_dragTo(drag.Base * Gizmo.RotateDelta(axis, angle))
			end
		end,
		OnMove = function(face, distance)
			local drag = self.Drag
			if drag then
				self:_dragTo(drag.Base + drag.Base:VectorToWorldSpace(Gizmo.MoveDelta(face, distance)))
			end
		end,
		OnEnd = function()
			self:_endDrag()
		end,
	})
	self.Panel = KeyPanel.new(self, frame)
	setUpConnections(self)
	self:Sync()
	return self
end

function KeyTool:IsOpen()
	return self.Frame.Visible
end

function KeyTool:Sync(opened)
	local app = self.App
	local document = app.Document
	local clip = app.Selection.Primary
	local kind = nil
	if document and clip and document:IsClip(clip) then
		kind = document:KindOf(clip)
	end
	if not KeyMath.Kinds[kind] then
		clip, kind = nil, nil
	end
	local changed = clip ~= self.Clip
	if changed and self.Drag then
		self:_cancelDrag()
	end
	self.Clip, self.Kind = clip, kind
	self.Props = if clip then KeyMath.Props(document, clip) else nil
	self.Keys = if clip and kind ~= "Attach" then document:GetKeys(clip) else {}
	local key = app.Selection.Key
	if key and (not clip or document:ClipOf(key) ~= clip) then
		key = nil
	end
	self.Key = key
	if clip and (changed or opened) and self:IsOpen() and KeyMath.IsAnchored(kind, self.Props) and not Live.Timeline(app) then
		Live.Ensure(app)
	end
	self.PathDirty = true
	self.Panel:Refresh()
end

function KeyTool:StatusText()
	local props, kind = self.Props, self.Kind
	if not props then
		return ""
	end
	local app = self.App
	local inside = KeyMath.Inside(props, app.Time)
	local anchored = KeyMath.IsAnchored(kind, props)
	local parts = {}
	if Live.Locked(self.Clip) then
		table.insert(parts, "This track is locked; unlock it in the lane header to edit.")
	end
	if kind == "Attach" then
		table.insert(parts, `Follows {props.Target ~= "" and props.Target or "?"}{props.TargetJoint ~= "" and " / " .. props.TargetJoint or ""}. Drag the handles to change the offset.`)
	elseif kind == "Camera" and anchored then
		table.insert(parts, `Keys are relative to {props.Anchor}{props.AnchorJoint ~= "" and " / " .. props.AnchorJoint or ""}.`)
	end
	if anchored and not Live.Timeline(app) then
		table.insert(parts, "Start the preview to place anchored keys.")
	end
	if kind ~= "Attach" then
		if inside then
			table.insert(parts, string.format("Playhead is at clip time %.2fs.", KeyMath.ToLocal(props, app.Time)))
		else
			table.insert(parts, "Playhead is outside this clip.")
		end
	end
	return table.concat(parts, " ")
end

function KeyTool:SetMode(mode)
	self.Mode = if mode == "Rotate" then "Rotate" else "Move"
	self.App:SetSetting("KeyToolMode", self.Mode)
	self.Gizmo:SetMode(self.Mode)
	self.Panel:Refresh()
end

function KeyTool:SetShowPath(show)
	self.ShowPath = show == true
	self.App:SetSetting("KeyToolPath", self.ShowPath)
	self.PathDirty = true
	self.Panel:Refresh()
end

function KeyTool:SelectKey(key)
	self.App:SelectKey(key)
end

function KeyTool:_keyList()
	local deps = self.App.Deps
	local folder = self.Clip and self.Clip:FindFirstChild("Keys")
	local keys = deps.Spline.ReadKeys(folder)
	local drag = self.Drag
	if drag and drag.Key and drag.Value then
		for _, entry in keys do
			if entry.Instance == drag.Key then
				entry.CFrame = drag.Value
			end
		end
	end
	return keys
end

function KeyTool:KeyWorld(key)
	local drag = self.Drag
	local value = if drag and drag.Key == key and drag.Value then drag.Value else key.Value
	return KeyMath.KeyWorld(self.App, self.Kind, self.Props, value, KeyMath.KeyTime(key))
end

function KeyTool:TargetWorld()
	if not self.Clip then
		return nil
	end
	if self.Kind == "Attach" then
		if not self:IsOpen() then
			return nil
		end
		local drag = self.Drag
		if drag and drag.World then
			return drag.World
		end
		return KeyMath.AttachWorld(self.App, self.Props)
	end
	if self.Key and self.Key.Parent then
		return self:KeyWorld(self.Key)
	end
	return nil
end

function KeyTool:_frame()
	if self.Clip and Gizmo.CameraMoved(self) then
		self.Dirty = true
	end
	if not self.Dirty and not self.PathDirty then
		return
	end
	if self.Drag and self.Drag.Patched then
		self.Drag.Patched = false
		Live.Reseek(self.App)
	end
	if self.PathDirty then
		self.PathDirty = false
		self:_buildPath()
	end
	self.Dirty = false
	self:Redraw()
	if self.Clip and self:IsOpen() then
		self.Panel.Status.Text = self:StatusText()
	end
end

function KeyTool:_beginDrag()
	local app = self.App
	local base = self:TargetWorld()
	if not base or (app.Preview and app.Preview.Playing) or not self:_editable() then
		self.Gizmo:Cancel()
		return
	end
	local props = self.Props
	self.Drag = {
		Base = base,
		Key = if self.Kind ~= "Attach" then self.Key else nil,
		LocalTime = if self.Key then KeyMath.KeyTime(self.Key) else nil,
		Original = if self.Kind == "Attach" then props.Offset else self.Key.Value,
	}
end

function KeyTool:_dragTo(world)
	local drag = self.Drag
	local app = self.App
	local kind, props = self.Kind, self.Props
	local value
	if kind == "Attach" then
		local frame = KeyMath.Frame(app, "Attach", props, KeyMath.AttachTime(app, props))
		value = frame and frame:ToObjectSpace(world)
	else
		value = KeyMath.WorldToKey(app, kind, props, world, drag.LocalTime)
	end
	if not value then
		return
	end
	drag.Value = value
	drag.World = world
	self.Gizmo:SetCFrame(world)
	drag.Patched = Live.Patch(app, self.Clip, function(state)
		if kind == "Attach" then
			state.Props.Offset = value
			state.ExitPivot = nil
		else
			for _, entry in state.Keys or {} do
				if entry.Instance == drag.Key then
					entry.CFrame = value
				end
			end
		end
	end) or drag.Patched
	self.PathDirty = true
end

function KeyTool:_endDrag()
	local drag = self.Drag
	self.Drag = nil
	if not drag or not drag.Value or drag.Value == drag.Original then
		self.PathDirty = true
		return
	end
	local document = self.App.Document
	local result
	if self.Kind == "Attach" then
		result = document:SetAttribute(self.Clip, "Offset", drag.Value)
	else
		result = document:SetKey(drag.Key, drag.Value)
	end
	if not result and self.App.Preview.Active then
		self.App.Preview:Rebuild()
	end
	self:Sync()
end

function KeyTool:_cancelDrag()
	local drag = self.Drag
	self.Drag = nil
	self.Gizmo:Cancel()
	if drag and drag.Value and self.App.Preview.Active then
		self.App.Preview:Rebuild()
	end
end

function KeyTool:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	self.Drag = nil
	self.Gizmo:Destroy()
	self.Markers:Destroy()
	self.Panel:Destroy()
end

require(script.Parent.KeyActions)(KeyTool)
require(script.Parent.KeyDraw)(KeyTool)

return KeyTool
