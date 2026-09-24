local Model = require(script.Model)
local Ruler = require(script.Ruler)
local Lanes = require(script.Lanes)
local Blocks = require(script.Blocks)
local SubKeys = require(script.SubKeys)
local Playhead = require(script.Playhead)
local Snapping = require(script.Snapping)
local Marquee = require(script.Marquee)
local Warnings = require(script.Warnings)
local Reading = require(script.Reading)
local Hover = require(script.Hover)
local Interaction = require(script.Interaction)
local Keyboard = require(script.Keyboard)

local TimelineView = {}
TimelineView.__index = TimelineView

TimelineView.Inset = 3
TimelineView.MinWidth = 6
TimelineView.FollowMargin = 30

local BLACK = Color3.new(0, 0, 0)

local function layer(name, parent, zindex, props)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = zindex
	for key, value in props or {} do
		frame[key] = value
	end
	frame.Parent = parent
	return frame
end

function TimelineView.new(app, frame)
	local self = setmetatable({}, TimelineView)
	self.App = app
	self.Frame = frame
	self.Connections = {}
	self.Dirty = {}
	self.Overrides = {}
	self.Model = Model.Empty()
	self.Destroyed = false
	local rulerHeight = app.RulerHeight
	local root = layer("TimelineCanvas", frame, 1, { ClipsDescendants = true })
	self.Root = root
	self.RulerFrame = layer("Ruler", root, 3, { Size = UDim2.new(1, 0, 0, rulerHeight), BackgroundTransparency = 0 })
	self.LaneFrame = layer("Lanes", root, 1, {
		Position = UDim2.fromOffset(0, rulerHeight),
		Size = UDim2.new(1, 0, 1, -rulerHeight),
		ClipsDescendants = true,
	})
	self.RowLayer = layer("Rows", self.LaneFrame, 1)
	self.GridLayer = layer("Grid", self.LaneFrame, 2)
	self.BlockLayer = layer("Blocks", self.LaneFrame, 3)
	self.OverlayLayer = layer("Overlay", self.LaneFrame, 4)
	self.MarkLayer = layer("Marks", root, 5)
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.BorderSizePixel = 0
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 10
	hit.Parent = root
	self.Hit = hit
	self:_palette()
	self.Reading = Reading.new(self)
	self.Snapping = Snapping.new(self)
	self.Ruler = Ruler.new(self)
	self.Lanes = Lanes.new(self)
	self.Blocks = Blocks.new(self)
	self.SubKeys = SubKeys.new(self)
	self.Playhead = Playhead.new(self)
	self.Marquee = Marquee.new(self)
	self.Hover = Hover.new(self)
	self.Interaction = Interaction.new(self)
	self.Keyboard = Keyboard.new(self)
	local signals = app.Signals
	local function on(signal, fn)
		table.insert(self.Connections, signal:Connect(fn))
	end
	on(signals.DocumentChanged, function(_, changes)
		if changes and changes.Opened then
			self.Reading:Reset()
			self.Interaction:Cancel()
		end
		self:Invalidate("Model")
	end)
	on(signals.ViewChanged, function()
		self:Invalidate("View")
	end)
	on(signals.SelectionChanged, function()
		self:Invalidate("Selection")
	end)
	on(signals.TimeChanged, function()
		self:_follow()
		self:Invalidate("Time")
	end)
	on(signals.ThemeChanged, function()
		self:Invalidate("Theme")
	end)
	on(signals.PreviewChanged, function()
		if self.Reading:Refresh() then
			self:Invalidate("Model")
		end
	end)
	table.insert(self.Connections, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:Invalidate("View")
	end))
	self:Invalidate("Model")
	self:Flush()
	return self
end

function TimelineView:_palette()
	local theme = self.App.Theme
	local get = function(name)
		return theme:Get(name)
	end
	local lane = get("Lane")
	self.Dark = theme.IsDark ~= false
	self.Colors = {
		Lane = lane,
		LaneAlt = get("LaneAlt"),
		Group = get("GroupRow"),
		Surface = get("Surface"),
		Divider = get("Divider"),
		Border = get("Border"),
		Text = get("Text"),
		SubText = get("SubText"),
		Dim = get("Dim"),
		Faint = get("Faint"),
		Accent = get("Accent"),
		Error = get("Error"),
		Warning = get("Warning"),
		Playhead = get("Playhead"),
		Lock = get("Lock"),
		TrackSelected = lane:Lerp(get("Accent"), 0.12),
		Grid = lane:Lerp(get("Text"), if self.Dark then 0.07 else 0.1),
		Tick = get("Dim"),
		EndShade = BLACK,
		Snap = Color3.fromRGB(255, 214, 64),
		DarkText = Color3.fromRGB(22, 22, 26),
		LightText = Color3.fromRGB(250, 250, 252),
	}
	self.Fonts = theme.Fonts
