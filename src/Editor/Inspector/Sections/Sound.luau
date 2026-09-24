local Selection = game:GetService("Selection")

local Layout = require(script.Parent.Parent.Layout)
local Fields = require(script.Parent.Parent.Fields)
local Context = require(script.Parent.Parent.Context)
local Audition = require(script.Parent.Parent.Audition)
local Library = require(script.Parent.Parent.Library)

local Sound = {}

local PROPERTIES = {
	{ Name = "SoundId", Type = "string", Label = "Sound id" },
	{ Name = "Volume", Type = "number", Label = "Volume", Min = 0, Max = 10, Step = 0.05 },
	{ Name = "PlaybackSpeed", Type = "number", Label = "Playback speed", Min = 0.05, Max = 10, Step = 0.05 },
	{ Name = "Looped", Type = "bool", Label = "Looped" },
}

function Sound.Template(clip)
	return clip:FindFirstChildWhichIsA("Sound")
end

function Sound.Range(clip, sound)
	local offset = clip:GetAttribute("StartOffset") or 0
	local duration = clip:GetAttribute("Duration") or 0
	local speed = (clip:GetAttribute("Speed") or 1) * sound.PlaybackSpeed
	return offset, offset + duration * speed, sound.TimeLength
end

function Sound.Replace(app, clip, source)
	return Context.Write(app, "Replace sound", function(document)
		document:Touch(clip)
		local copy = Context.Copy(source)
		assert(copy, "could not copy " .. source:GetFullName())
		for _, child in clip:GetChildren() do
			if child:IsA("Sound") then
				child.Parent = nil
			end
		end
		copy.Name = "Sound"
		copy.Parent = clip
		return copy
	end)
end

function Sound.Build(inspector, clip, order, locked)
	local app = inspector.App
	local sound = Sound.Template(clip)
	local _, body = Layout.Section(inspector, order, "SoundTemplate", "Sound asset")
	local actions = Layout.Buttons(body, 20, "SoundActions")
	local replace
	replace = Layout.Button(actions, 2, "Replace…", function()
		Library.Pick(replace.Instance, {
			Category = "Sounds",
			Title = "Replace sound",
			OnPick = function(source)
				inspector:Commit(function()
					Sound.Replace(app, clip, source)
				end)
			end,
		})
	end, { Name = "ReplaceSound", Enabled = not locked, Tooltip = "Pick a sound from the asset library" })
	if not sound then
		Layout.Text(body, 1, "This clip has no Sound yet. Pick one from the library.", { Color = "Warning" })
		return
	end
	for index, property in PROPERTIES do
		Fields.Add(inspector, {
			Entry = property,
			Parent = body,
			Order = index,
			Target = sound,
			ReadOnly = locked,
			Tooltip = "Sound." .. property.Name,
			Read = function()
				return sound[property.Name]
			end,
			Commit = function(value)
				Context.Write(app, "Set " .. property.Name, function(document)
					document:Touch(clip)
					sound[property.Name] = value
				end)
			end,
		})
	end
	local range = Layout.Text(body, 10, "", { Name = "Range" })
	inspector:Bind(function()
		local from, to, total = Sound.Range(clip, sound)
		range.Text = `Plays {string.format("%.2f", from)} to {string.format("%.2f", to)} s of {if total > 0 then string.format("%.2f s", total) else "an unloaded sound"}`
	end)
	local play
	play = Layout.Button(actions, 1, "Play", function()
		if Audition.IsPlaying(sound) then
			Audition.Stop()
			return
		end
		local from, to = Sound.Range(clip, sound)
		local speed = clip:GetAttribute("Speed") or 1
		Audition.Play(sound, { Offset = from, Duration = (to - from) / math.max(sound.PlaybackSpeed * speed, 0.01), Speed = speed })
	end, { Name = "PlaySound", Style = "Primary", Tooltip = "Preview the clip's part of the sound" })
	local function render()
		play:SetText(if Audition.IsPlaying(sound) then "Stop" else "Play")
	end
	local connection = Audition.Changed:Connect(render)
	inspector:OnClear(function()
		connection:Disconnect()
		if Audition.IsPlaying(sound) then
			Audition.Stop()
		end
	end)
	render()
	Layout.Button(actions, 3, "Select", function()
		Selection:Set({ sound })
	end, { Name = "SelectSound", Style = "Ghost", Tooltip = "Select the Sound in the Explorer" })
	Layout.Button(actions, 4, "Fit to sound", function()
		local from, _, total = Sound.Range(clip, sound)
		if total <= 0 then
			app:Notify("The sound has not loaded, so its length is unknown", "Warn")
			return
		end
		local speed = (clip:GetAttribute("Speed") or 1) * sound.PlaybackSpeed
		inspector:Commit(function()
			app.Document:SetClipTiming(clip, nil, math.max(total - from, 0) / math.max(speed, 0.01), true)
		end)
	end, { Name = "FitSound", Style = "Ghost", Enabled = not locked, Tooltip = "Duration = rest of the sound after the start offset" })
end

return Sound
