local JointGroups = {}

JointGroups.Order = { "Body", "Head", "Left Arm", "Left Hand", "Right Arm", "Right Hand", "Left Leg", "Right Leg", "Legs", "Cloth", "Other" }

local RULES = {
	{ "Hand", { "thumb", "index", "middle", "ring", "pinky", "finger", "hand", "palm", "wrist" } },
	{ "Arm", { "shoulder", "clavicle", "elbow", "forearm", "arm" } },
	{ "Head", { "head", "neck", "jaw", "eye", "brow", "lip", "mouth", "tongue", "teeth", "ear", "nose", "hair", "face" } },
	{ "Leg", { "thigh", "shin", "calf", "knee", "foot", "feet", "toe", "ankle", "shoe", "leg" } },
	{ "Cloth", { "skirt", "dress", "cloth", "coat", "cape", "tail", "sleeve", "scarf", "tie", "under", "bone" } },
	{ "Body", { "root", "cog", "hip", "pelvis", "spine", "chest", "torso", "waist", "ctrl", "body", "belly", "abdomen" } },
}

local SIDED = { Hand = true, Arm = true, Leg = true }

local cache = setmetatable({}, { __mode = "k" })

local function sideOf(name)
	local lower = string.lower(name)
	if string.find(lower, "left", 1, true) or string.match(lower, "[%._%- ]l$") or string.match(lower, "[%._%- ]l[%._%- ]") or string.match(lower, "^l[%._%- ]") then
		return "Left"
	end
	if string.find(lower, "right", 1, true) or string.match(lower, "[%._%- ]r$") or string.match(lower, "[%._%- ]r[%._%- ]") or string.match(lower, "^r[%._%- ]") then
		return "Right"
	end
	return nil
end

local function categoryOf(name)
	local lower = string.lower(name)
	for _, rule in RULES do
		for _, word in rule[2] do
			if string.find(lower, word, 1, true) then
				return rule[1]
			end
		end
	end
	return nil
end

function JointGroups.Classify(key)
	local segments = string.split(key, "/")
	local leaf = segments[#segments]
	local category
	for index = #segments, 1, -1 do
		category = categoryOf(segments[index])
		if category then
			break
		end
	end
	category = category or "Other"
	if category == "Leg" and categoryOf(leaf) == "Body" then
		category = "Body"
	end
	if not SIDED[category] then
		return category
	end
	local side
	for index = #segments, 1, -1 do
		side = sideOf(segments[index])
		if side then
			break
		end
	end
	if not side then
		return if category == "Leg" then "Legs" else "Other"
	end
	return side .. " " .. category
end

function JointGroups.Leaf(key)
	local segments = string.split(key, "/")
	return segments[#segments]
end

local function walk(pose, path, time, joints)
	for _, child in pose:GetChildren() do
		if child:IsA("Pose") then
			local key = if path == "" then child.Name else path .. "/" .. child.Name
			if child.Weight > 0 then
				local list = joints[key]
				if not list then
					list = {}
					joints[key] = list
				end
				table.insert(list, time)
			end
			walk(child, key, time, joints)
		end
	end
end

function JointGroups.Scan(sequence)
	local keyframes = sequence:GetKeyframes()
	local stamp = #keyframes .. ":" .. #sequence:GetDescendants()
	local cached = cache[sequence]
	if cached and cached.Stamp == stamp then
		return cached.Joints
	end
	local joints = {}
	for _, keyframe in keyframes do
		for _, root in keyframe:GetChildren() do
			if root:IsA("Pose") then
				walk(root, "", keyframe.Time, joints)
			end
		end
	end
	for _, list in joints do
		table.sort(list)
	end
	cache[sequence] = { Stamp = stamp, Joints = joints }
	return joints
end

function JointGroups.Invalidate(sequence)
	if sequence then
		cache[sequence] = nil
	else
		table.clear(cache)
	end
end

function JointGroups.ForTrack(document, info)
	local keys = {}
	for _, clip in info.Clips do
		local sequence = document:GetSequence(clip)
		if sequence then
			for key in JointGroups.Scan(sequence) do
				keys[key] = true
			end
		end
	end
	local byGroup = {}
	for key in keys do
		local group = JointGroups.Classify(key)
		byGroup[group] = byGroup[group] or {}
		table.insert(byGroup[group], key)
	end
	local groups = {}
	for _, name in JointGroups.Order do
		local joints = byGroup[name]
		if joints then
			table.sort(joints)
			table.insert(groups, { Name = name, Joints = joints })
		end
	end
	return groups
end

function JointGroups.Times(sequence, joints)
	local scan = JointGroups.Scan(sequence)
	local seen, times = {}, {}
	for _, key in joints do
		for _, time in scan[key] or {} do
			local rounded = math.round(time * 10000)
			if not seen[rounded] then
				seen[rounded] = true
				table.insert(times, time)
			end
		end
	end
	table.sort(times)
	return times
end

return JointGroups
