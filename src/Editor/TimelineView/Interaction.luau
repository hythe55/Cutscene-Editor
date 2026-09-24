local Drag = require(script.Parent.Drag)
local Actions = require(script.Parent.Actions)
local ContextMenu = require(script.Parent.ContextMenu)
local AutoScroll = require(script.Parent.AutoScroll)

local Interaction = {}
Interaction.__index = Interaction

Interaction.EdgeWidth = 6
Interaction.HandleRadius = 6
Interaction.HandleBand = 9
Interaction.KeyRadius = 5
Interaction.KeyBand = 4
Interaction.DoubleClick = 0.4
Interaction.ScrollStep = 40
Interaction.PanStep = 60
Interaction.ZoomStep = 1.2

local BUTTONS = {
	[Enum.UserInputType.MouseButton1] = 1,
	[Enum.UserInputType.MouseButton2] = 2,
	[Enum.UserInputType.MouseButton3] = 3,
}

local KEY = Enum.KeyCode
local MOD = Enum.ModifierKey

local function point(input)
	return Vector2.new(input.Position.X, input.Position.Y)
end

function Interaction.new(view)
	local self = setmetatable({}, Interaction)
	self.View = view
	self.App = view.App
	self.Held = {}
	self.Drag = nil
	self.LastClick = nil
	self.LastPosition = nil
	self.LastMods = {}
	self.Connections = {}
	self.AutoScroll = AutoScroll.new(self)
	local hit = view.Hit
	local function on(signal, fn)
		table.insert(self.Connections, signal:Connect(fn))
	end
	on(hit.InputBegan, function(input)
		local button = BUTTONS[input.UserInputType]
		if button then
			self:PointerDown(point(input), button, self:Modifiers(input), input)
		end
	end)
	on(hit.InputChanged, function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			if not self.Capture then
				self:PointerMove(point(input), self:Modifiers(input))
			end
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not self.Capture then
			self:Wheel(point(input), input.Position.Z, self:Modifiers(input))
		end
	end)
	on(hit.InputEnded, function(input)
		local button = BUTTONS[input.UserInputType]
		if button and not self.Capture then
			self:PointerUp(point(input), button, self:Modifiers(input))
		end
	end)
	on(hit.MouseLeave, function()
		if not self.Drag then
			view.Hover:Clear()
		end
	end)
	return self
end

function Interaction:Modifiers(input)
	local held = self.Held
	local function down(modifier, a, b)
		local ok, value = false, false
		if input then
			ok, value = pcall(input.IsModifierKeyDown, input, modifier)
		end
		return (ok and value == true) or held[a] == true or held[b] == true
	end
	return {
		Shift = down(MOD.Shift, KEY.LeftShift, KEY.RightShift),
		Ctrl = down(MOD.Ctrl, KEY.LeftControl, KEY.RightControl) or down(MOD.Meta, KEY.LeftSuper, KEY.RightSuper),
		Alt = down(MOD.Alt, KEY.LeftAlt, KEY.RightAlt),
	}
end

function Interaction:_capture()
	local layer = self.App.Shell and self.App.Shell.Layer
	if self.Capture or not layer then
		return
	end
	local capture = Instance.new("TextButton")
	capture.Name = "TimelineDragCapture"
	capture.Text = ""
	capture.AutoButtonColor = false
	capture.BackgroundTransparency = 1
	capture.BorderSizePixel = 0
	capture.Size = UDim2.fromScale(1, 1)
	capture.ZIndex = 500
	capture.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			self:PointerMove(point(input), self:Modifiers(input))
		end
	end)
	capture.InputEnded:Connect(function(input)
		local button = BUTTONS[input.UserInputType]
		if button then
			self:PointerUp(point(input), button, self:Modifiers(input))
		end
	end)
	capture.InputBegan:Connect(function(input)
		local drag = self.Drag
		if drag and BUTTONS[input.UserInputType] then
			self:PointerUp(self.LastPosition, drag.Button, self.LastMods)
		end
	end)
	capture.MouseLeave:Connect(function()
		local drag = self.Drag
		if drag then
			self:PointerUp(self.LastPosition, drag.Button, self.LastMods)
		end
	end)
	capture.Parent = layer
	self.Capture = capture
end

function Interaction:_release()
	if self.Capture then
		self.Capture:Destroy()
		self.Capture = nil
	end
	if self.InputWatch then
		self.InputWatch:Disconnect()
		self.InputWatch = nil
	end
end

function Interaction:_watch(input, drag)
	if not input then
		return
	end
	self.InputWatch = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
		if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
			if self.Drag == drag then
				self:PointerUp(self.LastPosition, drag.Button, self.LastMods)
			end
		end
	end)
end

function Interaction:_begin(drag)
	if not drag then
		return
	end
	self.Drag = drag
	self.View.Hover:HideTip()
	self:_capture()
	self:_watch(self.PressInput, drag)
