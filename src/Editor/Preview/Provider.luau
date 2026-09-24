local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")

local Provider = {}

Provider.ErrorWait = 2

function Provider.ResolvePath(path)
	if type(path) ~= "string" then
		return nil
	end
	path = string.gsub(path, "^game%.", "")
	if path == "" then
		return nil
	end
	local segments = string.split(path, ".")
	local ok, current = pcall(game.FindService, game, segments[1])
	if not ok or not current then
		current = game:FindFirstChild(segments[1])
	end
	for index = 2, #segments do
		if not current then
			return nil
		end
		current = current:FindFirstChild(segments[index])
	end
	return current
end

local function registers(folder)
	local path = folder and folder:GetAttribute("DialogueModule")
	return type(path) == "string" and path ~= ""
end

function Provider.Registry(folder)
	local parent = folder and folder.Parent
	if registers(parent) then
		return parent
	end
	local cutscenes = ReplicatedStorage:FindFirstChild("Cutscenes")
	return if registers(cutscenes) then cutscenes else nil
end

function Provider.Resolve(folder)
	local registry = Provider.Registry(folder)
	local info = { Kind = "Fallback", Label = "Built-in fallback" }
	if not registry then
		return info
	end
	local path = registry:GetAttribute("DialogueModule")
	local guiPath = registry:GetAttribute("DialogueGui")
	info.Registry = registry
	info.ModulePath = path
	info.GuiPath = if type(guiPath) == "string" and guiPath ~= "" then guiPath else nil
	local module = Provider.ResolvePath(path)
	if not module or not module:IsA("ModuleScript") then
		info.Kind = "Missing"
		info.Error = `{path} was not found`
		info.Label = "Missing: " .. path
		return info
	end
	info.Kind = "Game"
	info.Module = module
	info.Label = "Game: " .. path
	if info.GuiPath then
		local gui = Provider.ResolvePath(info.GuiPath)
		if gui and gui:IsA("LayerCollector") then
			info.Gui = gui
		else
			info.GuiError = `{info.GuiPath} was not found`
		end
	end
	return info
end

local function strip(root)
	for _, instance in root:GetDescendants() do
		for _, tag in CollectionService:GetTags(instance) do
			CollectionService:RemoveTag(instance, tag)
		end
	end
	for _, tag in CollectionService:GetTags(root) do
		CollectionService:RemoveTag(root, tag)
	end
end

local function cloneOf(instance)
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
	strip(copy)
	return copy
end

local function rename(message, copy, path)
	message = tostring(message)
	local name = copy.Name
	if string.sub(message, 1, #name) == name then
		local rest = string.sub(message, #name + 1)
		local first = string.sub(rest, 1, 1)
		if first == ":" or first == "." then
			return path .. rest
		end
	end
	return message
end

local function requireCopy(copy, path, onError)
	local connection
	connection = ScriptContext.Error:Connect(function(message, _, source)
		if source and (source == copy or source:IsDescendantOf(copy)) then
			connection:Disconnect()
			if onError then
				task.spawn(onError, rename(message, copy, path))
			end
		end
	end)
	local ok, result = pcall(require, copy)
	if ok then
		connection:Disconnect()
	else
		task.delay(Provider.ErrorWait, function()
			connection:Disconnect()
		end)
	end
	return ok, result
end

function Provider.Load(info, onError)
	if info.Kind ~= "Game" or not info.Module then
		return nil, info.Error
	end
	local copy = cloneOf(info.Module)
	if not copy then
		return nil, "could not clone " .. tostring(info.ModulePath)
	end
	local ok, result = requireCopy(copy, info.ModulePath or copy.Name, onError)
	if not ok then
		return nil, tostring(result), true
	end
	if type(result) ~= "table" or type(result.new) ~= "function" then
		return nil, `{info.ModulePath} does not return a table with .new`
	end
	return result
end

function Provider.Build(info, deps, guiParent, onError)
	local provider, err, pending = nil, nil, false
	if info.Kind == "Game" then
		provider, err, pending = Provider.Load(info, onError)
	end
	if provider then
		local gui = nil
		if info.Gui then
			gui = cloneOf(info.Gui)
			if gui then
				gui.Archivable = false
				gui.Parent = guiParent
			end
		end
		local ok, box = pcall(provider.new, { Gui = gui, GuiParent = guiParent, Preview = true })
		if ok and type(box) == "table" then
			return box, gui, provider, nil
		end
		err = tostring(box)
		if gui then
			gui:Destroy()
		end
	end
	local fallback = deps.FallbackDialogueBox
	local ok, box = pcall(fallback.new, { GuiParent = guiParent, Preview = true })
	if ok then
		return box, nil, fallback, err, pending
	end
	return nil, nil, nil, tostring(box), false
end

function Provider.SetRegistration(modulePath, guiPath)
	local id = ChangeHistoryService:TryBeginRecording("CutsceneEditorProvider", "Set dialogue provider")
	local ok, err = pcall(function()
		local root = ReplicatedStorage:FindFirstChild("Cutscenes")
		if not root then
			root = Instance.new("Folder")
			root.Name = "Cutscenes"
			root.Parent = ReplicatedStorage
		end
		root:SetAttribute("DialogueModule", if modulePath and modulePath ~= "" then modulePath else nil)
		root:SetAttribute("DialogueGui", if guiPath and guiPath ~= "" then guiPath else nil)
	end)
	if id then
		ChangeHistoryService:FinishRecording(id, if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	end
	return ok, err
end

function Provider.PathOf(instance)
	local parts = {}
	local current = instance
	while current and current ~= game do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return if current == game then table.concat(parts, ".") else nil
end

return Provider
