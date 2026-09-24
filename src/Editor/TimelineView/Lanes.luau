local Lanes = {}
Lanes.__index = Lanes

local function frame(parent, name)
	local instance = Instance.new("Frame")
	instance.Name = name
	instance.BorderSizePixel = 0
	instance.Parent = parent
	return instance
end

function Lanes.new(view)
	local self = setmetatable({}, Lanes)
	self.View = view
	self.Rows = {}
	self.Summaries = {}
	self.EndShade = frame(view.OverlayLayer, "AfterEnd")
	self.EndShade.BackgroundTransparency = 0.72
	self.EndShade.ZIndex = 1
	self.EndLine = frame(view.OverlayLayer, "EndLine")
	self.EndLine.ZIndex = 1
	self.Drop = frame(view.OverlayLayer, "DropTarget")
	self.Drop.BackgroundTransparency = 0.8
	self.Drop.Visible = false
	self.Drop.ZIndex = 2
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = self.Drop
	self.DropStroke = stroke
	return self
end

function Lanes:_row(index)
	local entry = self.Rows[index]
	if not entry then
		local background = frame(self.View.RowLayer, "Row")
		local divider = frame(background, "Divider")
		divider.AnchorPoint = Vector2.new(0, 1)
		divider.Position = UDim2.fromScale(0, 1)
		divider.Size = UDim2.new(1, 0, 0, 1)
		entry = { Frame = background, Divider = divider }
		self.Rows[index] = entry
	end
	return entry
end

function Lanes:_summary(index)
	local bar = self.Summaries[index]
	if not bar then
		bar = frame(self.View.RowLayer, "Summary")
		bar.ZIndex = 2
		bar.BackgroundTransparency = 0.25
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 2)
		corner.Parent = bar
		self.Summaries[index] = bar
	end
	return bar
end

function Lanes:_summaries(row, y, count)
	local view = self.View
	local app = view.App
	local spans = {}
	for _, info in row.Lane.Tracks do
		for _, item in view.Model.ByTrack[info.Track] or {} do
			table.insert(spans, { item.Start, item.Start + math.max(item.Duration, 1 / 30), item.Color })
		end
	end
	table.sort(spans, function(a, b)
		return a[1] < b[1]
	end)
	local merged = {}
	for _, span in spans do
		local last = merged[#merged]
		if last and span[1] <= last[2] + 2 / app.PixelsPerSecond then
			last[2] = math.max(last[2], span[2])
		else
			table.insert(merged, { span[1], span[2], span[3] })
		end
	end
	local width = view:Width()
	for _, span in merged do
		local x0, x1 = view:X(span[1]), view:X(span[2])
		if x1 >= 0 and x0 <= width then
			count += 1
			local bar = self:_summary(count)
			bar.Visible = true
			bar.BackgroundColor3 = span[3]:Lerp(view.Colors.Lane, 0.35)
			bar.Position = UDim2.fromOffset(math.round(x0), y + row.Height - 9)
			bar.Size = UDim2.fromOffset(math.max(math.round(x1 - x0), 2), 5)
		end
	end
	return count
end

function Lanes:Render()
	local view = self.View
	local app = view.App
	local colors = view.Colors
	local model = view.Model
	local height = view:LaneHeight()
	local selection = app.Selection
	local count, summaries = 0, 0
	local parity = 0
	for _, row in model.Rows do
		local y = row.Y - app.ScrollY
		if row.Type == "Group" then
			parity = 0
		else
			parity += 1
		end
		if y + row.Height >= 0 and y <= height then
			count += 1
			local entry = self:_row(count)
			local background = entry.Frame
			background.Visible = true
			background.Position = UDim2.fromOffset(0, y)
			background.Size = UDim2.new(1, 0, 0, row.Height)
			local color
			if row.Type == "Group" then
				color = colors.Group
				if row.Collapsed then
					summaries = self:_summaries(row, y, summaries)
				end
			elseif selection.Track == row.Track then
				color = colors.TrackSelected
			else
				color = if parity % 2 == 0 then colors.LaneAlt else colors.Lane
			end
			background.BackgroundColor3 = color
			entry.Divider.BackgroundColor3 = colors.Divider
			entry.Divider.BackgroundTransparency = if row.Type == "Group" then 0 else 0.4
		end
	end
	for i = count + 1, #self.Rows do
		self.Rows[i].Frame.Visible = false
	end
	for i = summaries + 1, #self.Summaries do
		self.Summaries[i].Visible = false
	end
	local length = model.Length
	local endX = view:X(length)
	local width = view:Width()
	local visible = app.Document ~= nil and endX < width
	self.EndShade.Visible = visible
	self.EndLine.Visible = visible and endX >= 0
	if visible then
		local x = math.max(math.round(endX), 0)
		self.EndShade.BackgroundColor3 = colors.EndShade
		self.EndShade.Position = UDim2.fromOffset(x, 0)
		self.EndShade.Size = UDim2.new(1, -x, 1, 0)
		self.EndLine.BackgroundColor3 = colors.Dim
		self.EndLine.Position = UDim2.fromOffset(x, 0)
		self.EndLine.Size = UDim2.new(0, 1, 1, 0)
	end
end

function Lanes:ShowDrop(row)
	local view = self.View
	if not row then
		self.Drop.Visible = false
		return
	end
	self.Drop.Visible = true
	self.Drop.BackgroundColor3 = view.Colors.Accent
	self.DropStroke.Color = view.Colors.Accent
	self.Drop.Position = UDim2.fromOffset(0, row.Y - view.App.ScrollY)
	self.Drop.Size = UDim2.new(1, 0, 0, row.Height)
end

function Lanes:Destroy() end

return Lanes
