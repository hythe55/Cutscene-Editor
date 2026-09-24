local RunService = game:GetService("RunService")

if RunService:IsRunning() then
	return
end

local root = script.Parent

local ICONS = {
	Open = "rbxasset://studio_svg_textures/Shared/Ribbon/%s/Medium/RibbonVideoFrame.png",
	Reload = "rbxasset://studio_svg_textures/Lua/FileSync/%s/Large/Refresh.png",
}

local function themeName()
	local ok, name = pcall(function()
		return settings().Studio.Theme.Name
	end)
	return if ok and name == "Light" then "Light" else "Dark"
end

local function icon(name)
	return string.format(ICONS[name], themeName())
end

local toolbar = plugin:CreateToolbar("Cutscenes")
local openButton = toolbar:CreateButton("CutsceneEditorOpen", "Open the cutscene timeline editor", icon("Open"), "Cutscene Editor")
openButton.ClickableWhenViewportHidden = true
local reloadButton = toolbar:CreateButton("CutsceneEditorReload", "Remount the cutscene editor from fresh module copies", icon("Reload"), "Reload")
reloadButton.ClickableWhenViewportHidden = true

settings().Studio.ThemeChanged:Connect(function()
	openButton.Icon = icon("Open")
	reloadButton.Icon = icon("Reload")
end)

local widget = plugin:CreateDockWidgetPluginGuiAsync(
	"CutsceneEditorWidget",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 1150, 380, 760, 260)
)
widget.Name = "CutsceneEditor"
widget.Title = "Cutscene Editor"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local app = nil

local function freshCopies()
	local editor = root.Editor:Clone()
	local runtime = root.Runtime.Timeline:Clone()
	local Timeline = require(runtime)
	local deps = {
		Timeline = Timeline,
		Schema = Timeline.Schema,
		Sampler = Timeline.Sampler,
		Spline = require(runtime.Spline),
		FallbackDialogueBox = Timeline.FallbackDialogueBox,
		RuntimeModule = root.Runtime.Timeline,
	}
	return editor, deps
end

local function clear()
	for _, child in widget:GetChildren() do
		child:Destroy()
	end
end

local function showError(message)
	clear()
	local frame = Instance.new("Frame")
	frame.Name = "LoadError"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = settings().Studio.Theme:GetColor(Enum.StudioStyleGuideColor.MainBackground)
	frame.BorderSizePixel = 0
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingTop = UDim.new(0, 16)
	padding.Parent = frame
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 22)
	title.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = settings().Studio.Theme:GetColor(Enum.StudioStyleGuideColor.ErrorText)
	title.Text = "The cutscene editor failed to load"
	title.Parent = frame
	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(0, 30)
	body.Size = UDim2.new(1, 0, 1, -40)
	body.FontFace = Font.new("rbxasset://fonts/families/BuilderMono.json")
	body.TextSize = 13
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextColor3 = settings().Studio.Theme:GetColor(Enum.StudioStyleGuideColor.MainText)
	body.Text = tostring(message) .. "\n\nFix the error, then press Reload in the Cutscenes toolbar."
	body.Parent = frame
	frame.Parent = widget
end

local function unmount()
	if app then
		local current = app
		app = nil
		local ok, err = pcall(current.Destroy, current)
		if not ok then
			warn("CutsceneEditor: unmount failed: " .. tostring(err))
		end
	end
	clear()
end

local function syntaxErrors(module)
	local found = {}
	local all = module:GetDescendants()
	table.insert(all, 1, module)
	for _, descendant in all do
		if descendant:IsA("ModuleScript") then
			local ok, compiled, err = pcall(loadstring, descendant.Source, "=" .. descendant:GetFullName())
			if ok and not compiled and err then
				table.insert(found, err)
			end
		end
	end
	return found
end

local function mount()
	unmount()
	local reported = {}
	local connection = game:GetService("ScriptContext").Error:Connect(function(message, trace)
		table.insert(reported, tostring(message) .. "\n" .. tostring(trace))
	end)
	local editor
	local ok, result = xpcall(function()
		local deps
		editor, deps = freshCopies()
		return require(editor)(plugin, widget, deps)
	end, function(err)
		return debug.traceback(tostring(err), 2)
	end)
	if ok then
		connection:Disconnect()
		app = result
		return
	end
	task.wait()
	connection:Disconnect()
	local details = { tostring(result) }
	for _, message in reported do
		table.insert(details, message)
	end
	if editor then
		for _, err in syntaxErrors(editor) do
			table.insert(details, err)
		end
	end
	local message = table.concat(details, "\n\n")
	warn("CutsceneEditor: " .. message)
	showError(message)
end

openButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

reloadButton.Click:Connect(function()
	if widget.Enabled then
		mount()
	else
		widget.Enabled = true
	end
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	openButton:SetActive(widget.Enabled)
	if widget.Enabled then
		if not app then
			mount()
		end
	else
		unmount()
	end
end)

plugin.Unloading:Connect(unmount)

openButton:SetActive(widget.Enabled)
if widget.Enabled then
	mount()
end
