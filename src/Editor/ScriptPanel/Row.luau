local UI = require(script.Parent.Parent.UI)
local Context = require(script.Parent.Parent.Inspector.Context)
local Text = require(script.Parent.Parent.Inspector.Fields.Text)
local Ripple = require(script.Parent.Ripple)

local Row = {}
Row.__index = Row

local function formatTime(t)
	local minutes = math.floor(t / 60)
	return string.format("%d:%05.2f", minutes, t - minutes * 60)
end

function Row.new(panel, clip)
	local app = panel.App
	local self = setmetatable({ Panel = panel, Clip = clip, Selected = false, Current = false, SpeakerId = false }, Row)
	local button = UI.Create("TextButton", {
		Name = "Line",
		Parent = panel.List,
		Text = "",
		BackgroundColor3 = "Panel",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	self.Instance = button
	self.Marker = UI.Create("Frame", {
		Name = "Marker",
		Parent = button,
		BackgroundColor3 = "Playhead",
		Size = UDim2.new(0, 3, 1, 0),
		Visible = false,
	})
	UI.Divider({ Parent = button, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1) })
	local root = UI.Create("Frame", {
		Name = "Body",
		Parent = button,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = { Left = 10, Right = 8, Top = 4, Bottom = 5 },
		List = { Padding = 1 },
	})
	local top = UI.Create("Frame", {
		Name = "Top",
		Parent = root,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 18),
	})
	self.Time = UI.Create("TextLabel", {
		Name = "Time",
		Parent = top,
		Text = "",
		Font = "Mono",
		TextSize = 12,
		TextColor3 = "Dim",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0, 58, 1, 0),
	})
	self.Speaker = UI.Create("TextLabel", {
		Name = "Speaker",
		Parent = top,
		Text = "",
		Font = "Bold",
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(60, 0),
		Size = UDim2.new(1, -140, 1, 0),
	})
	self.Badge = UI.Create("TextButton", {
		Name = "Duration",
		Parent = top,
		Text = "",
		Font = "Medium",
		TextSize = 12,
		BackgroundColor3 = "Sunken",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Corner = UDim.new(1, 0),
		Padding = { Left = 8, Right = 8 },
		Tooltip = function()
			return self.BadgeTip
		end,
	})
	self.Text = Text.new({}, {
		Parent = root,
		LayoutOrder = 2,
		Value = clip:GetAttribute("Text") or "",
		Placeholder = "Type the line…",
		MinHeight = 22,
		TextSize = 14,
		Compact = true,
		Commit = function(value)
			app.Document:SetAttribute(clip, "Text", value)
			panel:Schedule()
		end,
		OnFocus = function()
			if app.Selection.Primary ~= clip then
				app:Select(clip, "Replace")
			end
		end,
	})
	button.Activated:Connect(function()
		app:Select(clip, "Replace")
		app:SetTime(clip:GetAttribute("Start") or 0)
	end)
	self.Badge.Activated:Connect(function()
		if clip.Parent and clip.Parent:GetAttribute("Locked") ~= true then
			Ripple.Fit(app, { clip }, "Exact", "Fit line to reading time")
			panel:Schedule()
		end
	end)
	return self
end

function Row:Update(order)
	local app = self.Panel.App
	local clip = self.Clip
	self.Instance.LayoutOrder = order
	local start = clip:GetAttribute("Start") or 0
	local duration = clip:GetAttribute("Duration") or 0
	local speaker = clip:GetAttribute("Speaker")
	local mood = clip:GetAttribute("Mood")
	self.Time.Text = formatTime(start)
	self.Speaker.Text = Context.SpeakerName(app, speaker) .. (if type(mood) == "string" and mood ~= "" and mood ~= "Normal" then "  · " .. mood else "")
	if speaker ~= self.SpeakerId then
		self.SpeakerId = speaker
		UI.Set(self.Speaker, "TextColor3", Context.SpeakerToken(speaker))
	end
	local reading = Ripple.ReadingTime(app, clip)
	local short = duration + 1e-3 < reading
	self.Badge.Text = if short then string.format("%.1f / %.1f s", duration, reading) else string.format("%.1f s", duration)
	UI.Set(self.Badge, "TextColor3", if short then "Error" else "Dim")
	UI.Set(self.Badge, "BackgroundColor3", if short then "ErrorSoft" else "Sunken")
	self.BadgeTip = if short then `Needs {string.format("%.1f", reading)} s to read. Click to fit.` else `Reads in {string.format("%.1f", reading)} s. Click to fit exactly.`
	self.Text:Set(clip:GetAttribute("Text") or "")
	self.Start, self.Finish = start, start + duration
end

function Row:SetState(selected, current)
	if selected ~= self.Selected or self.Painted == nil then
		self.Selected = selected
		UI.Set(self.Instance, "BackgroundColor3", if selected then "AccentSoft" else "Panel")
	end
	self.Painted = true
	self.Current = current
	self.Marker.Visible = current
end

function Row:Destroy()
	self.Instance:Destroy()
end

return Row
