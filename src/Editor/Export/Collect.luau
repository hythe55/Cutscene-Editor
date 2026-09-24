local SourceLookup = require(script.Parent.Parent.Sources)
local ServerStorage = game:GetService("ServerStorage")

local Document = require(script.Parent.Parent.Document)

local Collect = {}

Collect.TempName = "CutsceneEditorExport"

local function ordered(list)
	table.sort(list, function(a, b)
		local ao, bo = a:GetAttribute("Order") or math.huge, b:GetAttribute("Order") or math.huge
		if ao ~= bo then
			return ao < bo
		end
		return a.Name < b.Name
	end)
	return list
end

local function clipsOf(track)
	local clips = {}
	for _, child in track:GetChildren() do
		if child:IsA("Configuration") then
			table.insert(clips, child)
		end
	end
	table.sort(clips, function(a, b)
		return (a:GetAttribute("Start") or 0) < (b:GetAttribute("Start") or 0)
	end)
	return clips
end

local function filled(value)
	return type(value) == "string" and value ~= ""
end

function Collect.Sequence(target)
	return SourceLookup.Sequence(target)
end

function Collect.Length(sequence)
	local length = 0
	for _, keyframe in sequence:GetKeyframes() do
		length = math.max(length, keyframe.Time)
	end
	return length
end

function Collect.IdleOf(folder, actorId)
	local actors = folder and folder:FindFirstChild("Actors")
	local config = actors and filled(actorId) and actors:FindFirstChild(actorId)
	local idle = config and config:FindFirstChild("Idle")
	return if idle and idle:IsA("KeyframeSequence") then idle else nil
end

function Collect.Item(deps, target, folder, hashes)
	local sequence = Collect.Sequence(target)
	if not sequence then
		return nil
	end
	local ok, hash = pcall(deps.Timeline.ComputeHash, sequence)
	if not ok then
		return nil
	end
	if hashes then
		hashes:Put(sequence, hash)
	end
	local idle = target:IsA("KeyframeSequence")
	local actor = if idle then (target.Parent and target.Parent.Name) else (target.Parent and target.Parent:GetAttribute("Actor"))
	local id = target:GetAttribute("AnimationId")
	local exported = target:GetAttribute("ExportedHash")
	return {
		Clip = target,
		Targets = { target },
		Cutscene = folder,
		Actor = if filled(actor) then actor else "Scene",
		Name = if idle then "Idle" else target.Name,
		Idle = idle,
		Sequence = sequence,
		Length = Collect.Length(sequence),
		Hash = hash,
		Smooth = sequence:GetAttribute("Interpolation") == "Smooth",
		Never = not filled(id) or not filled(exported),
		Stale = not filled(id) or exported ~= hash,
	}
end

function Collect.Folders(app, all)
	if all then
		return Document.List()
	end
	return if app.Document then { app.Document.Folder } else {}
end

function Collect.Scan(app, all, hashes)
	local items = {}
	for _, folder in Collect.Folders(app, all) do
		local tracks = folder:FindFirstChild("Tracks")
		local list = {}
		for _, track in if tracks then tracks:GetChildren() else {} do
			if track:GetAttribute("Kind") == "Animation" then
				table.insert(list, track)
			end
		end
		local seen = {}
		for _, track in ordered(list) do
			local actorId = track:GetAttribute("Actor")
			if filled(actorId) and not seen[actorId] then
				seen[actorId] = true
				local idle = Collect.IdleOf(folder, actorId)
				local item = idle and Collect.Item(app.Deps, idle, folder, hashes)
				if item then
					table.insert(items, item)
				end
			end
			for _, clip in clipsOf(track) do
				local item = Collect.Item(app.Deps, clip, folder, hashes)
				if item then
					table.insert(items, item)
				end
			end
		end
	end
	return items
end

function Collect.Group(items)
	local groups, byHash = {}, {}
	for _, item in items do
		local group = byHash[item.Hash]
		if group then
			table.insert(group.Targets, item.Clip)
			group.Never = group.Never and item.Never
		else
			local copy = table.clone(item)
			copy.Targets = { item.Clip }
			byHash[item.Hash] = copy
			table.insert(groups, copy)
		end
	end
	return groups
end

function Collect.Candidates(app, all, force, hashes)
	local items = {}
	for _, item in Collect.Scan(app, all, hashes) do
		if force or item.Stale then
			table.insert(items, item)
		end
	end
	return Collect.Group(items)
end

function Collect.Count(items)
	local targets, never = 0, 0
	for _, item in items do
		targets += #item.Targets
		if item.Never then
			never += 1
		end
	end
	return targets, never
end

function Collect.Partial(app, all)
	local byActor = {}
	for _, item in Collect.Scan(app, all) do
		local key = item.Cutscene.Name .. "/" .. item.Actor
		local entry = byActor[key] or { Total = 0, Stale = 0, Name = item.Actor, Cutscene = item.Cutscene.Name }
		byActor[key] = entry
		entry.Total += 1
		if item.Stale then
			entry.Stale += 1
		end
	end
	local partial = {}
	for _, entry in byActor do
		if entry.Stale > 0 and entry.Stale < entry.Total then
			table.insert(partial, entry)
		end
	end
	table.sort(partial, function(a, b)
		return a.Name < b.Name
	end)
	return partial
end

function Collect.Prepare(deps, item)
	local copy
	if item.Smooth then
		copy = deps.Timeline.Bake(item.Sequence, 30)
	else
		local sequence = item.Sequence
		local archivable = sequence.Archivable
		if not archivable then
			sequence.Archivable = true
		end
		copy = sequence:Clone()
		if not archivable then
			sequence.Archivable = false
		end
	end
	assert(copy, "could not copy the keyframes")
	copy.Name = string.gsub(item.Actor .. "_" .. item.Name, "[^%w_%-]", "_")
	copy.Archivable = true
	if item.Idle then
		copy.Loop = true
	end
	local folder = ServerStorage:FindFirstChild(Collect.TempName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Collect.TempName
		folder.Archivable = false
		folder.Parent = ServerStorage
	end
	copy.Parent = folder
	return copy
end

function Collect.Cleanup()
	local folder = ServerStorage:FindFirstChild(Collect.TempName)
	if folder then
		folder:Destroy()
	end
end

function Collect.ParseId(value)
	if type(value) == "number" then
		return if value > 0 then math.floor(value) else nil
	end
	if type(value) ~= "string" then
		return nil
	end
	local digits = string.match(value, "(%d+)%s*$") or string.match(value, "id=(%d+)") or string.match(value, "(%d%d%d%d+)")
	local id = tonumber(digits)
	return if id and id > 0 then id else nil
end

return Collect
