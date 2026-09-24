local Schema = require(script.Parent.Schema)

local Data = {}

local TrackInfo = {}
TrackInfo.__index = TrackInfo

function TrackInfo:GetAttribute(name)
	return self.Instance:GetAttribute(name)
end

function TrackInfo:FindFirstChild(name)
	return self.Instance:FindFirstChild(name)
end

function Data.Tracks(folder)
	local list = {}
	local tracks = folder:FindFirstChild("Tracks")
	if not tracks then
		return list
	end
	for _, instance in tracks:GetChildren() do
		if instance:IsA("Folder") or instance:IsA("Configuration") then
			local info = Schema.Read(instance, "Track")
			if info.Kind ~= "" then
				info.Instance = instance
				info.Name = instance.Name
				table.insert(list, setmetatable(info, TrackInfo))
			end
		end
	end
	table.sort(list, function(a, b)
		if a.Order ~= b.Order then
			return a.Order < b.Order
		end
		return a.Name < b.Name
	end)
	return list
end

function Data.Clips(trackInstance)
	local clips = {}
	for _, clip in trackInstance:GetChildren() do
		if clip:IsA("Configuration") then
			table.insert(clips, clip)
		end
	end
	return clips
end

local function playable(kind)
	local tracks = script.Parent:FindFirstChild("Tracks")
	return Schema.Kinds[kind] ~= nil and tracks ~= nil and tracks:FindFirstChild(kind) ~= nil
end

function Data.Length(folder)
	local length = 0
	for _, track in Data.Tracks(folder) do
		if not track.Muted and playable(track.Kind) then
			for _, clip in Data.Clips(track.Instance) do
				local props = Schema.ReadCommon(clip)
				length = math.max(length, props.Start + props.Duration)
			end
		end
	end
	return length
end

function Data.ServerEvents(folder)
	local events = {}
	for _, track in Data.Tracks(folder) do
		if not track.Muted and track.Kind == "Event" then
			for _, clip in Data.Clips(track.Instance) do
				local props = Schema.Read(clip, "Event")
				if props.Side == "Server" or props.Side == "Both" then
					table.insert(events, { Name = props.Name, Phase = "Start", Time = props.Start, Data = props.Data })
					if props.Duration > 0 then
						table.insert(events, { Name = props.Name, Phase = "End", Time = props.Start + props.Duration, Data = props.Data })
					end
				end
			end
		end
	end
	table.sort(events, function(a, b)
		return a.Time < b.Time
	end)
	return events
end

return Data