end

function Interaction:PointerDown(position, button, mods, input)
	self.PressInput = input
	mods = mods or {}
	local view = self.View
	local app = self.App
	self.LastPosition, self.LastMods = position, mods
	view.Hover:HideTip()
	if not app.Document or self.Drag then
		return
	end
	local hit = self:HitTest(position)
	if hit.Area == "Outside" then
		return
	end
	if button == 3 or (button == 1 and hit.Area == "Ruler") then
		return self:_begin(Drag.Scrub(self, hit, position, button, mods))
	end
	if button == 2 then
		if hit.Item and not app.Selection.Clips[hit.Item.Clip] then
			app:Select(hit.Item.Clip, "Replace")
		end
		return ContextMenu.Show(view, hit, position)
	end
	if button ~= 1 then
		return
	end
	if hit.SubKey then
		return self:_begin(Drag.SubKey(self, hit, position))
	elseif hit.Row and (hit.Row.Type == "KeyGroup" or hit.Row.Type == "KeyJoint") then
		return
	end
	local now = os.clock()
	local clip = hit.Item and hit.Item.Clip
	local last = self.LastClick
	local double = last ~= nil and clip ~= nil and last.Clip == clip and now - last.Time <= Interaction.DoubleClick and (last.Position - position).Magnitude <= 5
	self.LastClick = if double then nil else { Time = now, Position = position, Clip = clip }
	if not hit.Item then
		return self:_begin(Drag.Marquee(self, hit, position, mods))
	end
	if double then
		Actions.OpenTool(view, hit.Item)
		return
	end
	local selected = app.Selection.Clips[clip] == true
	if mods.Ctrl then
		app:Select(clip, "Toggle")
		if not app.Selection.Clips[clip] then
			return
		end
	elseif mods.Shift then
		app:Select(clip, "Add")
	elseif not selected then
		app:Select(clip, "Replace")
	end
	local zone = hit.Zone
	if zone == "Key" then
		return self:_begin(Drag.Key(self, hit, position))
	elseif zone == "Left" or zone == "Right" then
		return self:_begin(Drag.Retime(self, hit, position, zone))
	elseif zone ~= "Body" then
		return self:_begin(Drag.Fade(self, hit, position, zone))
	end
	return self:_begin(Drag.Move(self, hit, position, selected and not mods.Ctrl and not mods.Shift))
end

function Interaction:PointerMove(position, mods)
	mods = mods or {}
	self.LastPosition, self.LastMods = position, mods
	local drag = self.Drag
	if drag then
		drag:Move(position, mods)
		self.AutoScroll:Update(position)
		return
	end
	local hit = self:HitTest(position)
	self.View.Hover:Update(if hit.Area == "Lanes" then hit else nil, position)
end

function Interaction:Refresh()
	if self.Drag and self.LastPosition then
		self.Drag:Move(self.LastPosition, self:Modifiers(nil))
	end
end

function Interaction:_after()
	local view = self.View
	view.SnapTime = nil
	view.Preselect = nil
	view.Lanes:ShowDrop(nil)
	view.Marquee:Clear()
	view:Invalidate("Drag")
end

function Interaction:PointerUp(position, button, mods)
	local drag = self.Drag
	if not drag or (button ~= nil and drag.Button ~= button) then
		return
	end
	self.Drag = nil
	self.AutoScroll:Stop()
	self:_release()
	local ok, err = pcall(drag.Finish, drag, position or self.LastPosition, mods or self.LastMods)
	if not ok then
		warn("CutsceneEditor: timeline drag failed: " .. tostring(err))
		table.clear(self.View.Overrides)
	end
	self:_after()
end

function Interaction:Cancel()
	local drag = self.Drag
	if not drag then
		return false
	end
	self.Drag = nil
	self.AutoScroll:Stop()
	self:_release()
	pcall(drag.Cancel, drag)
	table.clear(self.View.Overrides)
	self:_after()
	return true
end

function Interaction:Wheel(position, delta, mods)
	mods = mods or {}
	local view = self.View
	local app = self.App
	if not app.Document or delta == 0 then
		return
	end
	if mods.Ctrl then
		local anchor = view:T(view:ToLocal(position).X)
		app:SetZoom(app.PixelsPerSecond * Interaction.ZoomStep ^ delta, anchor)
	elseif mods.Shift then
		app:SetView({ ScrollTime = app.ScrollTime - delta * Interaction.PanStep / app.PixelsPerSecond })
	else
		app:SetScrollY(app.ScrollY - delta * Interaction.ScrollStep)
	end
end

function Interaction:Destroy()
	self:Cancel()
	self.AutoScroll:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
end

require(script.Parent.HitTest)(Interaction)

return Interaction
