local Model = require(script.Parent.Model)
local Parts = require(script.Parent.BlockParts)

local Blocks = {}
Blocks.__index = Blocks

Blocks.MinLabel = 22
Blocks.KeySpacing = 6
Blocks.MinKeyGap = 8
Blocks.MinKeyWidth = 24
Blocks.MaxKeys = 96
Blocks.KeyInset = 6
Blocks.ClipMargin = 5
Blocks.MinHandleWidth = 20
Blocks.HandleInset = 4

local BLACK = Color3.new(0, 0, 0)

local function luminance(color)
	return 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
end

function Blocks.new(view)
	local self = setmetatable({}, Blocks)
	self.View = view
	self.All = {}
	self.ByClip = {}
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Size = UDim2.fromOffset(0, 0)
	content.Parent = view.BlockLayer
	self.Content = content
	return self
end

function Blocks.HandleX(view, item, width)
	local names = Model.Fades[item.Kind]
	if not names then
		return nil, nil
	end
	local pps = view.App.PixelsPerSecond
	local low, high = Blocks.HandleInset, math.max(width - Blocks.HandleInset, Blocks.HandleInset)
	local fadeIn = math.clamp(view:Fade(item, names[1]) * pps, low, high)
	local fadeOut = if names[2] then math.clamp(width - view:Fade(item, names[2]) * pps, low, high) else nil
	return fadeIn, fadeOut
end

function Blocks:ResetCache()
	for _, block in self.All do
		table.clear(block.Cache)
	end
end

function Blocks:Find(clip)
	local block = self.ByClip[clip]
	return block and block.Frame
end

function Blocks:Render()
	local view = self.View
	local app = view.App
	local model = view.Model
	local pps = app.PixelsPerSecond
	local width, height = view:Width(), view:LaneHeight()
	local ruler = app.RulerHeight
	local offsetX, offsetY = math.round(-app.ScrollTime * pps), -math.round(app.ScrollY)
	local position = UDim2.fromOffset(offsetX, offsetY)
	if self.Content.Position ~= position then
		self.Content.Position = position
	end
	local visible = {}
	for _, item in model.Items do
		local x, y, w, h = view:Rect(item)
		if x then
			local reach = w
			if item.Need then
				reach = math.max(reach, item.Need * pps)
			end
			local top = y - ruler
			if x + reach >= -2 and x <= width + 2 and top + h >= 0 and top <= height then
				table.insert(visible, { Item = item, H = h })
			end
		end
	end
	local previous = self.ByClip
	local current = {}
	local used = {}
	for _, entry in visible do
		local block = previous[entry.Item.Clip]
		if block and not used[block] then
			used[block] = true
			entry.Block = block
		end
	end
	local free = {}
	for _, block in self.All do
		if not used[block] then
			table.insert(free, block)
		end
	end
	local margin = Blocks.ClipMargin
	local band = { -offsetX + margin, width - offsetX - margin, margin - offsetY, height - margin - offsetY }
	for _, entry in visible do
		if not entry.Block then
			local block = table.remove(free)
			if not block then
				block = Parts.Create(self.Content, view)
				table.insert(self.All, block)
			end
			entry.Block = block
		end
		current[entry.Item.Clip] = entry.Block
		self:_draw(entry.Block, entry.Item, entry.H, band)
	end
	for _, block in free do
		Parts.Put(block, block.Frame, "Visible", false)
		block.Item = nil
	end
	self.ByClip = current
end

function Blocks:_colors(item, selected, preselected)
	local colors = self.View.Colors
	local base = item.Color
	local body
	if item.Muted then
		body = base:Lerp(colors.Lane, 0.7)
	elseif selected then
		body = base
	elseif preselected then
		body = base:Lerp(colors.Text, 0.1)
	else
		body = base:Lerp(colors.Lane, 0.32)
	end
	local text = if luminance(body) > 0.5 then colors.DarkText else colors.LightText
	return body, text
