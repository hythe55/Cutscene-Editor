--!nocheck
-- Read-only validation for one timeline. Paste into execute_luau (Edit datamodel). It never edits the place:
-- Tag actors are swapped for Template copies inside an unparented probe, and the preview Timeline lives in an
-- unparented container. Poses and pivots come from the runtime's own maths (ctx:PoseAt, PivotAt, ProbeJointCFrame).
-- Copy it next to your build script and add scene-specific checks (reach, door jambs, hidden actors, seats).
-- Returns "PASS" or "FAIL" followed by the report.

local CUTSCENE = "MyCutscene"
local FPS = 30
local NEAR = 0.4
local CAMERA_IGNORE_TAGS = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local out, failures = {}, 0
local function fail(...)
	failures += 1
	table.insert(out, "FAIL " .. table.concat({ ... }, " "))
end
local function info(...)
	table.insert(out, "info " .. table.concat({ ... }, " "))
end

local function resolvePath(path)
	local node = game
	for _, name in string.split(path, ".") do
		if name ~= "game" then
			if node == game then
				local ok, service = pcall(game.GetService, game, name)
				node = if ok and service then service else game:FindFirstChild(name)
			else
				node = node:FindFirstChild(name)
			end
			if not node then
				return nil
			end
		end
	end
	return node
end

local cutscenes = ReplicatedStorage:FindFirstChild("Cutscenes")
local folder = cutscenes and cutscenes:FindFirstChild(CUTSCENE)
assert(folder, "no ReplicatedStorage.Cutscenes." .. CUTSCENE)
local runtimeSource = resolvePath(cutscenes:GetAttribute("RuntimePath") or "ReplicatedStorage.Timeline")
assert(runtimeSource, "runtime not found; set RuntimePath on ReplicatedStorage.Cutscenes")
local runtime = runtimeSource:Clone()
local Timeline = require(runtime)
local Spline = require(runtime.Spline)
local Sources = Timeline.Sources

local probe = folder:Clone()
for _, config in probe.Actors:GetChildren() do
	if config:GetAttribute("Source") == "Tag" then
		local tag = config:GetAttribute("Tag")
		local found
		for _, inst in CollectionService:GetTagged(tag) do
			if inst:IsA("PVInstance") and inst.Archivable then
				found = inst
				if inst:IsDescendantOf(workspace) then
					break
				end
			end
		end
		if not found then
			fail("actor", config.Name, "tag", tostring(tag), "has no model")
		else
			local copy = found:Clone()
			for _, d in copy:GetDescendants() do
				for _, t in CollectionService:GetTags(d) do
					CollectionService:RemoveTag(d, t)
				end
			end
			for _, t in CollectionService:GetTags(copy) do
				CollectionService:RemoveTag(copy, t)
			end
			copy.Name = "Template"
			copy.Parent = config
			config:SetAttribute("Source", "Template")
		end
	end
end

local fakeBox = {}
function fakeBox:Open() end
function fakeBox:Close()
	return { Wait = function() end, Connect = function() end, Once = function() end }
end
function fakeBox:Say()
	return { Done = true }
end
function fakeBox:Render() end
function fakeBox:Destroy() end

local container = Instance.new("Folder")
container.Archivable = false
local timeline = Timeline.new(probe, { Preview = true, Container = container, DialogueBox = fakeBox })
local ctx = timeline.Context

local function clipsOf(kind)
	local list = {}
	for _, track in folder.Tracks:GetChildren() do
		if track:GetAttribute("Kind") == kind and not track:GetAttribute("Muted") then
			for _, clip in track:GetChildren() do
				if clip:IsA("Configuration") then
					table.insert(list, { Clip = clip, Track = track, Actor = track:GetAttribute("Actor"), Start = clip:GetAttribute("Start") or 0, Duration = clip:GetAttribute("Duration") or 0 })
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Start < b.Start
	end)
	return list
end

local actorIds = {}
for _, config in folder.Actors:GetChildren() do
	actorIds[config.Name] = true
end
for _, track in folder.Tracks:GetChildren() do
	local actorId = track:GetAttribute("Actor")
	if actorId and actorId ~= "" and not actorIds[actorId] then
		fail("track", track.Name, "names missing actor", actorId)
	end
	if not runtime.Tracks:FindFirstChild(track:GetAttribute("Kind") or "") then
		fail("track", track.Name, "has unknown kind", tostring(track:GetAttribute("Kind")))
	end
end

local cameras = clipsOf("Camera")
for index = 2, #cameras do
	local previous, current = cameras[index - 1], cameras[index]
	if current.Start < previous.Start + previous.Duration - 1e-4 then
		fail("camera clips overlap:", previous.Clip.Name, current.Clip.Name)
	end
end

local exportedActor = {}
local byActor = {}
for _, entry in clipsOf("Animation") do
	byActor[entry.Actor] = byActor[entry.Actor] or {}
	table.insert(byActor[entry.Actor], entry.Clip)
end
for actorId, clips in byActor do
	local all = true
	for _, clip in clips do
		if not Sources.IsExported(clip, Sources.Keyframes(clip)) then
			all = false
		end
	end
	local idle = folder.Actors:FindFirstChild(actorId) and folder.Actors[actorId]:FindFirstChild("Idle")
	if idle and not Sources.IsExported(idle, Sources.Keyframes(idle)) then
		all = false
	end
	exportedActor[actorId] = all
	info("actor", actorId, if all then "plays uploaded animations" else "plays keyframes")
