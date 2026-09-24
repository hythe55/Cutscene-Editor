local Selection = game:GetService("Selection")

local UI = require(script.Parent.Parent.Parent.UI)
local Layout = require(script.Parent.Parent.Layout)
local Fields = require(script.Parent.Parent.Fields)
local Context = require(script.Parent.Parent.Context)
local Template = require(script.Parent.Template)
local Animation = require(script.Parent.Animation)
local Collect = require(script.Parent.Parent.Parent.Export.Collect)

local Scene = {}

local REGISTRY_FIELDS = {
	{ Name = "DialogueModule", Type = "string", Label = "Dialogue module", Placeholder = "Built-in fallback" },
	{ Name = "DialogueGui", Type = "string", Label = "Dialogue GUI", Placeholder = "none" },
	{ Name = "RuntimePath", Type = "string", Label = "Runtime path", Placeholder = "ReplicatedStorage.Timeline" },
	{ Name = "AssetLibrary", Type = "string", Label = "Asset library", Placeholder = Context.DefaultLibrary },
}

local CUTSCENE_FIELDS = {
	{ Name = "ChairTag", Type = "string", Label = "Chair tag", Placeholder = "none" },
}

local function visible(entry, values)
	for key, expected in entry.When or {} do
		if values[key] ~= expected then
			return false
		end
	end
	return true
end

function Scene.Track(inspector, track, order)
	local app = inspector.App
	local schema = app.Deps.Schema
	local _, body = Layout.Section(inspector, order, "Track", "Track")
	for index, entry in schema.Track do
		Fields.Attribute(inspector, body, index, track, entry)
	end
	local info = Layout.Text(body, 20, "", { Name = "TrackInfo" })
	inspector:Bind(function()
		local clips = app.Document:GetClips(track)
		if #clips == 0 then
			info.Text = "No clips on this lane yet."
			return
		end
		local first, last = math.huge, 0
		for _, clip in clips do
			local start = clip:GetAttribute("Start") or 0
			first = math.min(first, start)
			last = math.max(last, start + (clip:GetAttribute("Duration") or 0))
		end
		info.Text = `{#clips} clip{if #clips == 1 then "" else "s"} from {Layout.FormatTime(first)} to {Layout.FormatTime(last)}`
	end)
	return order + 10
end

local function talkJointPicker(inspector, body, order, actor)
	local app = inspector.App
	local dropdown = UI.Dropdown({
		Name = "AddTalkJoint",
		Parent = body,
		LayoutOrder = order,
		Placeholder = "Add a talk joint…",
		Searchable = true,
		Options = function()
			return Context.JointOptions(app, actor)
		end,
		OnChanged = function(joint, widget)
			widget:Set(nil)
			if type(joint) ~= "string" or joint == "" then
				return
			end
			local current = actor:GetAttribute("TalkJoints")
			local list = if type(current) == "string" and current ~= "" then string.split(current, ",") else {}
			for _, existing in list do
				if string.gsub(existing, "%s", "") == joint then
					return
				end
			end
			table.insert(list, joint)
			inspector:Commit(function()
				app.Document:SetAttribute(actor, "TalkJoints", table.concat(list, ","))
			end)
		end,
	})
	return dropdown
end

local function modelStatus(inspector, body, order, actor)
	local app = inspector.App
	local status = Layout.Status(body, order, "ModelStatus")
	local actions = Layout.Buttons(body, order + 1, "ModelActions")
	local model = nil
	Layout.Button(actions, 1, "Select model", function()
		if model and model.Parent then
			Selection:Set({ model })
		end
	end, { Name = "SelectModel", Style = "Ghost", Tooltip = "Select the model this actor resolves to in edit mode" })
	inspector:Bind(function()
		local source = actor:GetAttribute("Source") or "Tag"
		model = Context.ActorModel(app, actor)
		if model then
			local joints = Context.Joints(app, actor)
			status.Set(`Resolves to {model:GetFullName()} · {#joints} joints`, "Success")
		elseif source == "Role" or source == "Group" then
			status.Set("Players at run time; preview uses stand-ins with R15 joints", "Text")
		else
			status.Set(if source == "Tag" then `Nothing tagged "{tostring(actor:GetAttribute("Tag"))}" in the place` else "No Template model yet", "Warning")
		end
	end)
end

local function idleSection(inspector, actor, order)
	local app = inspector.App
	local idle = actor:FindFirstChild("Idle")
	if not idle or not idle:IsA("KeyframeSequence") then
		return
	end
	local _, body = Layout.Section(inspector, order, "ActorIdle", "Idle base layer")
	local info = Layout.Text(body, 0, "", { Name = "IdleInfo" })
	inspector:Bind(function()
		info.Text = `{#idle:GetKeyframes()} keyframes · {string.format("%.2f", Animation.Length(idle))} s · loops under every clip. Export uploads it together with the clips.`
	end)
	Animation.ExportControls(inspector, body, idle, 1, false, { Noun = "idle" })
	for _, entry in app.Deps.Schema.Idle do
		if entry.Name == "AnimationId" then
			Fields.Attribute(inspector, body, 2, idle, entry, { Placeholder = "rbxassetid://…" })
		end
	end
