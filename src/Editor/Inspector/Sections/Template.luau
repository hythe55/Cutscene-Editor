local Selection = game:GetService("Selection")

local Layout = require(script.Parent.Parent.Layout)
local Context = require(script.Parent.Parent.Context)
local Library = require(script.Parent.Parent.Library)

local Template = {}

Template.BurstSeconds = 4

local function accepts(instance, actor)
	if actor then
		return instance:IsA("Model") or instance:IsA("BasePart")
	end
	return instance:IsA("Attachment") or instance:IsA("BasePart") or instance:IsA("Model")
end

function Template.Of(container, actor)
	if actor then
		return container:FindFirstChild("Template")
	end
	for _, child in container:GetChildren() do
		if accepts(child, false) then
			return child
		end
	end
	return nil
end

function Template.Summary(template)
	if not template then
		return "No template"
	end
	local counts, order = {}, {}
	for _, descendant in template:GetDescendants() do
		local class = descendant.ClassName
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Light") or descendant:IsA("Beam") or descendant:IsA("Trail") or descendant:IsA("Sound") then
			if not counts[class] then
				table.insert(order, class)
			end
			counts[class] = (counts[class] or 0) + 1
		end
	end
	local parts = {}
	for _, class in order do
		table.insert(parts, `{counts[class]} {class}{if counts[class] == 1 then "" else "s"}`)
	end
	return `{template.ClassName} "{template.Name}"` .. (if #parts > 0 then " · " .. table.concat(parts, ", ") else "")
end

function Template.Replace(app, container, source, actor)
	return Context.Write(app, "Replace template", function(document)
		document:Touch(container)
		local copy = Context.Copy(source)
		assert(copy, "could not copy " .. source:GetFullName())
		for _, child in container:GetChildren() do
			if (actor and child.Name == "Template") or (not actor and accepts(child, false)) then
				child.Parent = nil
			end
		end
		copy.Name = if actor then "Template" else source.Name
		copy.Parent = container
		if actor and container:GetAttribute("Source") ~= "Template" then
			document:WriteAttribute(container, "Source", "Template")
		end
		return copy
	end)
end

local function burstCFrame(app, clip)
	local offset = clip:GetAttribute("Offset")
	offset = if typeof(offset) == "CFrame" then offset else CFrame.identity
	local anchor = clip:GetAttribute("Anchor")
	if type(anchor) == "string" and anchor ~= "" then
		local base = Context.JointWorld(app, anchor, clip:GetAttribute("AnchorJoint"))
		if base then
			return base * offset
		end
	end
	if offset ~= CFrame.identity then
		return offset
	end
	local camera = workspace.CurrentCamera
	return camera.CFrame * CFrame.new(0, 0, -12)
end

function Template.Burst(app, clip, template)
	local cframe = burstCFrame(app, clip)
	local copy = Context.Copy(template)
	if not copy then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = "CutsceneEditorBurst"
	folder.Archivable = false
	copy.Archivable = false
	if copy:IsA("Attachment") then
		local host = Instance.new("Part")
		host.Name = "BurstHost"
		host.Anchored = true
		host.CanCollide = false
		host.CanQuery = false
		host.Transparency = 1
		host.Size = Vector3.new(0.2, 0.2, 0.2)
		host.CFrame = cframe
		host.Parent = folder
		copy.Parent = host
	else
		local parts = if copy:IsA("BasePart") then { copy } else {}
		for _, descendant in copy:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
		for _, part in parts do
			part.Anchored = true
			part.CanCollide = false
		end
		copy:PivotTo(cframe)
		copy.Parent = folder
	end
	folder.Parent = workspace
	local scale = clip:GetAttribute("EmitScale") or 1
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
			local count = descendant:GetAttribute("EmitCount")
			count = if type(count) == "number" then count else math.clamp(descendant.Rate * 0.25, 4, 40)
			descendant:Emit(math.max(math.round(count * scale), 1))
		end
	end
	task.delay(Template.BurstSeconds, function()
		folder:Destroy()
	end)
	return folder
end

function Template.Build(inspector, container, order, locked, options)
	options = options or {}
	local app = inspector.App
	local actor = options.Actor == true
	local category = options.Category or (if actor then "Props" else "VFX")
	local template = Template.Of(container, actor)
	local _, body = Layout.Section(inspector, order, "Template" .. category, options.Title or "Template")
	local summary = Layout.Status(body, 1, "TemplateSummary")
	summary.Set(Template.Summary(template), if template then "Text" else "Warning")
	local actions = Layout.Buttons(body, 2, "TemplateActions")
	local replace
	replace = Layout.Button(actions, 1, "Replace…", function()
		Library.Pick(replace.Instance, {
			Category = category,
			Title = "Replace from " .. category,
			OnPick = function(source)
				inspector:Commit(function()
					Template.Replace(app, container, source, actor)
				end)
			end,
		})
	end, { Name = "ReplaceTemplate", Enabled = not locked, Tooltip = `Pick a template from the {category} library` })
	Layout.Button(actions, 2, "Use selection", function()
		local picked = nil
		for _, instance in Selection:Get() do
			if accepts(instance, actor) and not instance:IsDescendantOf(container) then
				picked = instance
				break
			end
		end
		if not picked then
			app:Notify(if actor then "Select a Model or Part in the Explorer first" else "Select an Attachment, Part or Model in the Explorer first", "Warn")
			return
		end
		inspector:Commit(function()
			Template.Replace(app, container, picked, actor)
		end)
	end, { Name = "UseSelection", Style = "Ghost", Enabled = not locked, Tooltip = "Copy the instance selected in the Explorer in as the template" })
	Layout.Button(actions, 3, "Select", function()
		if template then
			Selection:Set({ template })
		end
	end, { Name = "SelectTemplate", Style = "Ghost", Enabled = template ~= nil, Tooltip = "Select the template in the Explorer" })
	if not actor then
		Layout.Button(actions, 4, "Burst", function()
			if template and Template.Burst(app, container, template) then
				app:Notify("Burst preview plays for a few seconds at the clip's anchor", "Info")
			end
		end, { Name = "BurstPreview", Style = "Ghost", Enabled = template ~= nil, Tooltip = "Emit the effect once in the viewport" })
	end
end

return Template