end

function TimelineView:Invalidate(kind)
	if self.Destroyed then
		return
	end
	self.Dirty[kind or "View"] = true
	if self.Scheduled then
		return
	end
	self.Scheduled = true
	task.defer(function()
		self.Scheduled = false
		self:Flush()
	end)
end

function TimelineView:Stale()
	local app = self.App
	return app.Document ~= nil and (app:GetRows()) ~= self.Model.Rows
end

function TimelineView:Rebuild()
	self.Model = Model.Build(self)
	Warnings.Apply(self, self.Model)
	if not self.Interaction.Drag then
		table.clear(self.Overrides)
	end
end

function TimelineView:Sync()
	if not self.Destroyed and self:Stale() then
		self:Rebuild()
		self:Invalidate("View")
		return true
	end
	return false
end

function TimelineView:Flush()
	if self.Destroyed then
		return
	end
	local dirty = self.Dirty
	self.Dirty = {}
	if dirty.Theme then
		self:_palette()
		self.Blocks:ResetCache()
		self.Ruler:ResetCache()
	end
	if not dirty.Model and self:Stale() then
		dirty.Model = true
	end
	if dirty.Model or dirty.Theme then
		self:Rebuild()
	end
	local full = dirty.Model or dirty.View or dirty.Theme
	if full then
		self.Ruler:Render()
	end
	if full or dirty.Selection then
		self.Lanes:Render()
	end
	if full or dirty.Selection or dirty.Drag or dirty.Hover then
		self.Blocks:Render()
		self.SubKeys:Render()
		self.Marquee:Render()
	end
	if full or dirty.Time or dirty.Drag or dirty.Selection then
		self.Playhead:Render()
	end
end

function TimelineView:Width()
	return self.Root.AbsoluteSize.X
end

function TimelineView:LaneHeight()
	return math.max(self.Root.AbsoluteSize.Y - self.App.RulerHeight, 0)
end

function TimelineView:X(t)
	local app = self.App
	return (t - app.ScrollTime) * app.PixelsPerSecond
end

function TimelineView:T(x)
	local app = self.App
	return app.ScrollTime + x / app.PixelsPerSecond
end

function TimelineView:Timing(item)
	local override = self.Overrides[item.Clip]
	if override then
		return override.Start or item.Start,
			override.Duration or item.Duration,
			override.Speed or item.Speed,
			override.ClipOffset or item.ClipOffset,
			override.Row or item.Row
	end
	return item.Start, item.Duration, item.Speed, item.ClipOffset, item.Row
end

function TimelineView:Fade(item, name)
	local override = self.Overrides[item.Clip]
	if override and override[name] ~= nil then
		return override[name]
	end
	return item.Fades and item.Fades[name] or 0
end

function TimelineView:Rect(item)
	local app = self.App
	local start, duration, _, _, row = self:Timing(item)
	if not row then
		return nil
	end
	local inset = TimelineView.Inset
	local x = self:X(start)
	local width = math.max(duration * app.PixelsPerSecond, TimelineView.MinWidth)
	local y = app.RulerHeight + row.Y - app.ScrollY + inset
	return x, y, width, row.Height - inset * 2
end

function TimelineView:ToLocal(position)
	local origin = self.Root.AbsolutePosition
	return Vector2.new(position.X - origin.X, position.Y - origin.Y)
end

function TimelineView:ToAbsolute(x, y)
	local origin = self.Root.AbsolutePosition
	return Vector2.new(origin.X + x, origin.Y + y)
end

function TimelineView:ClipPoint(clip, fraction, dy)
	local item = self.Model.ByClip[clip]
	if not item then
		return nil
	end
	local x, y, width, height = self:Rect(item)
	if not x then
		return nil
	end
	return self:ToAbsolute(x + width * (fraction or 0.5), y + height / 2 + (dy or 0))
end

function TimelineView:GetBlock(clip)
	return self.Blocks:Find(clip)
end

function TimelineView:GetWarnings()
	local list = {}
	for _, item in self.Model.Items do
		if item.Warnings then
			list[item.Clip] = table.concat(item.Warnings, "\n")
		end
	end
	return list
end

function TimelineView:_follow()
	local app = self.App
	local preview = app.Preview
	if not preview or not preview.Playing or self.Interaction.Drag then
		return
	end
	local width = self:Width()
	local x = self:X(app.Time)
	if x > width - TimelineView.FollowMargin or x < 0 then
		app:SetView({ ScrollTime = app.Time - TimelineView.FollowMargin / app.PixelsPerSecond })
	end
end

function TimelineView:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	for _, part in { self.Interaction, self.Keyboard, self.Hover, self.Marquee, self.Playhead, self.SubKeys, self.Blocks, self.Lanes, self.Ruler } do
		pcall(part.Destroy, part)
	end
	self.Root:Destroy()
end

return TimelineView