end

function Scene.Actor(inspector, actor, order)
	local app = inspector.App
	local schema = app.Deps.Schema
	local values = schema.Read(actor, "Actor")
	local _, body = Layout.Section(inspector, order, "Actor", "Actor")
	local index = 0
	for _, entry in schema.Actor do
		if visible(entry, values) then
			index += 1
			local options = {}
			if entry.Type == "joint" then
				options.JointActor = function()
					return actor
				end
			end
			Fields.Attribute(inspector, body, index, actor, entry, options)
			if entry.Name == "TalkJoints" then
				index += 1
				talkJointPicker(inspector, body, index, actor)
			end
		end
	end
	modelStatus(inspector, body, 100, actor)
	if values.Source == "Template" then
		Template.Build(inspector, actor, order + 1, false, { Actor = true, Category = "Props", Title = "Template" })
	end
	idleSection(inspector, actor, order + 2)
	return order + 10
end

local function exportTargets(document)
	local targets, seen = {}, {}
	for _, track in document:GetTracks() do
		if track:GetAttribute("Kind") == "Animation" then
			local actorId = track:GetAttribute("Actor")
			if type(actorId) == "string" and not seen[actorId] then
				seen[actorId] = true
				local idle = Collect.IdleOf(document.Folder, actorId)
				if idle then
					table.insert(targets, { Target = idle, Sequence = idle })
				end
			end
			for _, clip in document:GetClips(track) do
				local sequence = Animation.Sequence(clip)
				if sequence then
					table.insert(targets, { Target = clip, Sequence = sequence })
				end
			end
		end
	end
	return targets
end

local function exportSummary(hashes, targets)
	local exported, pending = 0, {}
	for _, entry in targets do
		local cached, hash = hashes:Peek(entry.Sequence)
		if not cached then
			table.insert(pending, entry.Sequence)
		elseif Animation.Classify(entry.Target, hash) == "Exported" then
			exported += 1
		end
	end
	return exported, pending
end

function Scene.Cutscene(inspector, folder, order)
	local app = inspector.App
	local document = app.Document
	local _, body = Layout.Section(inspector, order, "Cutscene", "Cutscene")
	local info = Layout.Text(body, 1, "", { Name = "CutsceneInfo", Color = "SubText" })
	local generation = 0
	inspector:Bind(function()
		generation += 1
		local mine = generation
		local lines = 0
		for _, track in document:GetTracks() do
			if track:GetAttribute("Kind") == "Dialogue" then
				lines += #document:GetClips(track)
			end
		end
		local hashes = inspector.Hashes
		local targets = exportTargets(document)
		local exported, pending = exportSummary(hashes, targets)
		local head = `{Layout.FormatTime(app:GetLength())} long · {lines} dialogue line{if lines == 1 then "" else "s"} · `
		local function show(checking)
			info.Text = head .. (if checking then `checking {#targets} animations…` else `{exported} of {#targets} animations exported`)
		end
		show(#pending > 0)
		if #pending == 0 then
			return
		end
		local function stale()
			return mine ~= generation or info.Parent == nil
		end
		task.defer(function()
			if hashes:Fill(pending, stale) and not stale() then
				exported = exportSummary(hashes, targets)
				show(false)
			end
		end)
	end)
	for index, entry in CUTSCENE_FIELDS do
		Fields.Attribute(inspector, body, index + 1, folder, entry, { Clear = true, Placeholder = entry.Placeholder, Tooltip = "Tagged chairs where the preview seats student stand-ins" })
	end
	local registry = Context.Registry()
	if registry then
		local _, place = Layout.Section(inspector, order + 1, "PlaceSettings", "Place settings")
		Layout.Text(place, 0, "Attributes on ReplicatedStorage.Cutscenes, shared by every cutscene in this place.")
		for index, entry in REGISTRY_FIELDS do
			Fields.Attribute(inspector, place, index, registry, entry, { Clear = true, Placeholder = entry.Placeholder })
		end
		local library = Layout.Status(place, 20, "LibraryStatus")
		inspector:Bind(function()
			local root, path = Context.Library()
			if not root then
				library.Set(`{path} was not found`, "Warning")
				return
			end
			local parts = {}
			for _, category in { "Sounds", "VFX", "Props" } do
				local items = Context.LibraryItems(category)
				table.insert(parts, `{#items} {category}`)
			end
			library.Set(`Library {path}: {table.concat(parts, " · ")}`, "Success")
		end)
	end
	return order + 10
end

return Scene
