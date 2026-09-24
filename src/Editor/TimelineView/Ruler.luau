local Parts = require(script.Parent.BlockParts)

local Ruler = {}
Ruler.__index = Ruler

Ruler.MinLabelSpacing = 64
Ruler.MinTickSpacing = 5

local FRAME = 1 / 30

Ruler.Steps = {
	{ FRAME, nil },
	{ 2 * FRAME, FRAME },
	{ 5 * FRAME, FRAME },
	{ 10 * FRAME, FRAME },
	{ 0.5, 5 * FRAME },
	{ 1, 5 * FRAME },
	{ 2, 0.5 },
	{ 5, 1 },
	{ 10, 1 },
	{ 15, 5 },
	{ 30, 5 },
	{ 60, 10 },
	{ 120, 30 },
	{ 300, 60 },
	{ 600, 60 },
}

function Ruler.Choose(pixelsPerSecond)
	for _, step in Ruler.Steps do
		if step[1] * pixelsPerSecond >= Ruler.MinLabelSpacing then
			local minor = step[2]
			if minor and minor * pixelsPerSecond < Ruler.MinTickSpacing then
				minor = nil
			end
			return step[1], minor
		end
	end
	local last = Ruler.Steps[#Ruler.Steps]
	return last[1], last[2]
end

function Ruler.Format(t, major)
	t = math.max(t, 0)
	if major >= 1 - 1e-6 then
		local total = math.round(t)
		return string.format("%d:%02d", total // 60, total % 60)
	end
	local total = math.round(t * 100)
	return string.format("%d:%02d.%02d", total // 6000, (total // 100) % 60, total % 100)
end

local function frame(parent, name)
	local instance = Instance.new("Frame")
	instance.Name = name
	instance.BorderSizePixel = 0
	instance.Parent = parent
	return instance
end

function Ruler.new(view)
	local self = setmetatable({}, Ruler)
	self.View = view
	self.Frame = view.RulerFrame
	self.Ticks = {}
	self.Labels = {}
	self.Grid = {}
	self.Cache = {}
	self.Divider = frame(self.Frame, "Divider")
	self.Divider.AnchorPoint = Vector2.new(0, 1)
	self.Divider.Position = UDim2.fromScale(0, 1)
	self.Divider.Size = UDim2.new(1, 0, 0, 1)
	self.Divider.ZIndex = 3
	self.Span = frame(self.Frame, "SelectionSpan")
	self.Span.ZIndex = 1
	self.Span.BackgroundTransparency = 0.55
	self.Span.Visible = false
	self.EndMark = frame(self.Frame, "EndMark")
	self.EndMark.ZIndex = 2
	self.EndMark.Size = UDim2.fromOffset(2, view.App.RulerHeight)
	return self
end

function Ruler:_tick(index)
	local tick = self.Ticks[index]
	if not tick then
		tick = frame(self.Frame, "Tick")
		tick.AnchorPoint = Vector2.new(0, 1)
		tick.ZIndex = 2
		self.Ticks[index] = tick
	end
	return tick
end

function Ruler:_label(index)
	local label = self.Labels[index]
	if not label then
		label = Instance.new("TextLabel")
		label.Name = "Time"
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextSize = 11
		label.Size = UDim2.fromOffset(80, 14)
		label.ZIndex = 2
		label.Parent = self.Frame
		self.Labels[index] = label
	end
	return label
end

function Ruler:_grid(index)
	local line = self.Grid[index]
	if not line then
		line = frame(self.View.GridLayer, "Grid")
		line.Size = UDim2.new(0, 1, 1, 0)
		self.Grid[index] = line
	end
	return line
end

function Ruler:Render()
	local put = Parts.Put
	local view = self.View
	local app = view.App
	local colors = view.Colors
	local pps = app.PixelsPerSecond
	local width = view:Width()
	local height = app.RulerHeight
	self.Frame.BackgroundColor3 = colors.Surface
	self.Divider.BackgroundColor3 = colors.Border
	local major, minor = Ruler.Choose(pps)
	local step = minor or major
	local first = math.floor(app.ScrollTime / step) * step
	local tickCount, labelCount, gridCount = 0, 0, 0
	local font = view.Fonts.Mono
	local index = 0
	while true do
		local t = first + index * step
		index += 1
		local x = (t - app.ScrollTime) * pps
		if x > width + 1 then
			break
		end
		if t >= -1e-6 and x >= -80 then
			local ratio = t / major
			local isMajor = math.abs(ratio - math.round(ratio)) < 1e-4
			tickCount += 1
			local tick = self:_tick(tickCount)
			put(self, tick, "Visible", true)
			put(self, tick, "Position", UDim2.fromOffset(math.round(x), height - 1))
			put(self, tick, "Size", UDim2.fromOffset(1, if isMajor then 10 else 5))
			put(self, tick, "BackgroundColor3", if isMajor then colors.SubText else colors.Tick)
			if isMajor then
				labelCount += 1
				local label = self:_label(labelCount)
				put(self, label, "Visible", true)
				put(self, label, "FontFace", font)
				put(self, label, "TextColor3", colors.SubText)
				put(self, label, "Position", UDim2.fromOffset(math.round(x) + 4, 3))
				put(self, label, "Text", Ruler.Format(t, major))
				gridCount += 1
				local line = self:_grid(gridCount)
				put(self, line, "Visible", true)
				put(self, line, "Position", UDim2.fromOffset(math.round(x), 0))
				put(self, line, "BackgroundColor3", colors.Grid)
			end
		end
		if index > 4000 then
			break
		end
	end
	for i = tickCount + 1, #self.Ticks do
		put(self, self.Ticks[i], "Visible", false)
	end
	for i = labelCount + 1, #self.Labels do
		put(self, self.Labels[i], "Visible", false)
	end
	for i = gridCount + 1, #self.Grid do
		put(self, self.Grid[i], "Visible", false)
	end
	local length = view.Model.Length
	local endX = (length - app.ScrollTime) * pps
	self.EndMark.Visible = length > 0 and endX >= -2 and endX <= width + 2
	self.EndMark.Position = UDim2.fromOffset(math.round(endX) - 1, 0)
	self.EndMark.BackgroundColor3 = colors.Dim
	self:RenderSpan()
	self.Major, self.Minor = major, minor
end

function Ruler:RenderSpan()
	local view = self.View
	local app = view.App
	local first, last = math.huge, -math.huge
	for clip in app.Selection.Clips do
		local item = view.Model.ByClip[clip]
		if item then
			local start, duration = view:Timing(item)
			first = math.min(first, start)
			last = math.max(last, start + duration)
		end
	end
	if first == math.huge then
		self.Span.Visible = false
		return
	end
	local x0, x1 = view:X(first), view:X(last)
	self.Span.Visible = true
	self.Span.BackgroundColor3 = view.Colors.Accent
	self.Span.Position = UDim2.new(0, math.round(x0), 1, -4)
	self.Span.Size = UDim2.fromOffset(math.max(math.round(x1 - x0), 2), 3)
end

function Ruler:ResetCache()
	table.clear(self.Cache)
end

function Ruler:Destroy()
	for _, line in self.Grid do
		line:Destroy()
	end
end

return Ruler
