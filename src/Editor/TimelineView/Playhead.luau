local Playhead = {}
Playhead.__index = Playhead

Playhead.HeadHeight = 12
Playhead.TipMargin = 6

local function frame(parent, name, props)
	local instance = Instance.new("Frame")
	instance.Name = name
	instance.BorderSizePixel = 0
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

function Playhead.new(view)
	local self = setmetatable({}, Playhead)
	self.View = view
	local layer = view.MarkLayer
	self.Line = frame(layer, "PlayheadLine", { Size = UDim2.new(0, 2, 1, 0), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 3 })
	self.Head = frame(layer, "PlayheadHead", {
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(11, Playhead.HeadHeight),
		ZIndex = 4,
	})
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 2)
	corner.Parent = self.Head
	self.Tip = frame(self.Head, "Tip", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(7, 7),
		Rotation = 45,
		ZIndex = 4,
	})
	self.Snap = frame(layer, "SnapLine", { Size = UDim2.new(0, 1, 1, 0), Visible = false, ZIndex = 5 })
	self.SnapGlow = frame(layer, "SnapGlow", {
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0, 5, 1, 0),
		BackgroundTransparency = 0.8,
		Visible = false,
		ZIndex = 5,
	})
	return self
end

function Playhead:Render()
	local view = self.View
	local app = view.App
	local colors = view.Colors
	local width = view:Width()
	local x = view:X(app.Time)
	local visible = app.Document ~= nil and x >= -6 and x <= width + 6
	self.Line.Visible = visible
	self.Head.Visible = visible
	if visible then
		local rx = math.round(x)
		self.Line.Position = UDim2.fromOffset(rx, 0)
		self.Line.BackgroundColor3 = colors.Playhead
		self.Head.Position = UDim2.fromOffset(rx, app.RulerHeight - Playhead.HeadHeight - 2)
		self.Head.BackgroundColor3 = colors.Playhead
		self.Tip.BackgroundColor3 = colors.Playhead
		self.Tip.Visible = rx >= Playhead.TipMargin and rx <= width - Playhead.TipMargin
	end
	local snap = view.SnapTime
	local snapX = if snap then view:X(snap) else nil
	local showSnap = snapX ~= nil and snapX >= -2 and snapX <= width + 2
	self.Snap.Visible = showSnap
	self.SnapGlow.Visible = showSnap
	if showSnap then
		local rx = math.round(snapX)
		self.Snap.Position = UDim2.fromOffset(rx, 0)
		self.Snap.BackgroundColor3 = colors.Snap
		self.SnapGlow.Position = UDim2.fromOffset(rx, 0)
		self.SnapGlow.BackgroundColor3 = colors.Snap
	end
	view.Ruler:RenderSpan()
end

function Playhead:Destroy()
	self.Line:Destroy()
	self.Head:Destroy()
	self.Snap:Destroy()
	self.SnapGlow:Destroy()
end

return Playhead
