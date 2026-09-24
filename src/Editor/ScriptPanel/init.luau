local UI = require(script.Parent.UI)
local Ripple = require(script.Ripple)
local Row = require(script.Row)

local ScriptPanel = {}
ScriptPanel.__index = ScriptPanel

local TOOLBAR = 34

local function rippleLabel(ripple, all)
	return if not ripple then "Ripple: off" elseif all then "Ripple: all" else "Ripple: lane"
end

function ScriptPanel.new(app, frame)
	local self = setmetatable({}, ScriptPanel)
	self.App = app
	self.Frame = frame
	self.Rows = {}
	self.Lines = {}
	self.Connections = {}
	self.Pending = false
	local bar = UI.Create("Frame", {
		Name = "ScriptToolbar",
		Parent = frame,
		BackgroundColor3 = "Surface",
		ClipsDescendants = true,
		Size = UDim2.new(1, 0, 0, TOOLBAR),
		Padding = { X = 8, Top = 5, Bottom = 5 },
		List = { FillDirection = "Horizontal", Padding = 6, VerticalAlignment = Enum.VerticalAlignment.Center },
	})
	self.Bar = bar
	self.Divider = UI.Divider({ Parent = frame, Position = UDim2.fromOffset(0, TOOLBAR - 1), ZIndex = 2 })
	self.AddButton = UI.Button({
		Name = "AddLine",
		Parent = bar,
		LayoutOrder = 1,
		Text = "Add line",
		Icon = "Plus",
		Height = 24,
		TextSize = 13,
		Tooltip = "Adds a line right after the selected one, on the same lane, with the same speaker",
		OnClick = function()
			self:AddLine()
		end,
	})
	self.FitButton = UI.Button({
		Name = "AutoFit",
		Parent = bar,
		LayoutOrder = 2,
		Text = "Auto-fit",
		Trailing = "ChevronDown",
		Style = "Ghost",
		Height = 24,
		TextSize = 13,
		Tooltip = "Set line durations from each line's reading time",
		OnClick = function(button)
			self:FitMenu(button.Instance)
		end,
	})
	self.RippleButton = UI.Button({
		Name = "Ripple",
		Parent = bar,
		LayoutOrder = 3,
		Text = rippleLabel(Ripple.Settings(app)),
		Trailing = "ChevronDown",
		Style = "Ghost",
		Height = 24,
		TextSize = 13,
		Tooltip = "When a line gets longer, move the later lines on its lane, or every later clip",
		OnClick = function(button)
			self:RippleMenu(button.Instance)
		end,
	})
	self.List = UI.Create("ScrollingFrame", {
		Name = "Lines",
		Parent = frame,
		Position = UDim2.fromOffset(0, TOOLBAR),
		Size = UDim2.new(1, 0, 1, -TOOLBAR),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = "ScrollBar",
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		List = { Padding = 0 },
	})
	self.Empty = UI.Create("TextLabel", {
		Name = "Empty",
		Parent = self.List,
		LayoutOrder = 1000000,
		Text = "",
		TextSize = 13,
		TextColor3 = "Dim",
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = 16,
		Visible = false,
	})
	self.Count = UI.Create("TextLabel", {
		Name = "Count",
		Parent = self.List,
		LayoutOrder = 1000001,
		Text = "",
		TextSize = 12,
		TextColor3 = "Dim",
		Size = UDim2.new(1, 0, 0, 24),
		Padding = { X = 12 },
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local signals = app.Signals
	table.insert(self.Connections, signals.DocumentChanged:Connect(function()
		self:Schedule()
	end))
	table.insert(self.Connections, signals.SelectionChanged:Connect(function()
		self:Paint()
	end))
	table.insert(self.Connections, signals.TimeChanged:Connect(function()
		self:Paint()
	end))
	self:Rebuild()
	return self
end

function ScriptPanel:Schedule()
	if self.Pending or self.Destroyed then
		return
	end
	self.Pending = true
	task.defer(function()
		self.Pending = false
		if not self.Destroyed then
			self:Rebuild()
		end
	end)
end

function ScriptPanel:Collect()
	local document = self.App.Document
	local lines = {}
	if not document then
		return lines
	end
	for trackIndex, track in document:GetTracks() do
		if track:GetAttribute("Kind") == "Dialogue" then
			for _, clip in document:GetClips(track) do
				table.insert(lines, { Clip = clip, Start = clip:GetAttribute("Start") or 0, Lane = trackIndex })
			end
		end
	end
	table.sort(lines, function(a, b)
		if a.Start ~= b.Start then
			return a.Start < b.Start
		end
		return a.Lane < b.Lane
	end)
	return lines
end

function ScriptPanel:Rebuild()
	local lines = self:Collect()
	local keep = {}
	for index, line in lines do
		local clip = line.Clip
		keep[clip] = true
		local row = self.Rows[clip]
		if not row then
			row = Row.new(self, clip)
			self.Rows[clip] = row
		end
		row:Update(index)
	end
	for clip, row in self.Rows do
		if not keep[clip] then
			row:Destroy()
			self.Rows[clip] = nil
		end
	end
	self.Lines = lines
	local document = self.App.Document
	self.Empty.Visible = #lines == 0
	self.Empty.Text = if document then "No dialogue yet. Add line creates a Dialogue lane at the playhead." else "Open a cutscene to see its script."
	self.Count.Visible = #lines > 0
	self.Count.Text = `{#lines} line{if #lines == 1 then "" else "s"}`
	self.AddButton:SetEnabled(document ~= nil)
	self.FitButton:SetEnabled(#lines > 0)
	self:Paint()
	local focus = self.FocusClip
	if focus and self.Rows[focus] then
		self.FocusClip = nil
		task.defer(function()
			local row = self.Rows[focus]
			if row then
				row.Text:Focus()
			end
		end)
	end
end

function ScriptPanel:Paint()
	local app = self.App
	local t = app.Time
	local current = nil
	for _, line in self.Lines do
		local row = self.Rows[line.Clip]
		if row and row.Start and t >= row.Start - 1e-4 and t < row.Finish then
			current = row
		end
	end
	for clip, row in self.Rows do
		row:SetState(app.Selection.Clips[clip] == true, row == current)
	end
end

function ScriptPanel:Anchor()
	local app = self.App
	local primary = app.Selection.Primary
	if primary and self.Rows[primary] then
		return primary
	end
	local best = nil
	for _, line in self.Lines do
		if line.Start <= app.Time + 1e-4 then
			best = line.Clip
		end
	end
	return best or (self.Lines[#self.Lines] and self.Lines[#self.Lines].Clip)
end

function ScriptPanel:AddLine()
	local app = self.App
	local document = app.Document
	if not document then
		return nil
	end
	local anchor = self:Anchor()
	local track, start, speaker
	if anchor then
		track = anchor.Parent
		start = (anchor:GetAttribute("Start") or 0) + (anchor:GetAttribute("Duration") or 0)
		speaker = anchor:GetAttribute("Speaker")
	else
		for _, candidate in document:GetTracks() do
			if candidate:GetAttribute("Kind") == "Dialogue" and candidate:GetAttribute("Locked") ~= true then
				track = candidate
				break
			end
		end
		start = app.Time
	end
	if track and track:GetAttribute("Locked") == true then
		app:Notify("The dialogue lane is locked", "Warn")
		return nil
	end
	local clip = Ripple.Insert(app, track, start, { Speaker = speaker or "", Text = "", Mood = "Normal" }, anchor)
	if clip then
		self.FocusClip = clip
		app:Select(clip, "Replace")
		self:Schedule()
	end
	return clip
end

function ScriptPanel:Fit(mode)
	local app = self.App
	local clips = {}
	for _, line in self.Lines do
		table.insert(clips, line.Clip)
	end
	local count = Ripple.Fit(app, clips, mode, if mode == "Exact" then "Fit all lines" else "Lengthen short lines")
	app:Notify(if count > 0 then `Fitted {count} line{if count == 1 then "" else "s"} to their reading time` else "Every line already fits", "Info")
	self:Schedule()
	return count
end

function ScriptPanel:FitMenu(anchor)
	local ripple, all = Ripple.Settings(self.App)
	return UI.Menu.Show({
		{
			Text = "Lengthen lines that are too short",
			OnClick = function()
				self:Fit("Grow")
			end,
		},
		{
			Text = "Fit every line to its reading time",
			OnClick = function()
				self:Fit("Exact")
			end,
		},
		{ Separator = true },
		{ Text = if ripple then (if all then "Ripple all is on" else "Ripple is on for dialogue") else "Ripple is off", Enabled = false },
	}, { Anchor = anchor, MinWidth = 240 })
end

function ScriptPanel:SetRipple(ripple, all)
	Ripple.Set(self.App, ripple, all)
	self.RippleButton:SetText(rippleLabel(ripple, all))
end

function ScriptPanel:RippleMenu(anchor)
	local ripple, all = Ripple.Settings(self.App)
	return UI.Menu.Show({
		{
			Text = "Off",
			Checked = not ripple,
			OnClick = function()
				self:SetRipple(false, all)
			end,
		},
		{
			Text = "Later lines on the same lane",
			Checked = ripple and not all,
			OnClick = function()
				self:SetRipple(true, false)
			end,
		},
		{
			Text = "Every later clip on every lane",
			Checked = ripple and all,
			OnClick = function()
				self:SetRipple(true, true)
			end,
		},
	}, { Anchor = anchor, MinWidth = 240 })
end

function ScriptPanel:Destroy()
	self.Destroyed = true
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	for _, row in self.Rows do
		row:Destroy()
	end
	table.clear(self.Rows)
	self.Bar:Destroy()
	self.Divider:Destroy()
	self.List:Destroy()
end

return ScriptPanel
