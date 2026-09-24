local Model = require(script.Parent.Model)

local Drag = {}

Drag.Threshold = 3
Drag.MinDuration = 1 / 30
Drag.MinSpeed = 0.05
Drag.MaxSpeed = 10

local EPSILON = 1e-6

local function round(value)
	return math.round(value * 10000) / 10000
end

local function pending(origin, position)
	return (position - origin).Magnitude < Drag.Threshold
end

local function localTime(view, position)
	return view:T(view:ToLocal(position).X)
end

function Drag.Scrub(interaction, _hit, position, button, mods)
	local view = interaction.View
	local app = view.App
	view.Snapping:Collect(nil, false)
	local drag = { Kind = "Scrub", Button = button }
	function drag.Move(_, pos, keys)
		local t = math.clamp(localTime(view, pos), 0, math.max(view.Model.Length, 0))
		local snapped, line = view.Snapping:Time(t, keys, view.Snapping.ScrubThreshold)
		view.SnapTime = line
		app:SetTime(snapped)
		view:Invalidate("Drag")
	end
	function drag.Finish() end
	function drag.Cancel() end
	drag:Move(position, mods)
	return drag
end

function Drag.Move(interaction, hit, position, clickReplace)
	local view = interaction.View
	local app = view.App
	local anchor = hit.Item
	local items, exclude, edges = {}, {}, {}
	local locked = anchor.Locked
	local minStart = math.huge
	local sameTrack = true
	for clip in app.Selection.Clips do
		local item = view.Model.ByClip[clip]
		if item then
			if item.Locked then
				locked = true
			else
				table.insert(items, item)
				exclude[clip] = true
				table.insert(edges, item.Start)
				table.insert(edges, item.Start + item.Duration)
				minStart = math.min(minStart, item.Start)
				sameTrack = sameTrack and item.Track == anchor.Track
			end
		end
	end
	if anchor.Locked then
		table.clear(items)
	end
	view.Snapping:Collect(exclude)
	view.Snapping:Add(edges)
	local startTime = hit.Time
	local drag = { Kind = "Move", Button = 1, Started = false, Delta = 0, Target = nil, Items = items }
	function drag.Move(self, pos, keys)
		if not self.Started then
			if pending(position, pos) then
				return
			end
			if #items == 0 then
				if locked and not self.Warned then
					self.Warned = true
					app:Notify("That track is locked", "Warn")
				end
				return
			end
			self.Started = true
		end
		local localPosition = view:ToLocal(pos)
		local raw = math.max(view:T(localPosition.X) - startTime, -minStart)
		local delta, line = view.Snapping:Delta(edges, raw, anchor.Start, keys)
		delta = math.max(delta, -minStart)
		local target = nil
		if sameTrack then
			local row = interaction:RowAt(localPosition.Y)
			if row and row.Type == "Track" and row.Kind == anchor.Kind and row.Track ~= anchor.Track and not row.Info.Locked then
				target = row
			end
		end
		self.Delta, self.Target = delta, target
		view.SnapTime = line
		for _, item in items do
			view.Overrides[item.Clip] = { Start = item.Start + delta, Row = target }
		end
		view.Lanes:ShowDrop(target)
		view:Invalidate("Drag")
	end
	function drag.Finish(self)
		if not self.Started then
			if clickReplace then
				app:Select(anchor.Clip, "Replace")
			end
			return
		end
		if math.abs(self.Delta) < EPSILON and not self.Target then
			table.clear(view.Overrides)
			return
		end
		local clips = {}
		for _, item in items do
			table.insert(clips, item.Clip)
		end
		local result = app.Document:MoveClips(clips, self.Delta, self.Target and self.Target.Track)
		if result == nil then
			table.clear(view.Overrides)
		end
	end
	function drag.Cancel() end
	return drag
end

function Drag.Retime(interaction, hit, position, edge)
	local view = interaction.View
	local app = view.App
	local item = hit.Item
	if item.Locked then
		app:Notify("That track is locked", "Warn")
		return nil
	end
	view.Snapping:Collect({ [item.Clip] = true })
	local start, duration = item.Start, item.Duration
	local finish = start + duration
	local loop = item.Kind == "Animation" and item.Loop
	local sourceSpan = duration * item.Speed
	local drag = { Kind = "Retime", Button = 1, Started = false, Edge = edge, Item = item }
	function drag.Move(self, pos, keys)
		if not self.Started and pending(position, pos) then
			return
		end
		self.Started = true
		local shift = keys.Shift == true
		local speedMode = Model.Retime[item.Kind] == true and duration > 0 and (if loop then shift else not shift)
		local shortest, longest = Drag.MinDuration, math.huge
		if speedMode then
			shortest = math.max(sourceSpan / Drag.MaxSpeed, Drag.MinDuration)
			longest = math.max(sourceSpan / Drag.MinSpeed, shortest)
		end
		local snapped, line = view.Snapping:Time(localTime(view, pos), keys)
		local newStart, newDuration = start, duration
		if edge == "Left" then
			newStart = math.clamp(snapped, math.max(finish - longest, 0), math.max(finish - shortest, 0))
			newDuration = finish - newStart
		else
			newDuration = math.clamp(snapped - start, shortest, longest)
		end
		if math.abs(newStart - snapped) > 1e-4 and math.abs(newStart + newDuration - snapped) > 1e-4 then
			line = nil
		end
		local override = { Start = newStart, Duration = newDuration }
		local result = { Start = newStart, Duration = newDuration, Trim = not speedMode }
		if speedMode then
			override.Speed = math.clamp(sourceSpan / newDuration, Drag.MinSpeed, Drag.MaxSpeed)
		elseif edge == "Left" and item.Kind == "Animation" then
			local offset = item.ClipOffset + (newStart - start) * item.Speed
			if loop and item.SourceLength > 0 then
				offset %= item.SourceLength
				result.ClipOffset = round(offset)
			end
			override.ClipOffset = math.max(offset, 0)
		end
		self.Result = result
		view.Overrides[item.Clip] = override
		view.SnapTime = line
		view:Invalidate("Drag")
	end
	function drag.Finish(self)
		local result = self.Result
		if not result or (math.abs(result.Start - start) < EPSILON and math.abs(result.Duration - duration) < EPSILON) then
			view.Overrides[item.Clip] = nil
			return
		end
		local document = app.Document
		local written
		if result.ClipOffset then
			written = document:SetAttributes(item.Clip, {
				Start = round(math.max(result.Start, 0)),
				Duration = round(result.Duration),
				ClipOffset = result.ClipOffset,
			})
		else
			written = document:SetClipTiming(item.Clip, result.Start, result.Duration, result.Trim)
		end
		if written == nil then
			view.Overrides[item.Clip] = nil
		end
	end
	function drag.Cancel() end
	return drag
