local Layout = require(script.Parent.Parent.Layout)
local Fields = require(script.Parent.Parent.Fields)
local Context = require(script.Parent.Parent.Context)
local Ripple = require(script.Parent.Parent.Parent.ScriptPanel.Ripple)

local Dialogue = {}

local function entryOf(schema, name)
	for _, entry in schema.Kinds.Dialogue.Fields do
		if entry.Name == name then
			return entry
		end
	end
	return { Name = name, Type = "string", Label = name }
end

local function length(text)
	local ok, count = pcall(utf8.len, text)
	return if ok and count then count else #text
end

function Dialogue.Stats(app, clip, text)
	text = text or clip:GetAttribute("Text") or ""
	local reading = Context.ReadingTime(app, text, clip:GetAttribute("TypeSpeed"), clip:GetAttribute("Mood"))
	local duration = clip:GetAttribute("Duration") or 0
	return {
		Characters = length(text),
		Reading = reading,
		Duration = duration,
		Short = duration + 1e-3 < reading,
	}
end

function Dialogue.Build(inspector, clip, order, locked)
	local app = inspector.App
	local schema = app.Deps.Schema
	local _, body = Layout.Section(inspector, order, "Dialogue", "Dialogue")
	Fields.Attribute(inspector, body, 1, clip, entryOf(schema, "Speaker"), { ReadOnly = locked })
	local live = nil
	local stats = nil
	local function update()
		local info = Dialogue.Stats(app, clip, live)
		local summary = `{info.Characters} characters · reads in {string.format("%.1f", info.Reading)} s · clip {string.format("%.2f", info.Duration)} s`
		if info.Short then
			stats.Set(`Needs {string.format("%.1f", info.Reading)} s to read. {summary}`, "Error")
		else
			stats.Set(summary, "Success")
		end
	end
	local text = Fields.Attribute(inspector, body, 2, clip, entryOf(schema, "Text"), {
		ReadOnly = locked,
		Placeholder = "What does the speaker say?",
		Changed = function(value)
			live = value
			update()
		end,
	})
	if not locked then
		local tokens = Layout.Buttons(body, 3, "Tokens")
		Layout.Text(tokens, 0, "Insert", { TextSize = 12 }).Size = UDim2.fromOffset(38, 20)
		for index, role in Context.Roles(app) do
			local token = "{" .. role .. "}"
			Layout.Button(tokens, index, token, function()
				text:Insert(token)
			end, {
				Name = "Token" .. role,
				Style = "Ghost",
				Height = 20,
				TextSize = 12,
				Tooltip = `Replaced by the name of the player playing {role}`,
			})
		end
	end
	stats = Layout.Status(body, 4, "Reading")
	local actions = Layout.Buttons(body, 5, "FitActions")
	Layout.Button(actions, 1, "Fit to reading time", function()
		inspector:Commit(function()
			if Ripple.Fit(app, { clip }, "Exact", "Fit line to reading time") == 0 then
				app:Notify("The line already matches its reading time", "Info")
			end
		end)
	end, {
		Name = "FitReading",
		Enabled = not locked,
		Tooltip = "Sets the duration to the provider's reading time. Ripple in the Script tab shifts later lines.",
	})
	inspector:Bind(function()
		if not text:Busy() then
			live = nil
		end
		update()
	end)
	update()
	Fields.Attribute(inspector, body, 6, clip, entryOf(schema, "Mood"), { ReadOnly = locked, Options = Context.Moods(app) })
	Fields.Attribute(inspector, body, 7, clip, entryOf(schema, "TypeSpeed"), { ReadOnly = locked })
	Fields.Attribute(inspector, body, 8, clip, entryOf(schema, "Blips"), { ReadOnly = locked })
	local extras = Context.ProviderFields(app)
	if #extras > 0 then
		local _, section = Layout.Section(inspector, order + 1, "ProviderFields", "Provider fields")
		for index, definition in extras do
			if type(definition) == "table" and type(definition.Name) == "string" then
				local entry = table.clone(definition)
				entry.Type = entry.Type or "string"
				entry.Label = entry.Label or entry.Name
				Fields.Attribute(inspector, section, index, clip, entry, {
					Attribute = "X_" .. definition.Name,
					ReadOnly = locked,
					Tooltip = "Stored as X_" .. definition.Name,
				})
			end
		end
	end
end

return Dialogue
