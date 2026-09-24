local Selection = game:GetService("Selection")

local UI = require(script.Parent.Parent.UI)
local Runtime = require(script.Parent.Runtime)
local Provider = require(script.Parent.Parent.Preview.Provider)

local Menus = {}

function Menus.WithPreviewStopped(app, fn)
	local preview = app.Preview
	local wasActive = preview.Active
	preview:Stop()
	local results = table.pack(pcall(fn))
	if wasActive then
		preview:Start(app.Time)
	end
	if not results[1] then
		return false, results[2]
	end
	return table.unpack(results, 2, results.n)
end

local function selectInstance(instance)
	if instance then
		Selection:Set({ instance })
	end
end

local function promptRegistration(app, info)
	task.spawn(function()
		local selected = Selection:Get()[1]
		local suggestion = info.ModulePath
		if selected and selected:IsA("ModuleScript") then
			suggestion = Provider.PathOf(selected) or suggestion
		end
		local choice, modulePath = app:Modal({
			Title = "Dialogue module",
			Text = "Path to the game's dialogue provider ModuleScript. It must return a table with .new(options) that builds a box with Open, Close, Say, Render and Destroy.",
			Input = { Placeholder = "ReplicatedStorage.Classes.DialogueBox", Value = suggestion or "" },
			Buttons = { "Cancel", "Next" },
		})
		if choice ~= "Next" or not modulePath or modulePath == "" then
			return
		end
		local module = Provider.ResolvePath(modulePath)
		if not module or not module:IsA("ModuleScript") then
			app:Notify(`{modulePath} is not a ModuleScript`, "Error")
			return
		end
		local guiChoice, guiPath = app:Modal({
			Title = "Dialogue GUI (optional)",
			Text = "Path to the ScreenGui template the provider draws into. Leave it empty if the module builds its own GUI.",
			Input = { Placeholder = "StarterGui.InGameDialogueUI", Value = info.GuiPath or "" },
			Buttons = { "Cancel", "Save" },
		})
		if guiChoice ~= "Save" then
			return
		end
		if guiPath and guiPath ~= "" then
			local gui = Provider.ResolvePath(guiPath)
			if not gui or not gui:IsA("LayerCollector") then
				app:Notify(`{guiPath} is not a ScreenGui`, "Error")
				return
			end
		end
		local ok, err = Menus.WithPreviewStopped(app, function()
			return Provider.SetRegistration(modulePath, guiPath)
		end)
		if ok then
			app:Notify("Dialogue provider set to " .. modulePath, "Success")
		else
			app:Notify("Could not set the provider: " .. tostring(err), "Error")
		end
		app.Signals.PreviewChanged:Fire(app.Preview:GetState())
	end)
end

function Menus.Provider(app, anchor)
	local info = app.Preview:GetProviderInfo()
	local items = {
		{ Header = true, Text = "DIALOGUE PROVIDER" },
		{ Text = info.Label, Info = true, TextColor = "Text", Icon = "Chat", IconColor = if info.Kind == "Game" then "Success" else "SubText" },
	}
	if info.Error then
		table.insert(items, { Text = info.Error, Info = true, TextColor = "Warning", Icon = "Warning", IconColor = "Warning" })
	end
	if info.GuiError then
		table.insert(items, { Text = info.GuiError, Info = true, TextColor = "Warning", Icon = "Warning", IconColor = "Warning" })
	elseif info.GuiPath then
		table.insert(items, { Text = "GUI: " .. info.GuiPath, Info = true })
	end
	table.insert(items, { Separator = true })
	table.insert(items, {
		Text = if info.Kind == "Fallback" then "Use a game module…" else "Change game module…",
		OnClick = function()
			promptRegistration(app, info)
		end,
	})
	table.insert(items, {
		Text = "Use the built-in fallback",
		Enabled = info.Kind ~= "Fallback",
		OnClick = function()
			local ok, err = Menus.WithPreviewStopped(app, function()
				return Provider.SetRegistration(nil, nil)
			end)
			if ok then
				app:Notify("Dialogue uses the built-in fallback", "Info")
			else
				app:Notify(tostring(err), "Error")
			end
			app.Signals.PreviewChanged:Fire(app.Preview:GetState())
		end,
	})
	table.insert(items, {
		Text = "Select module in Explorer",
		Enabled = info.Module ~= nil,
		OnClick = function()
			selectInstance(info.Module)
		end,
	})
	table.insert(items, { Separator = true })
	table.insert(items, { Header = true, Text = "PREVIEW STAND-INS" })
	for _, count in { 1, 2, 4, 6, 8 } do
		table.insert(items, {
			Text = count .. (if count == 1 then " player" else " players"),
			Checked = app.Preview.PlayerCount == count,
			OnClick = function()
				app.Preview:SetPlayerCount(count)
				app:Notify(`Preview uses {count} stand-in player{if count == 1 then "" else "s"}`, "Info")
			end,
		})
	end
	local chairTag = app.Document and app.Document.Folder:GetAttribute("ChairTag")
	table.insert(items, {
		Text = if type(chairTag) == "string" and chairTag ~= "" then "Chairs: tag " .. chairTag else "Chairs: none (set ChairTag)",
		Info = true,
	})
	return UI.Menu.Show(items, { Anchor = anchor, AlignRight = true, MinWidth = 240 })
