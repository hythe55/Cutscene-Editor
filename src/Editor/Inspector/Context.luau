local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Provider = require(script.Parent.Parent.Preview.Provider)

local Context = {}

Context.DefaultLibrary = "ServerStorage.CutsceneAssets"
Context.DefaultMoods = { "Normal", "Shout", "Whisper" }
Context.DefaultRoles = { "Student1", "Student2", "Student3", "Student4" }
Context.R15 = {
	"Head", "UpperTorso", "LowerTorso", "HumanoidRootPart",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
}

local SPEAKER_COLORS = {
	Dark = {
		Color3.fromRGB(240, 196, 90),
		Color3.fromRGB(110, 180, 250),
		Color3.fromRGB(120, 210, 140),
		Color3.fromRGB(240, 130, 120),
		Color3.fromRGB(190, 140, 240),
		Color3.fromRGB(90, 200, 200),
		Color3.fromRGB(240, 150, 200),
	},
	Light = {
		Color3.fromRGB(138, 90, 0),
		Color3.fromRGB(20, 94, 178),
		Color3.fromRGB(26, 118, 52),
		Color3.fromRGB(184, 46, 36),
		Color3.fromRGB(118, 56, 184),
		Color3.fromRGB(0, 112, 112),
		Color3.fromRGB(170, 40, 112),
	},
}

local providers = setmetatable({}, { __mode = "k" })

local function saved(instance)
	local current = instance
	while current and current ~= game do
		if not current.Archivable then
			return false
		end
		current = current.Parent
	end
	return current == game
end

function Context.Write(app, name, fn)
	local document = app.Document
	if not document then
		return nil
	end
	return document:Batch(name, fn)
end

function Context.Actor(app, id)
	local document = app.Document
	return document and document:GetActor(id)
end

function Context.ActorModel(app, id)
	local config = if typeof(id) == "Instance" then id else Context.Actor(app, id)
	if not config then
		return nil
	end
	local source = config:GetAttribute("Source")
	if source == "Template" then
		local template = config:FindFirstChild("Template")
		return if template and template:IsA("PVInstance") then template else nil
	elseif source == "Tag" or source == nil then
		local tag = config:GetAttribute("Tag")
		if type(tag) ~= "string" or tag == "" then
			return nil
		end
		local best
		for _, instance in CollectionService:GetTagged(tag) do
			if instance:IsA("PVInstance") and saved(instance) then
				if instance:IsDescendantOf(workspace) then
					return instance
				end
				best = best or instance
			end
		end
		return best
	end
	return nil
end

function Context.Joints(app, id)
	local config = if typeof(id) == "Instance" then id else Context.Actor(app, id)
	local model = config and Context.ActorModel(app, config)
	local list, seen = {}, {}
	local function add(name, kind)
		if not seen[name] then
			seen[name] = true
			table.insert(list, { Name = name, Kind = kind })
		end
	end
	if model then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("Bone") then
				add(descendant.Name, "Bone")
			elseif descendant:IsA("Motor6D") and descendant.Part1 then
				add(descendant.Part1.Name, "Joint")
			end
		end
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				add(descendant.Name, "Part")
			end
		end
	elseif config and (config:GetAttribute("Source") == "Role" or config:GetAttribute("Source") == "Group") then
		for _, name in Context.R15 do
			add(name, "R15")
		end
	end
	table.sort(list, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)
	return list, model
end

function Context.JointOptions(app, id)
	local options = { { Text = "(pivot)", Value = "" } }
	local joints = Context.Joints(app, id)
	for _, joint in joints do
		table.insert(options, { Text = joint.Name, Value = joint.Name, Hint = joint.Kind })
	end
	return options
end

function Context.Live(app)
	local preview = app.Preview
	local timeline = preview and preview.Active and preview.Timeline
	return timeline and timeline.Context
end

function Context.JointWorld(app, id, joint)
	local named = type(joint) == "string" and joint ~= ""
	local live = Context.Live(app)
	if live and type(id) == "string" and id ~= "" then
		local ok, cframe = pcall(live.GetJointCFrame, live, id, if named then joint else nil)
		if ok and typeof(cframe) == "CFrame" then
			return cframe, "Preview"
		end
	end
	local model = Context.ActorModel(app, id)
	if not model then
		return nil
	end
	if not named then
		return model:GetPivot(), "Place"
	end
	local found = if model.Name == joint then model else model:FindFirstChild(joint, true)
	if not found then
		return nil
	elseif found:IsA("Bone") then
		return found.TransformedWorldCFrame, "Place"
	elseif found:IsA("Attachment") then
		return found.WorldCFrame, "Place"
	elseif found:IsA("BasePart") then
		return found.CFrame, "Place"
	elseif found:IsA("PVInstance") then
		return found:GetPivot(), "Place"
	end
	return nil
end

function Context.Roles(app)
	local document = app.Document
	local roles = document and document:GetRoles() or {}
	if #roles == 0 then
		roles = table.clone(Context.DefaultRoles)
	end
	return roles
end

