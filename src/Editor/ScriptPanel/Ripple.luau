local Context = require(script.Parent.Parent.Inspector.Context)

local Ripple = {}

Ripple.Epsilon = 1e-3
Ripple.FrameRate = 30

local state = setmetatable({}, { __mode = "k" })

local function round(value)
	return math.round(value * 10000) / 10000
end

function Ripple.Settings(app)
	local current = state[app]
	if current then
		return current.Ripple, current.All
	end
	return app:GetSetting("Script.Ripple", false) == true, app:GetSetting("Script.RippleAll", false) == true
end

function Ripple.Set(app, ripple, all)
	state[app] = { Ripple = ripple == true, All = all == true }
	app:SetSetting("Script.Ripple", ripple == true)
	app:SetSetting("Script.RippleAll", all == true)
end

function Ripple.Shift(document, clip, from, delta, all)
	local lane = clip.Parent
	local moved = 0
	for _, track in document:GetTracks() do
		if track:GetAttribute("Locked") ~= true and (all or track == lane) then
			for _, other in document:GetClips(track) do
				local start = other:GetAttribute("Start") or 0
				if other ~= clip and start >= from - Ripple.Epsilon then
					document:WriteAttribute(other, "Start", round(start + delta))
					moved += 1
				end
			end
		end
	end
	return moved
end

function Ripple.SetDurations(app, changes, label)
	if #changes == 0 then
		return 0
	end
	local ripple, all = Ripple.Settings(app)
	return Context.Write(app, label or "Retime lines", function(document)
		table.sort(changes, function(a, b)
			return (a.Clip:GetAttribute("Start") or 0) < (b.Clip:GetAttribute("Start") or 0)
		end)
		local count = 0
		for _, change in changes do
			local clip = change.Clip
			if document:IsClip(clip) and clip.Parent:GetAttribute("Locked") ~= true then
				local start = clip:GetAttribute("Start") or 0
				local old = clip:GetAttribute("Duration") or 0
				local new = round(math.max(change.Duration, 0))
				if math.abs(new - old) > 1e-4 then
					document:WriteAttribute(clip, "Duration", new)
					count += 1
					if ripple and new > old then
						Ripple.Shift(document, clip, start + old, new - old, all)
					end
				end
			end
		end
		return count
	end)
end

function Ripple.ReadingTime(app, clip)
	return Context.ReadingTime(app, clip:GetAttribute("Text") or "", clip:GetAttribute("TypeSpeed"), clip:GetAttribute("Mood"))
end

function Ripple.FitTarget(app, clip)
	return math.ceil(Ripple.ReadingTime(app, clip) * Ripple.FrameRate - 1e-6) / Ripple.FrameRate
end

function Ripple.Fit(app, clips, mode, label)
	local changes = {}
	for _, clip in clips do
		local target = Ripple.FitTarget(app, clip)
		local duration = clip:GetAttribute("Duration") or 0
		if (mode == "Exact" and math.abs(duration - target) > 1e-4) or duration < target - 1e-4 then
			table.insert(changes, { Clip = clip, Duration = target })
		end
	end
	if #changes == 0 then
		return 0
	end
	return Ripple.SetDurations(app, changes, label or "Fit lines to reading time") or 0
end

function Ripple.NewLane(document)
	local folder = document.Folder:FindFirstChild("Tracks")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Tracks"
		document:Touch(folder)
		folder.Parent = document.Folder
	end
	local order = -1
	for _, existing in document:GetTracks() do
		order = math.max(order, existing:GetAttribute("Order") or 0)
	end
	local track = Instance.new("Folder")
	track.Name = document.Unique(folder, "Dialogue")
	document:Touch(track)
	track:SetAttribute("Kind", "Dialogue")
	track:SetAttribute("Actor", "")
	track:SetAttribute("Order", order + 1)
	track:SetAttribute("Muted", false)
	track:SetAttribute("Locked", false)
	track.Parent = folder
	return track
end

function Ripple.Insert(app, track, start, props, anchor)
	local ripple, all = Ripple.Settings(app)
	return Context.Write(app, "Add line", function(document)
		track = track or Ripple.NewLane(document)
		assert(document:IsTrack(track), "Add line needs a Dialogue track")
		local clip = document:WriteClip(track, start, props)
		clip.Parent = track
		if ripple then
			local finish = start + (clip:GetAttribute("Duration") or 0)
			local following = math.huge
			for _, other in document:GetClips(track) do
				local otherStart = other:GetAttribute("Start") or 0
				if other ~= clip and other ~= anchor and otherStart >= start - Ripple.Epsilon then
					following = math.min(following, otherStart)
				end
			end
			if following < finish then
				Ripple.Shift(document, clip, start, finish - following, all)
			end
		end
		return clip
	end)
end

return Ripple
