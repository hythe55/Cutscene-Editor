local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Runtime = {}

Runtime.DefaultPath = "ReplicatedStorage.Timeline"

local function split(path)
	path = string.gsub(path or "", "^game%.", "")
	local segments = {}
	for segment in string.gmatch(path, "[^%.]+") do
		table.insert(segments, segment)
	end
	return segments
end

local function service(name)
	local ok, found = pcall(game.FindService, game, name)
	if ok and found then
		return found
	end
	return game:FindFirstChild(name)
end

function Runtime.Resolve(path)
	local segments = split(path)
	if #segments == 0 then
		return nil
	end
	local current = service(segments[1])
	for index = 2, #segments do
		if not current then
			return nil
		end
		current = current:FindFirstChild(segments[index])
	end
	return current
end

function Runtime.Path()
	local root = ReplicatedStorage:FindFirstChild("Cutscenes")
	local path = root and root:GetAttribute("RuntimePath")
	if type(path) == "string" and path ~= "" then
		return path, true
	end
	return Runtime.DefaultPath, false
end

function Runtime.ReadVersion(module)
	local version = module and module:FindFirstChild("Version")
	if not version or not version:IsA("ModuleScript") then
		return nil
	end
	local ok, source = pcall(function()
		return version.Source
	end)
	if not ok then
		return nil
	end
	return string.match(source, "return%s*[\"']([^\"']+)[\"']")
end

function Runtime.Compare(a, b)
	local pa, pb = split(a), split(b)
	for index = 1, math.max(#pa, #pb) do
		local x, y = tonumber(pa[index]) or 0, tonumber(pb[index]) or 0
		if x ~= y then
			return if x < y then -1 else 1
		end
	end
	return 0
end

function Runtime.Detect(deps)
	local path, explicit = Runtime.Path()
	local installed = Runtime.Resolve(path)
	local bundled = deps and deps.Timeline and deps.Timeline.Version or "?"
	local info = { Path = path, Explicit = explicit, Bundled = bundled, Installed = installed }
	if not installed or not installed:IsA("ModuleScript") then
		info.Status = "Missing"
		info.Label = "Runtime not installed"
		return info
	end
	info.Version = Runtime.ReadVersion(installed)
	if not info.Version then
		info.Status = "Unknown"
		info.Label = "Runtime (unknown version)"
	else
		local order = Runtime.Compare(info.Version, bundled)
		info.Status = if order < 0 then "Outdated" elseif order > 0 then "Newer" else "Current"
		info.Label = "Runtime " .. info.Version
	end
	return info
end

local function mirror(source, target, stats)
	if source:IsA("LuaSourceContainer") and target:IsA("LuaSourceContainer") and target.Source ~= source.Source then
		target.Source = source.Source
		stats.Updated += 1
	end
	local wanted = {}
	for _, child in source:GetChildren() do
		if child:IsA("LuaSourceContainer") or child:IsA("Folder") then
			wanted[child.Name] = true
			local existing = target:FindFirstChild(child.Name)
			if existing and existing.ClassName == child.ClassName then
				mirror(child, existing, stats)
			else
				if existing then
					existing:Destroy()
				end
				child:Clone().Parent = target
				stats.Created += 1
			end
		end
	end
	for _, child in target:GetChildren() do
		if (child:IsA("LuaSourceContainer") or child:IsA("Folder")) and not wanted[child.Name] then
			child:Destroy()
			stats.Removed += 1
		end
	end
end

function Runtime.Install(deps, path, remember)
	local source = deps and deps.RuntimeModule
	if typeof(source) ~= "Instance" or not source:IsA("ModuleScript") then
		return false, "the bundled runtime is not available"
	end
	local segments = split(path)
	if #segments < 2 then
		return false, "the path needs a service and a name, for example ReplicatedStorage.Timeline"
	end
	local stats = { Created = 0, Updated = 0, Removed = 0 }
	local id = ChangeHistoryService:TryBeginRecording("CutsceneEditorInstallRuntime", "Install cutscene runtime")
	local ok, err = pcall(function()
		local parent = service(segments[1])
		assert(parent, `service {segments[1]} was not found`)
		for index = 2, #segments - 1 do
			local child = parent:FindFirstChild(segments[index])
			if not child then
				child = Instance.new("Folder")
				child.Name = segments[index]
				child.Parent = parent
			end
			parent = child
		end
		local name = segments[#segments]
		local existing = parent:FindFirstChild(name)
		if existing and existing:IsA("ModuleScript") then
			mirror(source, existing, stats)
		else
			assert(existing == nil, `{path} exists and is not a ModuleScript`)
			local copy = source:Clone()
			copy.Name = name
			copy.Parent = parent
			stats.Created += 1
		end
		if remember == false then
			return
		end
		local root = ReplicatedStorage:FindFirstChild("Cutscenes")
		if not root then
			root = Instance.new("Folder")
			root.Name = "Cutscenes"
			root.Parent = ReplicatedStorage
		end
		if root:GetAttribute("RuntimePath") ~= path then
			root:SetAttribute("RuntimePath", path)
		end
	end)
	if id then
		ChangeHistoryService:FinishRecording(id, if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	end
	return ok, if ok then stats else err
end

return Runtime
