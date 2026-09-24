local SourceLookup = require(script.Parent.Parent.Parent.Sources)
local UI = require(script.Parent.Parent.Parent.UI)
local Layout = require(script.Parent.Parent.Layout)
local Fields = require(script.Parent.Parent.Fields)

local Animation = {}

local STATUS = {
	Exported = { Text = "Exported ✓", Color = "Success" },
	Changed = { Text = "Changed since export", Color = "Warning" },
	Never = { Text = "Never exported", Color = "Dim" },
	Missing = { Text = "No Keyframes sequence", Color = "Error" },
}

function Animation.Sequence(target)
	return SourceLookup.Sequence(target)
end

function Animation.Hash(deps, sequence, hashes)
	if hashes then
		return hashes:Get(sequence)
	end
	local ok, hash = pcall(deps.Timeline.ComputeHash, sequence)
	return if ok then hash else nil
end

function Animation.Classify(target, hash)
	local exported = target:GetAttribute("ExportedHash")
	local id = target:GetAttribute("AnimationId")
	if type(exported) ~= "string" or exported == "" or type(id) ~= "string" or id == "" then
		return "Never"
	end
	return if hash == exported then "Exported" else "Changed"
end

function Animation.Status(deps, target, hashes)
	local sequence = Animation.Sequence(target)
	if not sequence then
		return "Missing", nil
	end
	local hash = Animation.Hash(deps, sequence, hashes)
	return Animation.Classify(target, hash), hash
end

function Animation.Length(sequence)
	local length = 0
	for _, keyframe in if sequence then sequence:GetKeyframes() else {} do
		length = math.max(length, keyframe.Time)
	end
	return length
end

function Animation.ToCutscene(clip, keyTime, length)
	local start = clip:GetAttribute("Start") or 0
	local duration = clip:GetAttribute("Duration") or 0
	local speed = math.max(clip:GetAttribute("Speed") or 1, 1e-3)
	local offset = clip:GetAttribute("ClipOffset") or 0
	local t = start + (keyTime - offset) / speed
	if clip:GetAttribute("Loop") == true and length > 0 then
		while t < start - 1e-4 do
			t += length / speed
		end
	end
	return t, t >= start - 1e-4 and t <= start + duration + 1e-4
end

function Animation.ToClip(clip, t, length)
	local start = clip:GetAttribute("Start") or 0
	local local_ = (clip:GetAttribute("ClipOffset") or 0) + (t - start) * (clip:GetAttribute("Speed") or 1)
	if clip:GetAttribute("Loop") == true and length > 0 then
		local_ = local_ % length
	end
	return local_
end

local function poseCount(keyframe)
	local count = 0
	for _, descendant in keyframe:GetDescendants() do
		if descendant:IsA("Pose") and descendant.Weight > 0 then
			count += 1
		end
	end
	return count
end

local function filled(value)
	return type(value) == "string" and value ~= ""
end

function Animation.ExportControls(inspector, body, target, order, locked, options)
	options = options or {}
	local app = inspector.App
	local status = Layout.Status(body, order, "ExportStatus")
	local actions = Layout.Buttons(body, order + 2, "ExportActions")
	local noun = options.Noun or "clip"
	local exportButton = Layout.Button(actions, 1, "Export this " .. noun, function()
		local module = script.Parent.Parent.Parent:FindFirstChild("Export")
		if not module then
			app:Notify("Export is not installed in this build", "Warn")
			return
		end
		task.spawn(function()
			require(module).Run(app, { Clips = { target }, Force = true })
		end)
	end, { Name = "ExportClip", Enabled = not locked and Animation.Sequence(target) ~= nil, Tooltip = `Upload just this {noun} to Roblox` })
	local mark = Layout.Button(actions, 2, "Mark as exported", function()
		local sequence = Animation.Sequence(target)
		if not sequence or not filled(target:GetAttribute("AnimationId")) then
			app:Notify("Paste the uploaded animation id into Animation id first", "Warn")
			return
		end
		local hash = Animation.Hash(app.Deps, sequence)
		if not hash then
			app:Notify("Could not hash these keyframes", "Error")
			return
		end
		inspector:Commit(function()
			app.Document:SetAttribute(target, "ExportedHash", hash)
		end)
	end, { Name = "MarkExported", Style = "Ghost", Enabled = false, Tooltip = "Use when Animation id already holds exactly these keyframes, for example an id pasted by hand" })
	Layout.Button(actions, 3, "Clear", function()
		inspector:Commit(function()
			app.Document:SetAttributes(target, { AnimationId = "", ExportedHash = "" })
		end)
	end, { Name = "ClearExport", Style = "Ghost", Enabled = not locked, Tooltip = `Forget the uploaded id; the {noun} plays directly from its keyframes` })
	inspector:Bind(function()
		local state = Animation.Status(app.Deps, target, inspector.Hashes)
		local info = STATUS[state]
		status.Set(info.Text, info.Color)
		mark:SetEnabled(not locked and state ~= "Exported" and state ~= "Missing" and filled(target:GetAttribute("AnimationId")))
	end)
	return status, exportButton
end