end

function Blocks:_draw(block, item, h, band)
	local view = self.View
	local app = view.App
	local colors = view.Colors
	local put = Parts.Put
	local frame = block.Frame
	local selection = app.Selection
	local selected = selection.Clips[item.Clip] == true
	local preselected = view.Preselect ~= nil and view.Preselect[item.Clip] == true
	local primary = selection.Primary == item.Clip
	local hover = view.HoverState
	local hovered = hover ~= nil and hover.Item == item
	local start, duration, _, _, row = view:Timing(item)
	local short = item.Need ~= nil and duration + 1e-3 < item.Need
	local warned = short or (item.Warnings ~= nil and not item.ReadingShort)
	local body, text = self:_colors(item, selected, preselected)
	block.Item = item
	local pps = app.PixelsPerSecond
	local rx = math.round(start * pps)
	local rw = math.max(math.round((start + duration) * pps) - rx, view.MinWidth)
	put(block, frame, "Visible", true)
	put(block, frame, "Position", UDim2.fromOffset(rx, row.Y + view.Inset))
	put(block, frame, "Size", UDim2.fromOffset(rw, h))
	put(block, frame, "BackgroundColor3", body)
	local dragging = view.Overrides[item.Clip] ~= nil and view.Interaction.Drag ~= nil
	put(block, frame, "BackgroundTransparency", if dragging then 0.12 else 0)
	put(block, frame, "ZIndex", if dragging then 3 elseif selected then 2 else 1)
	local strokeColor, thickness = body:Lerp(BLACK, 0.45), 1
	if selected or preselected then
		strokeColor, thickness = colors.Text, if primary then 2 else 1
	elseif warned then
		strokeColor, thickness = colors.Error, 2
	elseif hovered then
		strokeColor = body:Lerp(colors.Text, 0.5)
	end
	put(block, block.Stroke, "Color", strokeColor)
	put(block, block.Stroke, "Thickness", thickness)
	local keys = #item.Keys > 0 and h >= 20
	local badge = if warned and rw >= 44 then 14 else 0
	local labelX = math.max(6, band[1] - Blocks.ClipMargin - rx + 6)
	local labelWidth = rw - labelX - 6 - badge
	local labelVisible = rw >= Blocks.MinLabel and labelWidth >= Blocks.MinLabel - 6
	put(block, block.Label, "Visible", labelVisible)
	if labelVisible then
		put(block, block.Label, "Text", item.Label)
		put(block, block.Label, "TextColor3", text)
		put(block, block.Label, "TextTransparency", if item.Muted then 0.35 else 0)
		put(block, block.Label, "Position", UDim2.fromOffset(labelX, if keys then 2 else math.floor((h - 14) / 2)))
		put(block, block.Label, "Size", UDim2.fromOffset(labelWidth, 14))
	end
	put(block, block.Badge, "Visible", warned and rw >= 44)
	if warned then
		put(block, block.Badge, "BackgroundColor3", colors.Error)
	end
	self:_fades(block, item, rw, h, selected or hovered, text)
	self:_keys(block, item, rx, row.Y + view.Inset, rw, h, text, band)
	self:_edges(block, hovered and hover.Zone or nil, h, text)
	self:_reading(block, warned, short, item, duration, rw, h)
	put(block, block.LockMark, "Visible", item.Locked and rw >= 16)
	if item.Locked then
		put(block, block.LockMark, "BackgroundColor3", colors.Lock)
	end
end

