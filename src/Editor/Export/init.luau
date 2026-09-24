local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")

local UI = require(script.Parent.UI)
local Context = require(script.Parent.Inspector.Context)
local Collect = require(script.Collect)

local Export = {}

Export.Collect = Collect
Export.Hooks = nil
Export.Running = false

local REMINDER = "Upload to the group that owns this experience: pick that group as the Creator in Roblox's upload window. Animations owned by your own account will not play in a group game."

local function raise(frame, z)
	for _, descendant in frame:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = z + 1
		end
	end
	frame.ZIndex = z
	return frame
end

local function plural(count, word)
	return `{count} {word}{if count == 1 then "" else "s"}`
end

local function label(item)
	local extra = if item.Targets and #item.Targets > 1 then ` (+{#item.Targets - 1} identical)` else ""
	return `{item.Actor} / {item.Name}{extra}`
end

local function pausePreview(app)
	local preview = app.Preview
	if preview and preview.Playing then
		preview:Pause()
	end
end

function Export.Scope(items)
	local targets, never = Collect.Count(items)
	if #items == 0 then
		return "Every animation in scope matches its last export."
	end
	local changed = #items - never
	local parts = {}
	if never > 0 then
		table.insert(parts, `{never} never exported`)
	end
	if changed > 0 then
		table.insert(parts, `{changed} changed since the last export`)
	end
	if targets > #items then
		return `{plural(#items, "upload")} needed for {targets} animations ({table.concat(parts, ", ")}). Clips with identical keyframes share one upload:`
	end
	return `{plural(#items, "upload")} needed ({table.concat(parts, ", ")}):`
end

function Export.Describe(items, limit)
	local lines = {}
	for index, item in items do
		if index > (limit or 6) then
			table.insert(lines, `…and {#items - index + 1} more`)
			break
		end
		table.insert(lines, `• {item.Cutscene.Name}: {label(item)} ({string.format("%.1f", item.Length)} s){if item.Smooth then " · baked" else ""}{if item.Never then "" else " · changed"}`)
	end
	return table.concat(lines, "\n")
end

