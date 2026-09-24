local CoreGui = game:GetService("CoreGui")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

_G.CutsceneEditorDev = _G.CutsceneEditorDev or {}
local Dev = _G.CutsceneEditorDev

Dev.Usage = table.concat({
	"Paste this chunk into execute_luau once per session; it defines _G.CutsceneEditorDev and changes nothing else.",
	"Dev.Mount({ Parent = 'StarterGui' | 'CoreGui' | 'Hidden', Size = UDim2, Position = UDim2 }) mounts the editor from fresh clones of ServerStorage.CutsceneEditorDev and returns the app.",
	"StarterGui and CoreGui mounts are visible in the viewport: hold the playtest-queue lease while mounted. 'Hidden' mounts into a disabled ScreenGui in CoreGui.",
	"A preview (Play, Seek, SetTime, camera lock) puts clones in Workspace and may move the camera: hold the lease for those too.",
	"Dev.Unmount() destroys the app, its preview, the GUI, the module clones and the Plugin object.",
	"Dev.Load() only clones and requires the modules and returns root, editor, runtime, deps. The clones stay outside the DataModel: Script Sync writes scripts created under ServerStorage to disk.",
	"Run node build.js --dev-mirror in the plugin repo first.",
	"Dev.Overrides = { ['Editor/Preview/CameraLock'] = source, ['Runtime/Timeline/Tracks/Dialogue'] = source } replaces module sources in the clones, for when Script Sync lags behind the mirror. Folder modules drop '/init'.",
	"When Script Sync does not update the mirror: run node build.js, copy dist/CutsceneEditor.rbxmx to <running Studio version folder>/content/cutscene-dev/<new name>.rbxmx, then Dev.Mount({ Staged = '<new name>.rbxmx' }) or Dev.LoadStaged(name). Use a new file name per build and delete that folder when done.",
}, "\n")

local function destroy(instance)
	if instance then
		pcall(game.Destroy, instance)
	end
end

function Dev.Unmount()
	if Dev.App then
		local ok, err = pcall(Dev.App.Destroy, Dev.App)
		if not ok then
			warn("CutsceneEditorDev: app:Destroy failed: " .. tostring(err))
		end
	end
	destroy(Dev.Gui)
	destroy(Dev.Root)
	destroy(Dev.Plugin)
	Dev.App, Dev.Gui, Dev.Root, Dev.Plugin, Dev.Deps, Dev.Editor, Dev.Runtime = nil, nil, nil, nil, nil, nil, nil
	return "unmounted"
end

function Dev.Load()
	local source = ServerStorage:FindFirstChild("CutsceneEditorDev")
	assert(source, "ServerStorage.CutsceneEditorDev is missing; run node build.js --dev-mirror")
	local editorSource = source:FindFirstChild("Editor")
	local runtimeFolder = source:FindFirstChild("Runtime")
	local runtimeSource = runtimeFolder and runtimeFolder:FindFirstChild("Timeline")
	assert(editorSource and runtimeSource, "CutsceneEditorDev needs Editor and Runtime.Timeline")
	destroy(Dev.Root)
	local root = Instance.new("Folder")
	root.Name = "CutsceneEditorDevMount"
	root.Archivable = false
	local editor = editorSource:Clone()
	editor.Parent = root
	local runtime = runtimeSource:Clone()
	runtime.Parent = root
	for key, source in Dev.Overrides or {} do
		local segments = string.split(key, "/")
		local current = if segments[1] == "Editor" then editor elseif segments[1] == "Runtime" and segments[2] == "Timeline" then runtime else nil
		local first = if segments[1] == "Editor" then 2 else 3
		for index = first, #segments do
			if not current then
				break
			end
			local child = current:FindFirstChild(segments[index])
			if not child then
				child = Instance.new("ModuleScript")
				child.Name = segments[index]
				child.Parent = current
			end
			current = child
		end
		if current and current:IsA("ModuleScript") then
			current.Source = source
		end
	end
	return Dev.Use(root, editor, runtime)
end

function Dev.Use(root, editor, runtime)
	local Timeline = require(runtime)
	local deps = {
		Timeline = Timeline,
		Schema = Timeline.Schema,
		Sampler = Timeline.Sampler,
		Spline = require(runtime.Spline),
		FallbackDialogueBox = Timeline.FallbackDialogueBox,
		RuntimeModule = runtime,
	}
	Dev.Root, Dev.Editor, Dev.Runtime, Dev.Deps = root, editor, runtime, deps
	return root, editor, runtime, deps
end

function Dev.LoadStaged(file)
	destroy(Dev.Root)
	local root = game:GetObjects("rbxasset://cutscene-dev/" .. (file or "CutsceneEditor.rbxmx"))[1]
	assert(root and root:FindFirstChild("Editor") and root:FindFirstChild("Runtime"), "the staged file is not a CutsceneEditor build")
	root.Archivable = false
	return Dev.Use(root, root.Editor, root.Runtime.Timeline)
end

function Dev.Mount(options)
	options = options or {}
	Dev.Unmount()
	local _, editor, _, deps
	if options.Staged then
		_, editor, _, deps = Dev.LoadStaged(options.Staged)
	else
		_, editor, _, deps = Dev.Load()
	end
	local plugin = PluginManager():CreatePlugin()
	Dev.Plugin = plugin
	local gui = Instance.new("ScreenGui")
	gui.Name = "CutsceneEditorDevGui"
	gui.Archivable = false
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local frame = Instance.new("Frame")
	frame.Name = "Widget"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = options.AnchorPoint or Vector2.new(0.5, 1)
	frame.Position = options.Position or UDim2.new(0.5, 0, 1, -12)
	frame.Size = options.Size or UDim2.fromOffset(1150, 380)
	frame.Parent = gui
	local parent = options.Parent or "StarterGui"
	if parent == "StarterGui" then
		gui.Parent = StarterGui
	elseif parent == "CoreGui" then
		gui.Parent = CoreGui
	elseif parent == "Hidden" then
		gui.Enabled = false
		gui.Parent = CoreGui
	elseif typeof(parent) == "Instance" then
		gui.Parent = parent
	end
	Dev.Gui = gui
	Dev.Frame = frame
	local Editor = require(editor)
	local ok, app = pcall(Editor, plugin, frame, deps)
	if not ok then
		Dev.Unmount()
		error("CutsceneEditorDev: mount failed: " .. tostring(app), 0)
	end
	Dev.App = app
	return app
end

function Dev.Leftovers()
	local found = {}
	local function scan(root)
		for _, descendant in root:GetDescendants() do
			if descendant.Name == "CutsceneEditorPreview" or descendant.Name == "TimelinePostFX" or descendant.Name == "TimelineFocus" or descendant.Name == "CutsceneCamera" then
				table.insert(found, descendant:GetFullName())
			end
		end
	end
	scan(workspace)
	pcall(scan, CoreGui)
	return found
end

return Dev
