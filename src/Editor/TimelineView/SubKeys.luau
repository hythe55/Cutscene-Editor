local Model = require(script.Parent.Model)
local JointGroups = require(script.Parent.Parent.JointGroups)

local SubKeys = {}
SubKeys.__index = SubKeys

SubKeys.Size = 8
SubKeys.HitRadius = 6

local function frame(parent, name)
	local instance = Instance.new("Frame")
	instance.Name = name
	instance.BorderSizePixel = 0
	instance.Parent = parent
	return instance
end

function SubKeys.new(view)
	local self = setmetatable({}, SubKeys)
	self.View = view
	self.Bars = {}
	self.Diamonds = {}
	self.Marks = {}
	local content = Instance.new("Frame")
	content.Name = "SubKeys"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Size = UDim2.fromOffset(0, 0)
	content.ZIndex = 4
	content.Parent = view.BlockLayer
	self.Content = content
	return self
end

function SubKeys.IsSubRow(row)
	return row ~= nil and (row.Type == "KeyGroup" or row.Type == "KeyJoint")
end

local function sameRow(subKey, row)
	return subKey ~= nil and subKey.Track == row.Track and subKey.Group == row.Group and subKey.Joint == row.Joint
end

function SubKeys:_bar(index)
	local bar = self.Bars[index]
	if not bar then
		bar = frame(self.Content, "Span")
		bar.ZIndex = 4
		self.Bars[index] = bar
	end
	return bar
end

function SubKeys:_diamond(index)
	local diamond = self.Diamonds[index]
	if not diamond then
		diamond = frame(self.Content, "Key")
		diamond.Rotation = 45
		diamond.AnchorPoint = Vector2.new(0.5, 0.5)
		diamond.ZIndex = 5
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1
		stroke.Parent = diamond
		self.Diamonds[index] = diamond
	end
	return diamond
end

function SubKeys.Times(view, item, joints)
	local document = view.App.Document
	local sequence = item.Sequence or (document and document:GetSequence(item.Clip))
	if not sequence then
		return {}
	end
	local times = JointGroups.Times(sequence, joints)
	local keys = {}
	for index, time in times do
		keys[index] = { Source = time }
	end
	local start, duration, speed, offset = view:Timing(item)
	local result = {}
	Model.KeyTimes({ Kind = "Animation", Keys = keys, Loop = item.Loop, SourceLength = item.SourceLength }, start, duration, speed, offset, function(t, key)
		table.insert(result, { T = t, Source = key.Source })
		return nil
	end)
	return result
end

function SubKeys:Render()
	local view = self.View
	local app = view.App
	local colors = view.Colors
	local pps = app.PixelsPerSecond
	local width, height = view:Width(), view:LaneHeight()
	self.Content.Position = UDim2.fromOffset(math.round(-app.ScrollTime * pps), -math.round(app.ScrollY))
	local selected = app.Selection.SubKey
	local drag = view.SubKeyDrag
	table.clear(self.Marks)
	local bars, diamonds = 0, 0
	local minX, maxX = app.ScrollTime * pps - 10, app.ScrollTime * pps + width + 10
	for _, row in view.Model.Rows do
		if SubKeys.IsSubRow(row) then
			local top = row.Y - app.ScrollY
			if top + row.Height >= 0 and top <= height then
				local centerY = row.Y + math.floor(row.Height / 2)
				local marks = {}
				self.Marks[row] = marks
				for _, item in view.Model.ByTrack[row.Track] or {} do
					local start, duration = view:Timing(item)
					local x0, x1 = start * pps, (start + duration) * pps
					if x1 >= minX and x0 <= maxX then
						bars += 1
						local bar = self:_bar(bars)
						bar.Visible = true
						bar.BackgroundColor3 = item.Color
						bar.BackgroundTransparency = 0.72
						bar.Position = UDim2.fromOffset(math.round(x0), centerY - 1)
						bar.Size = UDim2.fromOffset(math.max(math.round(x1 - x0), 2), 3)
						local last = -math.huge
						for _, mark in SubKeys.Times(view, item, row.Joints) do
							local x = mark.T * pps
							if x >= minX and x <= maxX then
								local isSelected = selected ~= nil and selected.Clip == item.Clip and math.abs(selected.Source - mark.Source) < 1e-4 and sameRow(selected, row)
								local moving = drag ~= nil and drag.Row == row and drag.Item == item and math.abs(drag.Source - mark.Source) < 1e-4
								table.insert(marks, { X = x, T = mark.T, Source = mark.Source, Item = item })
								if isSelected or moving or x - last >= 3 then
									last = x
									diamonds += 1
									local diamond = self:_diamond(diamonds)
									diamond.Visible = true
									local size = if isSelected or moving then SubKeys.Size + 2 else SubKeys.Size
									diamond.Size = UDim2.fromOffset(size, size)
									local drawX = if moving then drag.T * pps else x
									diamond.Position = UDim2.fromOffset(math.round(drawX), centerY)
									diamond.BackgroundColor3 = if isSelected or moving then colors.Accent else item.Color:Lerp(colors.Text, 0.35)
									diamond.BackgroundTransparency = if moving then 0.15 else 0
									diamond.UIStroke.Color = if isSelected then colors.Text else item.Color:Lerp(Color3.new(0, 0, 0), 0.5)
								end
							end
						end
					end
				end
			end
		end
	end
	for index = bars + 1, #self.Bars do
		self.Bars[index].Visible = false
	end
	for index = diamonds + 1, #self.Diamonds do
		self.Diamonds[index].Visible = false
	end
end

function SubKeys:Hit(row, localX)
	local marks = self.Marks[row]
	if not marks then
		return nil
	end
	local app = self.View.App
	local x = localX + app.ScrollTime * app.PixelsPerSecond
	local best, bestDistance = nil, SubKeys.HitRadius
	for _, mark in marks do
		local distance = math.abs(mark.X - x)
		if distance <= bestDistance then
			best, bestDistance = mark, distance
		end
	end
	return best
end

function SubKeys:Destroy()
	self.Content:Destroy()
	table.clear(self.Bars)
	table.clear(self.Diamonds)
	table.clear(self.Marks)
end

return SubKeys
