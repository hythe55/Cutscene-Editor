local RunService = game:GetService("RunService")

local UI = require(script.Parent.UI)
local Document = require(script.Parent.Document)
local Collect = require(script.Collect)
local Creator = require(script.Creator)
local Upload = require(script.Upload)

local Export = {}

Export.Collect = Collect
Export.Creator = Creator
Export.Upload = Upload
Export.Hooks = nil
Export.Running = false

local BETA = "Direct uploads from plugins need a Studio beta. Open File > Beta Features, turn on \"CreateAssetAsync Lua API\", restart Studio, then press Export again.\n\nYou can also upload these by hand now: Roblox's upload window opens for each one, and you paste the id it shows."

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

local function text(props)
	return UI.Create("TextLabel", {
		Name = props.Name,
		Parent = props.Parent,
		LayoutOrder = props.LayoutOrder or 0,
		Text = props.Text or "",
		TextSize = props.TextSize or 13,
		TextColor3 = props.TextColor3,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
end

function Export.Scope(items)
	local targets, never = Collect.Count(items)
	if #items == 0 then
		return "Every animation in scope matches its last export, so nothing needs uploading."
	end
	local current = 0
	for _, item in items do
		if not item.Stale then
			current += 1
		end
	end
	local changed = #items - never - current
	local parts = {}
	if never > 0 then
		table.insert(parts, `{never} never uploaded`)
	end
	if changed > 0 then
		table.insert(parts, `{changed} changed since the last upload`)
	end
	if current > 0 then
		table.insert(parts, `{current} uploaded again on request`)
	end
	if targets > #items then
		return `{plural(#items, "upload")} for {targets} animations ({table.concat(parts, ", ")}). Clips with identical keyframes share one upload:`
	end
	return `{plural(#items, "upload")} ({table.concat(parts, ", ")}):`
end

function Export.Describe(items, limit)
	local lines = {}
	for index, item in items do
		if index > (limit or 8) then
			table.insert(lines, `…and {#items - index + 1} more`)
			break
		end
		table.insert(lines, `• {item.Cutscene.Name}: {label(item)} ({string.format("%.1f", item.Length)} s){if item.Idle then " · idle loop" else ""}{if item.Smooth then " · baked" else ""}`)
	end
	return table.concat(lines, "\n")
end

local function queueContent(app, state)
	local content = UI.Create("Frame", {
		Name = "ExportQueue",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		List = { Padding = 8 },
	})
	local function lift()
		raise(content, 402)
	end
	local summary = text({ Name = "Summary", Parent = content, LayoutOrder = 1 })
	local function render()
		if not state.Fixed then
			state.Items = Collect.Candidates(app, state.All, state.Force)
		end
		local count = #state.Items
		summary.Text = if count == 0 then Export.Scope(state.Items) else `{Export.Scope(state.Items)}\n{Export.Describe(state.Items)}`
	end
	if not state.Fixed and #Collect.Folders(app, true) > 1 then
		UI.Toggle({
			Name = "AllCutscenes",
			Parent = content,
			LayoutOrder = 2,
			Label = "All cutscenes in this place",
			Value = state.All,
			OnChanged = function(value)
				state.All = value
				render()
				lift()
			end,
		})
	end
	render()
	state.Raise = lift
	local picker = Creator.Picker(state)
	picker.LayoutOrder = 3
	picker.Parent = content
	return raise(content, 402)
end

function Export.Confirm(app, ask, state)
	while true do
		local choice = ask({
			Title = if state.Fixed then "Export animation" else "Export animations",
			Text = "These upload straight to Roblox, and each clip gets its new animation id automatically.",
			Content = queueContent(app, state),
			Buttons = { "Cancel", "Upload" },
			Primary = "Upload",
			Width = 460,
		})
		if choice ~= "Upload" then
			return false
		end
		if #state.Items == 0 then
			return "Empty"
		end
		if state.Creator then
			return true
		end
		app:Notify("Enter the id of the group to upload to", "Warn")
	end
end

local function cutsceneOf(instance)
	local current = instance.Parent
	while current and current ~= game do
		if current:GetAttribute("Timeline") == true then
			return current
		end
		current = current.Parent
	end
	return nil
end

function Export.DocumentFor(app, run, folder)
	if app.Document and app.Document.Folder == folder then
		return app.Document
	end
	run.Documents = run.Documents or {}
	local document = run.Documents[folder]
	if not document then
		document = Document.new(folder, app.Deps)
		run.Documents[folder] = document
	end
	return document
end

function Export.Close(run)
	for _, document in run.Documents or {} do
		pcall(document.Destroy, document)
	end
	run.Documents = nil
end

function Export.Store(app, run, item, id)
	pausePreview(app)
	local byFolder, order = {}, {}
	for _, target in item.Targets do
		local folder = target.Parent and cutsceneOf(target)
		if folder then
			if not byFolder[folder] then
				byFolder[folder] = {}
				table.insert(order, folder)
			end
			table.insert(byFolder[folder], target)
		end
	end
	local stored = #order > 0
	for _, folder in order do
		local document = Export.DocumentFor(app, run, folder)
		local ok = document:Batch("Link " .. item.Name .. " animation", function(doc)
			for _, target in byFolder[folder] do
				doc:WriteAttribute(target, "AnimationId", "rbxassetid://" .. id)
				doc:WriteAttribute(target, "ExportedHash", item.Hash)
			end
			return true
		end)
		stored = stored and ok == true
	end
	return stored
end

function Export.Tidy(app, run, all)
	local tidied = 0
	for _, folder in Collect.Folders(app, all) do
		local document = Export.DocumentFor(app, run, folder)
		local ok, changed = pcall(document.TidySources, document)
		if ok and changed then
			tidied += 1
		elseif not ok then
			app:Notify(`Could not tidy {folder.Name}: {changed}`, "Warn")
		end
	end
	return tidied
end

local function record(app, run, summary, item, id)
	if Export.Store(app, run, item, id) then
		table.insert(summary.Uploaded, { Item = item, Id = id })
	else
		table.insert(summary.Failed, { Item = item, Id = id, Error = `uploaded as rbxassetid://{id}, but the id could not be saved. Paste it into Animation id and press Mark as exported` })
	end
end

local function progressModal(ask, creator, count)
	local frame = UI.Create("Frame", {
		Name = "ExportProgress",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		List = { Padding = 4 },
	})
	local line = text({ Name = "Line", Parent = frame, LayoutOrder = 1, Text = "Starting…" })
	raise(frame, 402)
	local handle = { Stopped = false }
	task.spawn(function()
		local choice = ask({
			Title = `Uploading {plural(count, "animation")}`,
			Text = `To {Creator.Name(creator)}. Each id is saved to its clips as soon as its upload finishes.`,
			Content = frame,
			Buttons = { "Stop" },
			Primary = "Stop",
			Width = 460,
		})
		if choice == "Stop" then
			handle.Stopped = true
		end
	end)
	function handle.Set(value)
		line.Text = value
	end
	function handle.Close()
		local scrim = frame:FindFirstAncestor("ModalScrim")
		if scrim then
			scrim:Destroy()
		end
	end
	return handle
end

local function byHand(app, ask, hooks, run, items, from, creator, summary)
	for index = from, #items do
		local item = items[index]
		local result = Upload.ByHand(app, ask, hooks, item, creator, `Upload {index}/{#items}: {label(item)}`)
		if result.Id then
			record(app, run, summary, item, result.Id)
		elseif result.Skipped then
			table.insert(summary.Skipped, { Item = item })
		elseif result.Error then
			table.insert(summary.Failed, { Item = item, Error = result.Error })
		else
			for rest = index, #items do
				table.insert(summary.NotReached, { Item = items[rest] })
			end
			return
		end
	end
end

function Export.UploadAll(app, ask, hooks, run, items, creator, summary)
	local progress = progressModal(ask, creator, #items)
	local stopped = function()
		return progress.Stopped
	end
	for index, item in items do
		if progress.Stopped then
			for rest = index, #items do
				table.insert(summary.NotReached, { Item = items[rest] })
			end
			break
		end
		progress.Set(`{index}/{#items}  {label(item)}`)
		local result = Upload.WithRetry(app, hooks, item, creator, stopped)
		if result.Id then
			record(app, run, summary, item, result.Id)
			if index < #items then
				task.wait(Upload.Gap)
			end
		elseif result.Unavailable then
			progress.Close()
			local choice = ask({
				Title = "Turn on direct uploads",
				Text = BETA,
				Buttons = { "Stop", "Upload by hand" },
				Primary = "Upload by hand",
				Width = 460,
			})
			if choice == "Upload by hand" then
				byHand(app, ask, hooks, run, items, index, creator, summary)
			else
				for rest = index, #items do
					table.insert(summary.NotReached, { Item = items[rest] })
				end
			end
			summary.Unavailable = true
			return
		elseif result.Denied then
			table.insert(summary.Failed, { Item = item, Error = `Roblox refused the upload to {Creator.Name(creator)}. Check that your role there can create assets` })
			for rest = index + 1, #items do
				table.insert(summary.NotReached, { Item = items[rest] })
			end
			break
		else
			table.insert(summary.Failed, { Item = item, Error = result.Error })
		end
	end
	progress.Close()
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
	add("Uploaded and linked", summary.Uploaded, function(entry)
		return `{label(entry.Item)} → rbxassetid://{entry.Id}`
	end)
	add("Skipped", summary.Skipped, function(entry)
		return label(entry.Item)
	end)
	add("Failed", summary.Failed, function(entry)
		return `{label(entry.Item)}: {entry.Error}`
	end)
	add("Not uploaded", summary.NotReached, function(entry)
		return label(entry.Item)
	end)
	if #summary.Partial > 0 then
		local names = {}
		for _, entry in summary.Partial do
			table.insert(names, `{entry.Cutscene}/{entry.Name}`)
		end
		table.insert(sections, `Still played from keyframes in game, because some of their clips or their Idle are not uploaded: {table.concat(names, ", ")}`)
	end
	return if #sections > 0 then table.concat(sections, "\n\n") else "Nothing was uploaded."
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
	local summary = { Uploaded = {}, Skipped = {}, Failed = {}, NotReached = {}, Partial = {} }
	local run = {}
	local ok, err = pcall(function()
		local state = { All = options.All == true, Force = options.Force == true, Items = {}, Choice = Creator.Load(app) }
		if options.Clips then
			state.Fixed = true
			for _, clip in options.Clips do
				local item = Collect.Item(app.Deps, clip, app.Document.Folder)
				if item and (state.Force or item.Stale) then
					table.insert(state.Items, item)
				end
			end
			state.Items = Collect.Group(state.Items)
		end
		local confirmed = Export.Confirm(app, ask, state)
		if confirmed == "Empty" then
			local tidied = Export.Tidy(app, run, state.All)
			app:Notify(if tidied > 0 then `Nothing needs uploading. Moved leftover keyframes into ServerStorage in {plural(tidied, "cutscene")}` else "Nothing needs uploading", "Info")
			return
		elseif not confirmed then
			return
		end
		Creator.Save(app, state.Choice)
		summary.Creator = state.Creator
		Export.UploadAll(app, ask, hooks, run, state.Items, state.Creator, summary)
		summary.Tidied = Export.Tidy(app, run, state.All)
		summary.Partial = Collect.Partial(app, state.All)
		ask({ Title = "Export finished", Text = Export.Summary(summary), Buttons = { "Done" }, Width = 460 })
	end)
	Collect.Cleanup()
	Export.Close(run)
	Export.Running = false
	if not ok then
		app:Notify("Export failed: " .. tostring(err), "Error")
		summary.Error = tostring(err)
	end
	return summary
end

return Export
