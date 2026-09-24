local Marquee = {}
Marquee.__index = Marquee

function Marquee.new(view)
	local self = setmetatable({}, Marquee)
	self.View = view
	local frame = Instance.new("Frame")
	frame.Name = "Marquee"
	frame.BorderSizePixel = 0
	frame.BackgroundTransparency = 0.86
	frame.Visible = false
	frame.ZIndex = 6
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	frame.Parent = view.OverlayLayer
	self.Frame = frame
	self.Stroke = stroke
	self.Box = nil
	return self
end

function Marquee:Set(t0, y0, t1, y1)
	self.Box = { T0 = math.min(t0, t1), T1 = math.max(t0, t1), Y0 = math.min(y0, y1), Y1 = math.max(y0, y1) }
	self:Render()
	return self:Hits()
end

function Marquee:Clear()
	self.Box = nil
	self:Render()
end

function Marquee:Hits()
	local box = self.Box
	local hits = {}
	if not box then
		return hits
	end
	for _, item in self.View.Model.Items do
		local start, duration, _, _, row = self.View:Timing(item)
		if row and row.Y + row.Height > box.Y0 and row.Y < box.Y1 then
			local finish = start + math.max(duration, 1 / 60)
			if finish >= box.T0 and start <= box.T1 then
				hits[item.Clip] = true
			end
		end
	end
	return hits
end

function Marquee:Render()
	local view = self.View
	local box = self.Box
	self.Frame.Visible = box ~= nil
	if not box then
		return
	end
	local app = view.App
	local x0, x1 = view:X(box.T0), view:X(box.T1)
	local y0, y1 = box.Y0 - app.ScrollY, box.Y1 - app.ScrollY
	self.Frame.BackgroundColor3 = view.Colors.Accent
	self.Stroke.Color = view.Colors.Accent
	self.Frame.Position = UDim2.fromOffset(math.round(x0), math.round(y0))
	self.Frame.Size = UDim2.fromOffset(math.max(math.round(x1 - x0), 1), math.max(math.round(y1 - y0), 1))
end

function Marquee:Destroy()
	self.Frame:Destroy()
end

return Marquee