function Context.ActorOptions(app, entry)
	local document = app.Document
	local options = { { Text = "(none)", Value = "" } }
	local seen = {}
	if entry and entry.AllowSpeaker then
		table.insert(options, { Text = "Speaker", Value = "Speaker", Hint = "active speaker" })
	end
	for _, actor in if document then document:GetActors() else {} do
		seen[actor.Name] = true
		local display = actor:GetAttribute("DisplayName")
		table.insert(options, {
			Text = actor.Name,
			Value = actor.Name,
			Hint = if type(display) == "string" and display ~= "" and display ~= actor.Name then display else actor:GetAttribute("Source"),
		})
	end
	if entry and entry.AllowRoles then
		for _, role in Context.Roles(app) do
			if not seen[role] then
				table.insert(options, { Text = role, Value = role, Hint = "role" })
			end
		end
	end
	return options
end

function Context.SpeakerName(app, id)
	if type(id) ~= "string" or id == "" then
		return "(no speaker)"
	end
	local actor = Context.Actor(app, id)
	local display = actor and actor:GetAttribute("DisplayName")
	return if type(display) == "string" and display ~= "" then display else id
end

local function speakerIndex(id)
	if type(id) ~= "string" or id == "" then
		return 1
	end
	local sum = 0
	for index = 1, #id do
		sum = (sum * 31 + string.byte(id, index)) % 100003
	end
	return sum % #SPEAKER_COLORS.Dark + 1
end

function Context.SpeakerColor(id, theme)
	local dark = if theme then theme.IsDark ~= false else true
	return SPEAKER_COLORS[if dark then "Dark" else "Light"][speakerIndex(id)]
end

function Context.SpeakerToken(id)
	return function(theme)
		return Context.SpeakerColor(id, theme)
	end
end

function Context.Provider(app)
	local document = app.Document
	local info = Provider.Resolve(document and document.Folder)
	local key = info.Kind .. "|" .. tostring(info.ModulePath)
	local cached = providers[app]
	if cached and cached.Key == key then
		return cached.Value, cached.Info
	end
	local provider = nil
	if info.Kind == "Game" then
		local ok, loaded = pcall(Provider.Load, info)
		provider = if ok then loaded else nil
	end
	provider = provider or app.Deps.FallbackDialogueBox
	providers[app] = { Key = key, Value = provider, Info = info }
	return provider, info
end

function Context.ReadingTime(app, text, typeSpeed, mood)
	local provider = Context.Provider(app)
	local speed = if type(typeSpeed) == "number" and typeSpeed > 0 then typeSpeed else nil
	local reader = type(provider) == "table" and provider.ReadingTime
	if type(reader) == "function" then
		local ok, seconds = pcall(reader, text or "", speed, mood)
		if ok and type(seconds) == "number" then
			return seconds
		end
	end
	local fallback = app.Deps.FallbackDialogueBox
	return fallback.ReadingTime(text or "", speed)
end

function Context.Moods(app)
	local provider = Context.Provider(app)
	local moods = type(provider) == "table" and provider.Moods
	return if type(moods) == "table" and #moods > 0 then moods else Context.DefaultMoods
end

function Context.ProviderFields(app)
	local provider = Context.Provider(app)
	local fields = type(provider) == "table" and provider.Fields
	return if type(fields) == "table" then fields else {}
end

function Context.Registry()
	return ReplicatedStorage:FindFirstChild("Cutscenes")
end

function Context.Library()
	local registry = Context.Registry()
	local path = registry and registry:GetAttribute("AssetLibrary")
	path = if type(path) == "string" and path ~= "" then path else Context.DefaultLibrary
	return Provider.ResolvePath(path), path
end

local ACCEPT = {
	Sounds = function(instance)
		return instance:IsA("Sound")
	end,
	VFX = function(instance)
		return instance:IsA("Attachment") or instance:IsA("BasePart") or instance:IsA("Model")
	end,
	Props = function(instance)
		return instance:IsA("Model") or instance:IsA("BasePart")
	end,
}

function Context.LibraryItems(category)
	local root, path = Context.Library()
	local folder = root and root:FindFirstChild(category)
	local items = {}
	if not folder then
		return items, `{path}.{category}`
	end
	local accept = ACCEPT[category] or ACCEPT.Props
	local function scan(parent, group)
		for _, child in parent:GetChildren() do
			if accept(child) then
				table.insert(items, { Instance = child, Name = child.Name, Group = group })
			elseif child:IsA("Folder") then
				scan(child, if group then group .. "/" .. child.Name else child.Name)
			end
		end
	end
	scan(folder, nil)
	table.sort(items, function(a, b)
		local ga, gb = a.Group or "", b.Group or ""
		if ga ~= gb then
			return ga:lower() < gb:lower()
		end
		return a.Name:lower() < b.Name:lower()
	end)
	return items, `{path}.{category}`
end

function Context.StripTags(root)
	for _, tag in CollectionService:GetTags(root) do
		CollectionService:RemoveTag(root, tag)
	end
	for _, descendant in root:GetDescendants() do
		for _, tag in CollectionService:GetTags(descendant) do
			CollectionService:RemoveTag(descendant, tag)
		end
	end
	return root
end

function Context.Copy(instance)
	local archivable = instance.Archivable
	if not archivable then
		instance.Archivable = true
	end
	local ok, copy = pcall(instance.Clone, instance)
	if not archivable then
		instance.Archivable = false
	end
	if not ok or not copy then
		return nil
	end
	copy.Archivable = true
	return Context.StripTags(copy)
end

return Context
