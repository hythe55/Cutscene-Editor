local Model = require(script.Parent.Model)

local Snapping = {}
Snapping.__index = Snapping

Snapping.Threshold = 8
Snapping.ScrubThreshold = 4
Snapping.FrameRate = 30

function Snapping.new(view)
	local self = setmetatable({}, Snapping)
	self.View = view
	self.Points = {}
	return self
end

function Snapping.Frame(t)
	return math.round(t * Snapping.FrameRate) / Snapping.FrameRate
end

function Snapping:Enabled(mods)
	return self.View.App.Snap == true and not (mods and mods.Alt)
end

function Snapping:Collect(exclude, withPlayhead)
	local view = self.View
	local points = { 0 }
	for _, item in view.Model.Items do
		if not (exclude and exclude[item.Clip]) then
			table.insert(points, item.Start)
			table.insert(points, item.Start + item.Duration)
			if item.Row then
				Model.KeyTimes(item, item.Start, item.Duration, item.Speed, item.ClipOffset, function(t)
					table.insert(points, t)
					return nil
				end)
			end
		end
	end
	if withPlayhead ~= false then
		table.insert(points, view.App.Time)
	end
	if view.Model.Length > 0 then
		table.insert(points, view.Model.Length)
	end
	table.sort(points)
	self.Points = points
	return points
end

function Snapping:Add(times)
	for _, t in times do
		table.insert(self.Points, t)
	end
	table.sort(self.Points)
end

function Snapping:Nearest(t)
	local points = self.Points
	local count = #points
	if count == 0 then
		return nil
	end
	local low, high = 1, count
	while low < high do
		local middle = (low + high) // 2
		if points[middle] < t then
			low = middle + 1
		else
			high = middle
		end
	end
	local best = points[low]
	if low > 1 and math.abs(points[low - 1] - t) < math.abs(best - t) then
		best = points[low - 1]
	end
	return best
end

function Snapping:Radius(pixels)
	return (pixels or Snapping.Threshold) / self.View.App.PixelsPerSecond
end

function Snapping:Time(t, mods, pixels)
	if not self:Enabled(mods) then
		return t, nil
	end
	local best = self:Nearest(t)
	if best and math.abs(best - t) <= self:Radius(pixels) then
		return best, best
	end
	return Snapping.Frame(t), nil
end

function Snapping:Delta(edges, delta, anchor, mods)
	if not self:Enabled(mods) then
		return delta, nil
	end
	local radius = self:Radius()
	local bestDistance, bestDelta, bestTime = math.huge, nil, nil
	for _, edge in edges do
		local moved = edge + delta
		local point = self:Nearest(moved)
		if point then
			local distance = math.abs(point - moved)
			if distance < bestDistance then
				bestDistance, bestDelta, bestTime = distance, point - edge, point
			end
		end
	end
	if bestDelta and bestDistance <= radius then
		return bestDelta, bestTime
	end
	return Snapping.Frame(anchor + delta) - anchor, nil
end

return Snapping