local function exportSection(inspector, clip, order, locked)
	local app = inspector.App
	local schema = app.Deps.Schema
	local _, body = Layout.Section(inspector, order, "AnimationExport", "Export")
	local idEntry
	for _, entry in schema.Kinds.Animation.Fields do
		if entry.Name == "AnimationId" then
			idEntry = entry
		end
	end
	Animation.ExportControls(inspector, body, clip, 1, locked)
	Fields.Attribute(inspector, body, 2, clip, idEntry or { Name = "AnimationId", Type = "string", Label = "Animation id" }, { ReadOnly = locked, Placeholder = "rbxassetid://…" })
	local actor = clip.Parent:GetAttribute("Actor")
	Layout.Text(body, 4, `An uploaded id is used only when every Animation clip of {if actor and actor ~= "" then actor else "this actor"}, and its Idle, are exported and unchanged.`)
end

local function keyframeRow(inspector, list, index, clip, keyframe, length)
	local app = inspector.App
	local button = UI.Create("TextButton", {
		Name = "Keyframe" .. index,
		Parent = list,
		LayoutOrder = index,
		Text = "",
		BackgroundColor3 = "Hover",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 22),
		Corner = 3,
	})
	local left = UI.Create("TextLabel", {
		Parent = button,
		Text = "",
		Font = "Mono",
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(0.55, -6, 1, 0),
	})
	local right = UI.Create("TextLabel", {
		Parent = button,
		Text = "",
		TextSize = 12,
		TextColor3 = "Dim",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 0),
		Size = UDim2.new(0.45, -6, 1, 0),
	})
	local entry = { Button = button, Keyframe = keyframe, Active = false }
	function entry.Render()
		local t, inside = Animation.ToCutscene(clip, keyframe.Time, length)
		left.Text = `{string.format("%.2f", keyframe.Time)}  →  {Layout.FormatTime(t)}`
		UI.Set(left, "TextColor3", if inside then "Text" else "Faint")
		right.Text = `{if keyframe.Name ~= "Keyframe" then keyframe.Name .. " · " else ""}{poseCount(keyframe)} poses`
		button.BackgroundTransparency = if entry.Active then 0 else 1
		UI.Set(button, "BackgroundColor3", if entry.Active then "AccentSoft" else "Hover")
	end
	button.MouseEnter:Connect(function()
		button.BackgroundTransparency = 0
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundTransparency = if entry.Active then 0 else 1
	end)
	button.Activated:Connect(function()
		local t = Animation.ToCutscene(clip, keyframe.Time, length)
		app:SetTime(math.clamp(t, clip:GetAttribute("Start") or 0, (clip:GetAttribute("Start") or 0) + (clip:GetAttribute("Duration") or 0)))
	end)
	entry.Render()
	return entry
end

local function keyframeSection(inspector, clip, order, locked)
	local app = inspector.App
	local document = app.Document
	local sequence = Animation.Sequence(clip)
	local _, body = Layout.Section(inspector, order, "AnimationKeyframes", "Keyframes")
	if not sequence then
		Layout.Text(body, 1, "This clip has no Keyframes sequence.", { Color = "Warning" })
		return
	end
	local info = Layout.Text(body, 1, "", { Name = "SourceInfo" })
	Fields.Add(inspector, {
		Entry = { Name = "Interpolation", Type = "bool", Label = "Smooth keys" },
		Parent = body,
		Order = 2,
		Target = sequence,
		ReadOnly = locked,
		Tooltip = "Interpolation = \"Smooth\" on the KeyframeSequence: velocity-continuous pass keys. Changing it needs a new export.",
		Read = function()
			return sequence:GetAttribute("Interpolation") == "Smooth"
		end,
		Commit = function(value)
			document:SetAttribute(sequence, "Interpolation", if value then "Smooth" else nil)
		end,
	})
	local actions = Layout.Buttons(body, 3, "KeyframeActions")
	Layout.Button(actions, 1, "Fit duration to source", function()
		local length = Animation.Length(sequence)
		local speed = math.max(clip:GetAttribute("Speed") or 1, 1e-3)
		local offset = clip:GetAttribute("ClipOffset") or 0
		if length <= offset then
			app:Notify("The clip offset is past the end of the animation", "Warn")
			return
		end
		inspector:Commit(function()
			document:SetClipTiming(clip, nil, (length - offset) / speed, true)
		end)
	end, { Name = "FitSource", Style = "Ghost", Enabled = not locked, Tooltip = "Duration = source length after the clip offset, at this speed" })
	local list = UI.Create("Frame", {
		Name = "KeyframeList",
		Parent = body,
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		List = { Padding = 0 },
	})
	local keyframes = document:GetKeyframes(clip)
	local length = Animation.Length(sequence)
	local rows = {}
	for index, keyframe in keyframes do
		rows[index] = keyframeRow(inspector, list, index, clip, keyframe, length)
	end
	local function highlight()
		local localTime = Animation.ToClip(clip, app.Time, length)
		local active = nil
		for index, keyframe in keyframes do
			if keyframe.Parent and keyframe.Time <= localTime + 1e-4 then
				active = index
			end
		end
		for index, row in rows do
			local on = index == active
			if on ~= row.Active then
				row.Active = on
				row.Render()
			end
		end
	end
	inspector:Connect(app.Signals.TimeChanged, highlight)
	inspector:Bind(function()
		length = Animation.Length(sequence)
		info.Text = `{#keyframes} keyframes · {string.format("%.2f", length)} s source{if clip:GetAttribute("Loop") == true then " · loops" else ""}. Click a keyframe to move the playhead there.`
		for _, row in rows do
			row.Render()
		end
		highlight()
	end)
end

function Animation.Build(inspector, clip, order, locked)
	exportSection(inspector, clip, order, locked)
	keyframeSection(inspector, clip, order + 1, locked)
end

return Animation
