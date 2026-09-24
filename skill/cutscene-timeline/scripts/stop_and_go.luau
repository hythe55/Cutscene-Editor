-- Stop-and-go detector. Paste into execute_luau (Edit datamodel); read-only.
-- For every KeyframeSequence under TARGETS, samples the runtime Sampler at 120 fps and reports interior keys
-- where a watched joint moves faster than MIN_SPEED deg/s 0.1 s before and after the key in a similar
-- direction (cos > 0.5) but drops below DROP of that speed at the key. Target: 0 outside deliberate snaps.
-- Smooth sequences (Interpolation = "Smooth") are sampled the way the game plays them.
-- Expected hits: planted-foot contacts in walk and run cycles, and deliberate snaps (a hiccup jolt). Judge the rest.

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

local cutscenes = game:GetService("ReplicatedStorage"):FindFirstChild("Cutscenes")
local RUNTIME = resolvePath(cutscenes and cutscenes:GetAttribute("RuntimePath") or "ReplicatedStorage.Timeline")
local TARGETS = { game:GetService("ServerStorage"):FindFirstChild("CutsceneSources") }
local WATCH = { "UpperArm", "LowerArm", "Hand", "Chest", "Spine", "Neck", "Head", "UpperLeg", "LowerLeg", "arm", "spine", "head" }
local MIN_SPEED, DROP, WINDOW, DT = 45, 0.3, 0.1, 1 / 120

assert(RUNTIME, "set RUNTIME to the game's Timeline module")
local Sampler = require(RUNTIME:Clone().Sampler)
local out = {}

local function watched(key)
	local leaf = string.match(key, "[^/]+$") or key
	for _, word in WATCH do
		if string.find(leaf, word, 1, true) then
			return leaf
		end
	end
	return nil
end

local function angularVelocity(a, b, dt)
	local axis, angle = a:ToObjectSpace(b):ToAxisAngle()
	return (a.Rotation * axis) * (angle / dt)
end

local function analyze(sequence, label)
	local sampler = Sampler.new(sequence)
	local frames = {}
	local t = 0
	while t <= sampler.Length + 1e-6 do
		local pose = {}
		sampler:Sample(t, function(key, cframe)
			pose[key] = cframe
		end)
		table.insert(frames, pose)
		t += DT
	end
	local watch = {}
	for key in frames[1] or {} do
		watch[key] = watched(key)
	end
	local function velocity(i, key)
		local a, b = frames[i - 1], frames[i + 1]
		if not (a and b and a[key] and b[key]) then
			return Vector3.zero
		end
		return angularVelocity(a[key], b[key], 2 * DT)
	end
	local window = math.floor(WINDOW / DT)
	local hits, checked, worst = 0, 0, {}
	for _, keyframe in sequence:GetKeyframes() do
		local kt = keyframe.Time
		if kt > WINDOW and kt < sampler.Length - WINDOW then
			local i = math.floor(kt / DT + 0.5) + 1
			for key, leaf in watch do
				local before = velocity(math.max(2, i - window), key)
				local after = velocity(math.min(#frames - 1, i + window), key)
				local mb, ma = math.deg(before.Magnitude), math.deg(after.Magnitude)
				if mb > MIN_SPEED and ma > MIN_SPEED and before.Unit:Dot(after.Unit) > 0.5 then
					checked += 1
					local at = math.deg(velocity(i, key).Magnitude)
					if at < DROP * math.min(mb, ma) then
						hits += 1
						if #worst < 4 then
							table.insert(worst, string.format("%s@%.2f %.0f>%.0f>%.0f", leaf, kt, mb, at, ma))
						end
					end
				end
			end
		end
	end
	table.insert(out, string.format("%-28s continuing %3d  stop-and-go %3d  %s", label, checked, hits, table.concat(worst, "; ")))
end

for _, root in TARGETS do
	for _, sequence in root:GetDescendants() do
		if sequence:IsA("KeyframeSequence") then
			local label = sequence:GetAttribute("Clip") or sequence.Name
			local ok, err = pcall(analyze, sequence, label)
			if not ok then
				table.insert(out, label .. " ERROR " .. tostring(err))
			end
		end
	end
end
return table.concat(out, "\n")