end

for _, entry in clipsOf("Animation") do
	local clip = entry.Clip
	local sourceId = clip:GetAttribute("SourceId")
	local source = Sources.Find(clip)
	local sequence = Sources.Keyframes(clip)
	if sourceId and sourceId ~= "" and not source then
		fail("animation", clip.Name, "SourceId", sourceId, "missing from ServerStorage.CutsceneSources")
	end
	if not sequence then
		fail("animation", clip.Name, "has no keyframes")
		continue
	end
	if source and clip:GetAttribute("ContentHash") ~= Sources.Hash(source) then
		fail("animation", clip.Name, "ContentHash is stale")
	end
	if not exportedActor[entry.Actor] and not Sources.Replica(clip) then
		fail("animation", clip.Name, "has no client keyframes but its actor plays keyframes")
	end
	local rig = ctx:GetRig(entry.Actor)
	local firstKey, nan, unknown = {}, 0, {}
	for _, keyframe in sequence:GetKeyframes() do
		for _, pose in keyframe:GetDescendants() do
			if pose:IsA("Pose") and pose.Weight > 0 then
				local c = pose.CFrame
				if c.X ~= c.X or c.Y ~= c.Y or c.Z ~= c.Z or c.LookVector.X ~= c.LookVector.X then
					nan += 1
				end
				local path, node = {}, pose
				while node and node:IsA("Pose") and node.Parent:IsA("Pose") do
					table.insert(path, 1, node.Name)
					node = node.Parent
				end
				local key = table.concat(path, "/")
				firstKey[key] = math.min(firstKey[key] or math.huge, keyframe.Time)
				if rig and key ~= "" and not rig:Find(key) then
					unknown[key] = true
				end
			end
		end
	end
	if nan > 0 then
		fail("animation", clip.Name, nan .. " NaN poses")
	end
	for key in unknown do
		fail("animation", clip.Name, "pose path", key, "matches no joint (check nesting and root pose name)")
		break
	end
	for key, t in firstKey do
		if t > 1e-3 then
			info("animation", clip.Name, "joint", key, string.format("first keyed at %.2f (identity before)", t))
			break
		end
	end
end

local provider
local modulePath = cutscenes:GetAttribute("DialogueModule")
local module = modulePath and resolvePath(modulePath)
if module then
	local ok, loaded = pcall(require, module:Clone())
	provider = ok and loaded or nil
end
local readingTime = (provider and provider.ReadingTime) or Timeline.FallbackDialogueBox.ReadingTime
for _, entry in clipsOf("Dialogue") do
	local text = entry.Clip:GetAttribute("Text") or ""
	local typeSpeed = entry.Clip:GetAttribute("TypeSpeed")
	local needed = readingTime(text, if typeSpeed and typeSpeed > 0 then typeSpeed else nil, entry.Clip:GetAttribute("Mood"))
	if entry.Duration + 1e-3 < needed then
		fail(string.format("dialogue %s lasts %.2f s, reading time %.2f s", entry.Clip.Name, entry.Duration, needed))
	end
end

local ignored = { container }
for _, tag in CAMERA_IGNORE_TAGS do
	for _, inst in CollectionService:GetTagged(tag) do
		table.insert(ignored, inst)
	end
end
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
overlap.FilterDescendantsInstances = ignored
local function clearance(point)
	local worst, worstPart = math.huge, nil
	for _, part in workspace:GetPartBoundsInRadius(point, NEAR + 0.1, overlap) do
		if part.Transparency < 0.95 then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { part }
			local distance, inside = math.huge, true
			for x = -1, 1 do
				for y = -1, 1 do
					for z = -1, 1 do
						if x ~= 0 or y ~= 0 or z ~= 0 then
							local hit = workspace:Raycast(point, Vector3.new(x, y, z).Unit * (NEAR + 0.1), params)
							if hit then
								distance = math.min(distance, hit.Distance)
							else
								inside = false
							end
						end
					end
				end
			end
			if inside and distance == math.huge then
				distance = 0
			end
			if distance < worst then
				worst, worstPart = distance, part
			end
		end
	end
	return worst, worstPart
end

for _, entry in cameras do
	local clip = entry.Clip
	local keys = Spline.ReadKeys(clip:FindFirstChild("Keys"))
	local anchor = clip:GetAttribute("Anchor") or ""
	local worst, worstPart, worstT = math.huge, nil, 0
	local t = entry.Start
	while t < entry.Start + entry.Duration - 1e-4 do
		local cf = Spline.Evaluate(keys, (t - entry.Start) * (clip:GetAttribute("Speed") or 1), clip:GetAttribute("Interpolation"))
		if anchor ~= "" then
			local anchorCF = ctx:ProbeJointCFrame(anchor, clip:GetAttribute("AnchorJoint"), t)
			cf = anchorCF and anchorCF * cf or cf
		end
		local distance, part = clearance(cf.Position)
		if distance < worst then
			worst, worstPart, worstT = distance, part, t
		end
		t += 1 / FPS
	end
	if worst < NEAR then
		fail(string.format("camera %s near plane %.2f studs from %s at %.2f", clip.Name, worst, worstPart and worstPart:GetFullName() or "?", worstT))
	end
end

timeline:Destroy()
container:Destroy()
probe:Destroy()
return (if failures == 0 then "PASS" else "FAIL") .. string.format(" (%d failures, length %.2f)\n", failures, Timeline.GetLength(folder)) .. table.concat(out, "\n")
