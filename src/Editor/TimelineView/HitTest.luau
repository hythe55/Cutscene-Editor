local Model = require(script.Parent.Model)
local Blocks = require(script.Parent.Blocks)

return function(Interaction)
	function Interaction:RowAt(localY)
		local app = self.App
		self.View:Sync()
		local contentY = localY - app.RulerHeight + app.ScrollY
		for _, row in self.View.Model.Rows do
			if contentY >= row.Y and contentY < row.Y + row.Height then
				return row, contentY
			end
		end
		return nil, contentY
	end

	function Interaction:_zone(item, hit, bx, by, bw, bh)
		local view = self.View
		local app = self.App
		local lx, ly = hit.X - bx, hit.Y - by
		local selected = app.Selection.Clips[item.Clip] == true
		local hovered = view.HoverState ~= nil and view.HoverState.Item == item
		local names = Model.Fades[item.Kind]
		if names and (selected or hovered) and not item.Locked and bw >= Blocks.MinHandleWidth and ly <= Interaction.HandleBand then
			local fadeIn, fadeOut = Blocks.HandleX(view, item, bw)
			if math.abs(lx - fadeIn) <= Interaction.HandleRadius then
				return names[1]
			end
			if fadeOut and math.abs(lx - fadeOut) <= Interaction.HandleRadius then
				return names[2]
			end
		end
		if bw >= 14 then
			if lx <= Interaction.EdgeWidth then
				return "Left"
			elseif lx >= bw - Interaction.EdgeWidth then
				return "Right"
			end
		elseif lx >= bw - 2 then
			return "Right"
		end
		local block = view.Blocks.ByClip[item.Clip]
		local marks = block and block.Item == item and not item.Loop and block.Marks
		if marks and #marks > 0 and math.abs(ly - (bh - Blocks.KeyInset)) <= Interaction.KeyBand then
			local best, bestDistance = nil, Interaction.KeyRadius
			for _, mark in marks do
				local distance = math.abs(lx - mark.X)
				if distance <= bestDistance then
					best, bestDistance = mark, distance
				end
			end
			if best then
				hit.Key, hit.KeyTime, hit.KeyEntry = best.Key.Instance, best.T, best.Key
				return "Key"
			end
		end
		return "Body"
	end

	function Interaction:HitTest(position)
		local view = self.View
		local app = self.App
		local localPosition = view:ToLocal(position)
		local x, y = localPosition.X, localPosition.Y
		local size = view.Root.AbsoluteSize
		local hit = { X = x, Y = y, Time = view:T(x), Position = position }
		if x < 0 or y < 0 or x > size.X or y > size.Y then
			hit.Area = "Outside"
			return hit
		end
		if y < app.RulerHeight then
			hit.Area = "Ruler"
			return hit
		end
		hit.Area = "Lanes"
		local row, contentY = self:RowAt(y)
		hit.Row, hit.ContentY = row, contentY
		if row and (row.Type == "KeyGroup" or row.Type == "KeyJoint") then
			hit.Track = row.Track
			hit.SubKey = view.SubKeys:Hit(row, x)
			return hit
		end
		if not row or row.Type ~= "Track" then
			return hit
		end
		hit.Track = row.Track
		local candidates = {}
		for _, item in view.Model.ByTrack[row.Track] or {} do
			local bx, by, bw, bh = view:Rect(item)
			if bx and y >= by and y <= by + bh then
				local slack = if bw < 10 then 3 else 0
				if x >= bx - slack and x <= bx + bw + slack then
					local score = (if app.Selection.Clips[item.Clip] then 1e6 else 0) + item.Start
					if x >= bx and x <= bx + bw then
						score += 1e7
					end
					table.insert(candidates, { Item = item, Score = score, Rect = { bx, by, bw, bh } })
				end
			end
		end
		if #candidates == 0 then
			return hit
		end
		table.sort(candidates, function(a, b)
			return a.Score > b.Score
		end)
		local first = candidates[1]
		local function edgeDistance(candidate, edge)
			local rect = candidate.Rect
			return math.abs(x - (if edge == "Left" then rect[1] else rect[1] + rect[3]))
		end
		local chosen, zone = first, self:_zone(first.Item, hit, table.unpack(first.Rect))
		local isEdge = zone == "Left" or zone == "Right"
		if isEdge or zone == "Body" or zone == "Key" then
			local bestDistance = if isEdge then edgeDistance(first, zone) else math.huge
			for index = 2, #candidates do
				local other = candidates[index]
				local otherZone = self:_zone(other.Item, { X = x, Y = y }, table.unpack(other.Rect))
				if otherZone == "Left" or otherZone == "Right" then
					local distance = edgeDistance(other, otherZone)
					if distance < bestDistance then
						chosen, zone, bestDistance = other, otherZone, distance
						hit.Key, hit.KeyTime, hit.KeyEntry = nil, nil, nil
					end
				end
			end
		end
		hit.Item = chosen.Item
		hit.Zone = zone
		return hit
	end
end