local function introContent(app, state)
	local content = UI.Create("Frame", {
		Name = "ExportScope",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		List = { Padding = 6 },
	})
	local summary = UI.Create("TextLabel", {
		Name = "Summary",
		Parent = content,
		LayoutOrder = 1,
		Text = "",
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	local function render()
		state.Items = Collect.Candidates(app, state.All, state.Force)
		local count = #state.Items
		summary.Text = if count == 0 then Export.Scope(state.Items) else `{Export.Scope(state.Items)}\n{Export.Describe(state.Items)}`
	end
	if #Collect.Folders(app, true) > 1 then
		UI.Toggle({
			Name = "AllCutscenes",
			Parent = content,
			LayoutOrder = 2,
			Label = "All cutscenes in this place",
			Value = state.All,
			OnChanged = function(value)
				state.All = value
				render()
				raise(content, 402)
			end,
		})
	end
	render()
	return raise(content, 402)
end

local function pickId(app, ask, hooks, item)
	while true do
		local choice = ask({
			Title = "Pick the animation you just uploaded",
			Text = `Link {label(item)} to its new asset. Pick it from your inventory, or paste the id from the upload window.`,
			Buttons = { "Skip", "Paste id", "Pick from inventory" },
			Primary = "Pick from inventory",
		})
		if choice == "Pick from inventory" then
			local picker = hooks and hooks.Pick or function(plugin)
				return plugin:PromptForExistingAssetIdAsync("Animation")
			end
			local ok, result = pcall(picker, app.Plugin)
			local id = if ok then Collect.ParseId(result) else nil
			if id then
				return id
			end
			app:Notify(if ok then "No animation was picked" else "The asset picker failed: " .. tostring(result), "Warn")
		elseif choice == "Paste id" then
			local answer, text = ask({
				Title = "Paste the animation id",
				Text = "An id such as 1234567890, or rbxassetid://1234567890.",
				Input = { Placeholder = "rbxassetid://…" },
				Buttons = { "Back", "Save" },
				Primary = "Save",
			})
			local id = if answer == "Save" then Collect.ParseId(text) else nil
			if id then
				return id
			elseif answer == "Save" then
				app:Notify("That is not an asset id", "Warn")
			end
		else
			return nil
		end
	end
end

local function upload(app, ask, hooks, item, summary)
	local previous = Selection:Get()
	local ok, err = pcall(function()
		local temp = Collect.Prepare(app.Deps, item)
		Selection:Set({ temp })
		local save = hooks and hooks.Save or function(plugin)
			return plugin:SaveSelectedToRoblox()
		end
		save(app.Plugin, temp)
	end)
	pcall(Selection.Set, Selection, previous)
	if not ok then
		Collect.Cleanup()
		table.insert(summary.Failed, { Item = item, Error = tostring(err) })
		app:Notify(`Upload of {label(item)} failed: {err}`, "Error")
		return
	end
	local id = pickId(app, ask, hooks, item)
	Collect.Cleanup()
	if not id then
		table.insert(summary.Unlinked, { Item = item })
		return
	end
	if Export.Store(app, item, id) then
		table.insert(summary.Uploaded, { Item = item, Id = id })
	else
		table.insert(summary.Failed, { Item = item, Id = id, Error = `uploaded as rbxassetid://{id}, but the id could not be stored. Paste it into Animation id and press Mark as exported` })
	end
end

function Export.Store(app, item, id)
	pausePreview(app)
	local stored = Context.Write(app, "Link " .. item.Name .. " animation", function(document)
		for _, target in item.Targets do
			if target.Parent then
				document:WriteAttribute(target, "AnimationId", "rbxassetid://" .. id)
				document:WriteAttribute(target, "ExportedHash", item.Hash)
			end
		end
		return true
	end)
	return stored == true
end

function Export.Summary(summary)
	local sections = {}
	local function add(title, list, describe)
		if #list > 0 then
			local lines = { `{title} ({#list})` }
			for index, entry in list do
				if index > 8 then
					table.insert(lines, `…and {#list - 8} more`)
					break
				end
				table.insert(lines, "• " .. describe(entry))
			end
			table.insert(sections, table.concat(lines, "\n"))
		end
	end
	add("Uploaded", summary.Uploaded, function(entry)
		return `{label(entry.Item)} → rbxassetid://{entry.Id}`
	end)
	add("Uploaded but not linked", summary.Unlinked, function(entry)
		return label(entry.Item)
	end)
	add("Skipped", summary.Skipped, function(entry)
		return label(entry.Item)
	end)
	add("Failed", summary.Failed, function(entry)
		return `{label(entry.Item)}: {entry.Error}`
	end)
	add("Not reached", summary.NotReached, function(entry)
		return label(entry.Item)
	end)
	if #summary.Partial > 0 then
		local names = {}
		for _, entry in summary.Partial do
			table.insert(names, `{entry.Cutscene}/{entry.Name}`)
		end
		table.insert(sections, `Still played from keyframes, because some of their clips or their Idle are not exported: {table.concat(names, ", ")}`)
	end
	return if #sections > 0 then table.concat(sections, "\n\n") else "Nothing was exported."
end

function Export.Run(app, options)
	options = options or {}
	local hooks = options.Hooks or Export.Hooks
	local ask = hooks and hooks.Ask or function(props)
		return app:Modal(props)
	end
	if Export.Running then
		app:Notify("An export is already running", "Warn")
		return nil
	end
	if RunService:IsRunning() then
		app:Notify("Export works in edit mode only", "Warn")
		return nil
	end
	if not app.Document then
		app:Notify("Open a cutscene first", "Warn")
		return nil
	end
	Export.Running = true
	pausePreview(app)
	local summary = { Uploaded = {}, Unlinked = {}, Skipped = {}, Failed = {}, NotReached = {}, Partial = {} }
	local ok, err = pcall(function()
		local state = { All = options.All == true, Force = options.Force == true, Items = {} }
		if options.Clips then
			for _, clip in options.Clips do
				local item = Collect.Item(app.Deps, clip, app.Document.Folder)
				if item and (state.Force or item.Stale) then
					table.insert(state.Items, item)
				end
			end
			state.Items = Collect.Group(state.Items)
			local choice = ask({
				Title = "Export animation",
				Text = REMINDER,
				Content = raise(UI.Create("TextLabel", {
					Text = if #state.Items > 0 then Export.Describe(state.Items) else "This animation has no keyframes to export.",
					TextSize = 13,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
				}), 402),
				Buttons = { "Cancel", "Start" },
				Primary = "Start",
			})
			if choice ~= "Start" then
				return
			end
		else
			local choice = ask({
				Title = "Export animations",
				Text = REMINDER,
				Content = introContent(app, state),
				Buttons = { "Cancel", "Start" },
				Primary = "Start",
				Width = 440,
			})
			if choice ~= "Start" then
				return
			end
		end
		local items = state.Items
		if #items == 0 then
			app:Notify("Every animation in scope is already exported", "Info")
		end
		for index, item in items do
			local choice = ask({
				Title = `Export {index}/{#items}: {label(item)} ({string.format("%.1f", item.Length)} s)`,
				Text = `{item.Cutscene.Name} · {if item.Idle then "The actor's Idle loop, needed before any of its clips can use uploaded animations. " else ""}{if item.Smooth then "Smooth keys: uploads a 30 fps bake so it plays like the preview." else "Uploads the keyframes as they are."}{if #item.Targets > 1 then ` The id is stored on all {#item.Targets} clips with these keyframes.` else ""} Upload opens Roblox's upload window.`,
				Buttons = { "Stop", "Skip", "Upload" },
				Primary = "Upload",
			})
			if choice == "Upload" then
				upload(app, ask, hooks, item, summary)
			elseif choice == "Skip" then
				table.insert(summary.Skipped, { Item = item })
			else
				for rest = index, #items do
					table.insert(summary.NotReached, { Item = items[rest] })
				end
				break
			end
		end
		summary.Partial = Collect.Partial(app, state.All)
		if #items > 0 then
			ask({ Title = "Export finished", Text = Export.Summary(summary), Buttons = { "Done" }, Width = 440 })
		end
	end)
	Collect.Cleanup()
	Export.Running = false
	if not ok then
		app:Notify("Export failed: " .. tostring(err), "Error")
		summary.Error = tostring(err)
	end
	return summary
end

return Export