end

function Drag.Fade(interaction, hit, position, name)
	local view = interaction.View
	local app = view.App
	local item = hit.Item
	local names = Model.Fades[item.Kind]
	local incoming = name == names[1]
	local other = if incoming then names[2] else names[1]
	local original = view:Fade(item, name)
	view.Snapping:Collect(nil)
	local drag = { Kind = "Fade", Button = 1, Started = false, Item = item, Name = name }
	function drag.Move(self, pos, keys)
		if not self.Started and pending(position, pos) then
			return
		end
		self.Started = true
		local snapped, line = view.Snapping:Time(localTime(view, pos), keys)
		local room = math.max(item.Duration - (if other then view:Fade(item, other) else 0), 0)
		local value = if incoming then snapped - item.Start else item.Start + item.Duration - snapped
		value = math.round(math.clamp(value, 0, room) * 1000) / 1000
		self.Value = value
		view.Overrides[item.Clip] = { [name] = value }
		view.SnapTime = line
		view:Invalidate("Drag")
	end
	function drag.Finish(self)
		local value = self.Value
		if value == nil or math.abs(value - original) < EPSILON then
			view.Overrides[item.Clip] = nil
			return
		end
		if app.Document:SetAttribute(item.Clip, name, value) == nil then
			view.Overrides[item.Clip] = nil
		end
	end
	function drag.Cancel() end
	return drag
end

function Drag.Key(interaction, hit, position)
	local view = interaction.View
	local app = view.App
	local item = hit.Item
	local entry = hit.KeyEntry
	local key = hit.Key
	local original = entry.Source
	app:SelectKey(key)
	view.Snapping:Collect(nil)
	local drag = { Kind = "Key", Button = 1, Started = false, Item = item, Key = key }
	function drag.Move(self, pos, keys)
		if not self.Started then
			if pending(position, pos) or item.Locked then
				return
			end
			self.Started = true
		end
		local start, duration, speed, offset = view:Timing(item)
		local snapped, line = view.Snapping:Time(localTime(view, pos), keys)
		local t = math.clamp(snapped, start, start + duration)
		local source = (t - start) * speed + (if item.Kind == "Animation" then offset else 0)
		self.Source = math.max(math.round(source * 10000) / 10000, 0)
		entry.Source = self.Source
		view.SnapTime = line
		view:Invalidate("Drag")
	end
	function drag.Finish(self)
		entry.Source = original
		if not self.Started then
			app:SetTime(hit.KeyTime)
			return
		end
		local source = self.Source
		if source == nil or math.abs(source - original) < EPSILON then
			view:Invalidate("Drag")
			return
		end
		local document = app.Document
		if item.Kind == "Animation" then
			entry.Source = source
			Model.Invalidate(item.Sequence)
			if document:SetKeyframeTime(key, source) == nil then
				entry.Source = original
			end
		else
			entry.Source = source
			if document:SetKey(key, nil, { Time = source }) == nil then
				entry.Source = original
			end
		end
	end
	function drag.Cancel()
		entry.Source = original
	end
	return drag
end

function Drag.Marquee(interaction, hit, position, mods)
	local view = interaction.View
	local app = view.App
	local additive = mods.Shift == true or mods.Ctrl == true
	local base = {}
	if additive then
		for clip in app.Selection.Clips do
			base[clip] = true
		end
	end
	local drag = { Kind = "Marquee", Button = 1, Started = false }
	function drag.Move(self, pos)
		if not self.Started and pending(position, pos) then
			return
		end
		self.Started = true
		local localPosition = view:ToLocal(pos)
		local contentY = localPosition.Y - app.RulerHeight + app.ScrollY
		local hits = view.Marquee:Set(hit.Time, hit.ContentY or 0, view:T(localPosition.X), contentY)
		local union = table.clone(base)
		for clip in hits do
			union[clip] = true
		end
		self.Result = union
		view.Preselect = union
		view:Invalidate("Drag")
	end
	function drag.Finish(self)
		view.Marquee:Clear()
		view.Preselect = nil
		if not self.Started then
			if not additive then
				if hit.Row and hit.Row.Type == "Track" then
					app:Select(hit.Row.Track)
				else
					app:Select({}, "Replace")
				end
			end
			return
		end
		local list = {}
		for clip in self.Result or base do
			table.insert(list, clip)
		end
		app:Select(list, "Replace")
	end
	function drag.Cancel() end
	return drag
end

return Drag