end

local function install(app, path)
	local ok, result = Menus.WithPreviewStopped(app, function()
		return Runtime.Install(app.Deps, path, true)
	end)
	if ok then
		app:Notify(`Runtime {app.Deps.Timeline.Version} installed at {path} ({result.Created} created, {result.Updated} updated, {result.Removed} removed)`, "Success")
	else
		app:Notify("Runtime install failed: " .. tostring(result), "Error")
	end
	app.Signals.PreviewChanged:Fire(app.Preview:GetState())
end

local function confirmDowngrade(app, info)
	task.spawn(function()
		local choice = app:Modal({
			Title = "Downgrade the runtime?",
			Text = `This place has runtime {info.Version} at {info.Path}, which is newer than the plugin's {info.Bundled}. Installing replaces it with the older copy. Update the plugin instead if you can.`,
			Buttons = { "Cancel", "Downgrade" },
			Primary = "Cancel",
			Danger = "Downgrade",
			Width = 420,
		})
		if choice == "Downgrade" then
			install(app, info.Path)
		end
	end)
end

local function promptPath(app, info, thenInstall)
	task.spawn(function()
		local choice, path = app:Modal({
			Title = "Runtime location",
			Text = "Where the game keeps the Timeline runtime. The path is stored in the RuntimePath attribute of ReplicatedStorage.Cutscenes.",
			Input = { Placeholder = Runtime.DefaultPath, Value = info.Path },
			Buttons = { "Cancel", if thenInstall then "Install" else "Save" },
		})
		if (choice == "Install" or choice == "Save") and path and path ~= "" then
			if thenInstall then
				install(app, path)
			else
				local ok, err = pcall(function()
					app.Document:SetAttribute(app.Document.Folder.Parent, "RuntimePath", path)
				end)
				if not ok then
					app:Notify(tostring(err), "Error")
				end
				app.Signals.PreviewChanged:Fire(app.Preview:GetState())
			end
		end
	end)
end

function Menus.RuntimeItems(app)
	local info = Runtime.Detect(app.Deps)
	local items = {
		{ Header = true, Text = "TIMELINE RUNTIME" },
		{ Text = "Bundled with the plugin", Hint = info.Bundled, Info = true },
		{
			Text = if info.Status == "Missing" then "Not installed in this place" else "Installed in this place",
			Hint = info.Version or (if info.Status == "Missing" then "—" else "?"),
			Info = true,
			TextColor = if info.Status == "Current" or info.Status == "Newer" then "SubText" else "Warning",
		},
		{ Text = info.Path, Info = true, Icon = "Runtime", Tooltip = "RuntimePath: " .. info.Path },
		{ Separator = true },
	}
	if info.Status == "Missing" then
		table.insert(items, {
			Text = "Install runtime here…",
			OnClick = function()
				if info.Explicit then
					task.spawn(install, app, info.Path)
				else
					promptPath(app, info, true)
				end
			end,
		})
	elseif info.Status == "Newer" then
		table.insert(items, {
			Text = "Downgrade to " .. info.Bundled .. "…",
			Danger = true,
			OnClick = function()
				confirmDowngrade(app, info)
			end,
		})
	else
		table.insert(items, {
			Text = if info.Status == "Current" then "Reinstall runtime " .. info.Bundled else "Update runtime to " .. info.Bundled,
			OnClick = function()
				task.spawn(install, app, info.Path)
			end,
		})
	end
	table.insert(items, {
		Text = "Change location…",
		Enabled = app.Document ~= nil and app.Document.Folder.Parent ~= nil,
		OnClick = function()
			promptPath(app, info, false)
		end,
	})
	table.insert(items, {
		Text = "Select in Explorer",
		Enabled = info.Installed ~= nil,
		OnClick = function()
			selectInstance(info.Installed)
		end,
	})
	return items
end

function Menus.Runtime(app, anchor)
	return UI.Menu.Show(Menus.RuntimeItems(app), { Anchor = anchor, AlignRight = true, MinWidth = 260 })
end

return Menus
