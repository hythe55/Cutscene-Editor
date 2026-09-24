local UI = require(script.Parent.Parent.UI)

local Editor = script.Parent.Parent

local Features = {}

Features.List = {
	{ Name = "Toolbar", Region = "Toolbar", Label = "Toolbar" },
	{ Name = "LaneHeaders", Region = "Headers", Label = "Lane headers" },
	{ Name = "TimelineView", Region = "Timeline", Label = "Timeline" },
	{ Name = "Inspector", Region = "Inspector", Label = "Inspector" },
	{ Name = "ScriptPanel", Region = "Script", Label = "Script panel" },
	{ Name = "KeyTool", Path = { "Tools", "KeyTool" }, Region = "Keys", Label = "Key tool" },
	{ Name = "PoseTool", Path = { "Tools", "PoseTool" }, Region = "Pose", Label = "Pose tool" },
}

function Features.Find(path)
	local current = Editor
	for _, name in path do
		current = current and current:FindFirstChild(name)
	end
	return if current and current:IsA("ModuleScript") then current else nil
end

local function regionOf(app, name)
	local shell = app.Shell
	return shell.Pages[name] or shell[name]
end

function Features.Placeholder(app, frame, entry, message)
	local holder = UI.Create("Frame", {
		Name = entry.Name .. "Placeholder",
		Parent = frame,
		Size = UDim2.fromScale(1, 1),
		Padding = 16,
		ClipsDescendants = true,
	})
	local column = UI.Create("Frame", {
		Parent = holder,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		List = { Padding = 4, HorizontalAlignment = Enum.HorizontalAlignment.Center },
	})
	UI.Create("TextLabel", {
		Parent = column,
		LayoutOrder = 1,
		Text = entry.Label .. (if message then " failed to load" else " is not installed"),
		Font = "Medium",
		TextSize = 13,
		TextColor3 = if message then "Error" else "Dim",
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	UI.Create("TextLabel", {
		Parent = column,
		LayoutOrder = 2,
		Text = message or ("Editor." .. table.concat(entry.Path or { entry.Name }, ".")),
		TextSize = 12,
		TextColor3 = "Faint",
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	return {
		Placeholder = true,
		Instance = holder,
		Destroy = function()
			holder:Destroy()
		end,
	}
end

function Features.Mount(app, entry)
	local frame = regionOf(app, entry.Region)
	local module = Features.Find(entry.Path or { entry.Name })
	local feature, message = nil, nil
	if module then
		local ok, class = pcall(require, module)
		if ok and type(class) == "table" and type(class.new) == "function" then
			local built, result = pcall(class.new, app, frame)
			if built and result then
				feature = result
			else
				message = tostring(result)
			end
		else
			message = if ok then "module has no .new" else tostring(class)
		end
	end
	if message then
		warn(`CutsceneEditor: {entry.Name} failed: {message}`)
		UI.Clear(frame, { UIPadding = true, UIListLayout = true })
	end
	feature = feature or Features.Placeholder(app, frame, entry, message)
	app.Features[entry.Name] = feature
	return feature
end

function Features.MountAll(app)
	app.Tools = {}
	for _, entry in Features.List do
		local feature = Features.Mount(app, entry)
		if entry.Path and entry.Path[1] == "Tools" then
			app.Tools[entry.Name] = feature
		end
	end
end

function Features.Remount(app, name)
	for _, entry in Features.List do
		if entry.Name == name then
			local old = app.Features[name]
			if old then
				pcall(old.Destroy, old)
			end
			return Features.Mount(app, entry)
		end
	end
	return nil
end

function Features.DestroyAll(app)
	for index = #Features.List, 1, -1 do
		local entry = Features.List[index]
		local feature = app.Features[entry.Name]
		if feature and feature.Destroy then
			local ok, err = pcall(feature.Destroy, feature)
			if not ok then
				warn(`CutsceneEditor: {entry.Name}:Destroy failed: {err}`)
			end
		end
		app.Features[entry.Name] = nil
	end
end

return Features
