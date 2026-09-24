local Layout = require(script.Parent.Layout)

local Fields = {}

local MODULES = {
	number = "Basic",
	string = "Basic",
	bool = "Basic",
	enum = "Basic",
	easing = "Basic",
	direction = "Basic",
	Color3 = "Basic",
	Vector3 = "Basic",
	CFrame = "Basic",
	text = "Text",
	actor = "Pickers",
	joint = "Pickers",
	value = "Value",
}

Fields.Stacked = { text = true, Vector3 = true, CFrame = true, value = true }

function Fields.Create(entry, ctx)
	local module = require(script[MODULES[entry.Type] or "Basic"])
	local builder = module[entry.Type] or module.string
	local field = builder(entry, ctx)
	if ctx.ReadOnly then
		if field.SetEnabled then
			field:SetEnabled(false)
		end
		field.Instance.Interactable = false
	end
	return field
end

function Fields.Add(inspector, spec)
	local entry = spec.Entry
	local stacked = if spec.Stacked ~= nil then spec.Stacked else Fields.Stacked[entry.Type]
	local row, holder = Layout.Row(spec.Parent, spec.Order, spec.Label or entry.Label or entry.Name, {
		Stacked = stacked,
		Tooltip = spec.Tooltip or entry.Name,
		Name = entry.Name,
	})
	local readOnly = spec.ReadOnly == true or entry.ReadOnly == true
	local field = Fields.Create(entry, {
		Parent = holder,
		Value = spec.Read(),
		App = inspector.App,
		Inspector = inspector,
		Target = spec.Target,
		Options = spec.Options,
		JointActor = spec.JointActor,
		Transform = spec.Transform,
		FromCamera = spec.FromCamera,
		Placeholder = spec.Placeholder,
		ReadOnly = readOnly,
		Changed = spec.Changed,
		Commit = function(value)
			if not readOnly then
				inspector:Commit(spec.Commit, value)
			end
		end,
	})
	field.Row = row
	inspector:Bind(function()
		if not (field.Busy and field:Busy()) then
			field:Set(spec.Read())
		end
	end)
	inspector.Fields[entry.Name] = field
	return field
end

function Fields.Attribute(inspector, parent, order, target, entry, options)
	options = options or {}
	local attribute = options.Attribute or entry.Name
	local document = inspector.App.Document
	local function read()
		local value = target:GetAttribute(attribute)
		if value == nil and entry.Type ~= "value" then
			return entry.Default
		end
		return value
	end
	return Fields.Add(inspector, {
		Entry = entry,
		Parent = parent,
		Order = order,
		Target = target,
		Label = options.Label,
		Tooltip = options.Tooltip or attribute,
		ReadOnly = options.ReadOnly,
		Options = options.Options,
		JointActor = options.JointActor,
		Transform = options.Transform,
		FromCamera = options.FromCamera,
		Placeholder = options.Placeholder,
		Changed = options.Changed,
		Read = options.Read or read,
		Commit = options.Commit or function(value)
			if options.Clear and value == "" then
				value = nil
			end
			document:SetAttribute(target, attribute, value)
		end,
	})
end

return Fields