function Blocks:_fades(block, item, w, h, active, text)
	local view = self.View
	local put = Parts.Put
	local pps = view.App.PixelsPerSecond
	local names = Model.Fades[item.Kind]
	local fadeIn = if names then math.clamp(view:Fade(item, names[1]) * pps, 0, w) else 0
	local fadeOut = if names and names[2] then math.clamp(view:Fade(item, names[2]) * pps, 0, w) else 0
	Parts.Ramp(block, block.FadeIn, fadeIn, h, false, text, w)
	Parts.Ramp(block, block.FadeOut, fadeOut, h, true, text, w)
	local handles = names ~= nil and active and w >= Blocks.MinHandleWidth and not item.Locked
	put(block, block.HandleIn, "Visible", handles)
	put(block, block.HandleOut, "Visible", handles and names[2] ~= nil)
	if handles then
		local inX, outX = Blocks.HandleX(view, item, w)
		put(block, block.HandleIn, "Position", UDim2.fromOffset(math.round(inX), 0))
		if outX then
			put(block, block.HandleOut, "Position", UDim2.fromOffset(math.round(outX), 0))
		end
	end
end

function Blocks:_keys(block, item, x, y, w, h, text, band)
	local view = self.View
	local app = view.App
	local selectedKey = app.Selection.Key
	local count = 0
	local drawn = {}
	local centerY = y + h - Blocks.KeyInset
	if #item.Keys > 0 and h >= 20 and w >= Blocks.MinKeyWidth and centerY >= band[3] and centerY <= band[4] then
		local start, duration, speed, offset = view:Timing(item)
		local pps = app.PixelsPerSecond
		local marks = {}
		Model.KeyTimes(item, start, duration, speed, offset, function(t, key)
			local px = math.round(t * pps)
			if px >= band[1] and px <= band[2] then
				table.insert(marks, { X = px - x, Key = key, T = t })
			end
			return nil
		end)
		table.sort(marks, function(a, b)
			return a.X < b.X
		end)
		local dense = #marks >= 2 and (marks[#marks].X - marks[1].X) / (#marks - 1) < Blocks.MinKeyGap
		local last = -math.huge
		for _, mark in marks do
			local isSelected = mark.Key.Instance == selectedKey
			if isSelected or (not dense and mark.X - last >= Blocks.KeySpacing) then
				last = mark.X
				count += 1
				table.insert(drawn, mark)
				Parts.Diamond(block, count, mark.X, h - Blocks.KeyInset, mark.Key.Role, if isSelected then view.Colors.Accent else text, isSelected)
				if count >= Blocks.MaxKeys then
					break
				end
			end
		end
	end
	block.Marks = drawn
	for index = count + 1, #block.Diamonds do
		Parts.Put(block, block.Diamonds[index].Frame, "Visible", false)
	end
end

function Blocks:_edges(block, zone, h, text)
	local put = Parts.Put
	put(block, block.EdgeLeft, "Visible", zone == "Left")
	put(block, block.EdgeRight, "Visible", zone == "Right")
	if zone == "Left" or zone == "Right" then
		local edge = if zone == "Left" then block.EdgeLeft else block.EdgeRight
		put(block, edge, "BackgroundColor3", text)
		put(block, edge, "Size", UDim2.fromOffset(3, h))
	end
end

function Blocks:_reading(block, warned, short, item, duration, w, h)
	local view = self.View
	local put = Parts.Put
	put(block, block.Stripe, "Visible", warned)
	put(block, block.Need, "Visible", short)
	if warned then
		put(block, block.Stripe, "BackgroundColor3", view.Colors.Error)
		put(block, block.Stripe, "Position", UDim2.fromOffset(0, h - 3))
		put(block, block.Stripe, "Size", UDim2.fromOffset(w, 3))
	end
	if not short then
		return
	end
	local pps = view.App.PixelsPerSecond
	local extra = math.max((item.Need - duration) * pps, 0)
	put(block, block.Need, "BackgroundColor3", view.Colors.Error)
	put(block, block.Need, "Position", UDim2.fromOffset(w, h - 3))
	put(block, block.Need, "Size", UDim2.fromOffset(math.round(extra), 3))
end

function Blocks:Destroy()
	self.Content:Destroy()
	table.clear(self.All)
	table.clear(self.ByClip)
end

return Blocks
