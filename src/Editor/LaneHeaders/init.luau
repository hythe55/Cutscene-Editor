local UI = require(script.Parent.UI)

local LaneHeaders = {}
LaneHeaders.__index = LaneHeaders

local SCROLL_STEP = 40
local SOURCE_LABELS = { Tag = "TAG", Template = "PROP", Role = "ROLE", Group = "GROUP" }

local function signature(app, rows)
	local parts = { app.Theme.Name }
	for _, row in rows do
		if row.Type == "Group" then
			local actor = row.Actor
			table.insert(parts, "G" .. (if actor then actor.Name .. tostring(actor:GetAttribute("DisplayName")) .. tostring(actor:GetAttribute("Source")) else "") .. tostring(row.Collapsed))
		else
			local info = row.Info
			table.insert(parts, table.concat({ "T", info.Name, tostring(info.Kind), tostring(info.Muted), tostring(info.Locked), tostring(#info.Clips) }, ":"))
		end
	end
	return table.concat(parts, "|")
end

function LaneHeaders.new(app, frame)
	local self = setmetatable({}, LaneHeaders)
	self.App = app
	self.Frame = frame
	self.Connections = {}
	self.RowFrames = {}
	local top = UI.Create("Frame", {
		Name = "HeaderTop",
		Parent = frame,
		BackgroundColor3 = "Surface",
		Size = UDim2.new(1, 0, 0, app.RulerHeight),
		ZIndex = 3,
	})
	UI.Divider({ Parent = top, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), BackgroundColor3 = "Border" })
	UI.Create("TextLabel", {
		Parent = top,
		Text = "TRACKS",
		Font = "Bold",
		TextSize = 11,
		TextColor3 = "Dim",
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -60, 1, 0),
	})
	self.AddActor = UI.Button({
		Parent = top,
		Text = "Actor",
		Icon = "Plus",
		Style = "Toolbar",
		Height = 22,
		TextSize = 12,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Tooltip = "Add an actor",
		OnClick = function(button)
			self:AddActorMenu(button.Instance)
		end,
	})
	local viewport = UI.Create("Frame", {
		Name = "Viewport",
		Parent = frame,
		Position = UDim2.fromOffset(0, app.RulerHeight),
		Size = UDim2.new(1, 0, 1, -app.RulerHeight),
		ClipsDescendants = true,
	})
	self.Viewport = viewport
	self.Content = UI.Create("Frame", { Name = "Rows", Parent = viewport, Size = UDim2.fromScale(1, 0) })
	self.EmptyLabel = UI.Create("TextLabel", {
		Parent = viewport,
		Text = "No tracks yet. Add an actor, then add tracks to it.",
		TextSize = 12,
		TextColor3 = "Dim",
		TextWrapped = true,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -24, 0, 40),
		Visible = false,
	})
	viewport.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			app:SetScrollY(app.ScrollY - input.Position.Z * SCROLL_STEP)
		end
	end)
	local signals = app.Signals
	table.insert(self.Connections, signals.DocumentChanged:Connect(function()
		self:Rebuild(false)
	end))
	table.insert(self.Connections, signals.ViewChanged:Connect(function()
		self:Rebuild(false)
		self:_scroll()
	end))
	table.insert(self.Connections, signals.SelectionChanged:Connect(function()
		self:_highlight()
	end))
	table.insert(self.Connections, signals.ThemeChanged:Connect(function()
		self:Rebuild(true)
	end))
	self:Rebuild(true)
	return self
end

function LaneHeaders:_scroll()
	self.Content.Position = UDim2.fromOffset(0, -self.App.ScrollY)
end

function LaneHeaders:Rebuild(force)
	local app = self.App
	local rows, total = app:GetRows()
	local key = signature(app, rows)
	if not force and key == self.Signature then
		return
	end
	self.Signature = key
	for _, entry in self.RowFrames do
		entry.Frame:Destroy()
	end
	table.clear(self.RowFrames)
	self.Content.Size = UDim2.new(1, 0, 0, total)
	for index, row in rows do
		local entry = if row.Type == "Group" then self:_group(row) else self:_track(row, index)
		entry.Row = row
		table.insert(self.RowFrames, entry)
	end
	self.EmptyLabel.Visible = app.Document ~= nil and #rows == 0
	self.AddActor:SetEnabled(app.Document ~= nil)
	self:_scroll()
	self:_highlight()
end

function LaneHeaders:_highlight()
	local selection = self.App.Selection
	for _, entry in self.RowFrames do
		local row = entry.Row
		local selected
		if row.Type == "Track" then
			selected = selection.Track == row.Track
		else
			selected = row.Actor ~= nil and selection.Actor == row.Actor and selection.Track == nil and next(selection.Clips) == nil
		end
		entry.Selected = selected
		entry.Render()
	end
end

local function rowButton(self, row, name)
	return UI.Create("TextButton", {
		Name = name,
		Parent = self.Content,
		Text = "",
		Position = UDim2.fromOffset(0, row.Y),
		Size = UDim2.new(1, 0, 0, row.Height),
		BackgroundColor3 = "Panel",
	})
end

function LaneHeaders:_group(row)
	local app = self.App
	local actor = row.Actor
	local frame = rowButton(self, row, "Group")
	UI.Divider({ Parent = frame, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1) })
	local chevron = UI.Create("Frame", {
		Parent = frame,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
	})
	UI.Icons.Draw(if row.Collapsed then "ChevronRight" else "ChevronDown", chevron, "Dim", 16)
	local displayName = if actor then actor:GetAttribute("DisplayName") else nil
	local label = UI.Create("TextLabel", {
		Parent = frame,
		Text = if actor then actor.Name else "Scene",
		Font = "Bold",
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(22, 0),
		Size = UDim2.new(1, -100, 1, 0),
		Tooltip = if type(displayName) == "string" and displayName ~= "" then `Shown in dialogue as "{displayName}"` else nil,
	})
	local source = if actor then SOURCE_LABELS[actor:GetAttribute("Source")] else "GLOBAL"
	local badge = UI.Create("TextLabel", {
		Parent = frame,
		Text = source or "",
		Font = "Bold",
		TextSize = 9,
		TextColor3 = "Dim",
		BackgroundColor3 = UI.Color("Panel", "Text", 0.08),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -30, 0.5, 0),
		Size = UDim2.fromOffset(0, 15),
		AutomaticSize = Enum.AutomaticSize.X,
		Corner = 3,
		Padding = { Left = 5, Right = 5 },
	})
	local add = UI.IconButton({
		Parent = frame,
		Icon = "Plus",
		Size = 20,
		IconSize = 14,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -5, 0.5, 0),
		Tooltip = if actor then `Add a track for {actor.Name}` else "Add a scene track",
		OnClick = function(button)
			self:AddTrackMenu(actor, button.Instance)
		end,
	})
	local entry = { Frame = frame }
	local hover = false
	function entry.Render()
		UI.Set(frame, "BackgroundColor3", if entry.Selected then "Selection" elseif hover then UI.Color("GroupRow", "Text", 0.04) else "GroupRow")
		UI.Set(label, "TextColor3", if entry.Selected then "Text" else "Text")
	end
	frame.MouseEnter:Connect(function()
		hover = true
		entry.Render()
	end)
	frame.MouseLeave:Connect(function()
		hover = false
		entry.Render()
	end)
	frame.Activated:Connect(function(input, clicks)
		local position = input and input.Position
		if position and position.X - frame.AbsolutePosition.X < 22 then
			app:SetCollapsed(actor, not row.Collapsed)
		elseif clicks == 2 then
			app:SetCollapsed(actor, not row.Collapsed)
		elseif actor then
			app:Select(actor)
		end
	end)
	frame.MouseButton2Click:Connect(function()
		self:GroupMenu(row, frame)
	end)
	entry.Badge = badge
	entry.Add = add
	return entry
end

function LaneHeaders:_track(row, index)
	local app = self.App
	local info = row.Info
	local track = row.Track
	local frame = rowButton(self, row, "Track")
	UI.Divider({ Parent = frame, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), BackgroundColor3 = UI.Color("Divider", "Panel", 0.4) })
	local accent = UI.Create("Frame", {
		Parent = frame,
		BackgroundColor3 = UI.Kind(info.Kind),
		Position = UDim2.fromOffset(14, 7),
		Size = UDim2.new(0, 3, 1, -14),
		Corner = 2,
	})
	local name = UI.Create("TextLabel", {
		Parent = frame,
		Text = info.Name,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(24, 2),
		Size = UDim2.new(1, -78, 0, 16),
	})
	local kind = UI.Create("TextLabel", {
		Parent = frame,
		Text = string.upper(tostring(info.Kind)) .. "  ·  " .. #info.Clips .. (if #info.Clips == 1 then " clip" else " clips"),
		Font = "Medium",
		TextSize = 10,
		TextColor3 = "Dim",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(24, 16),
		Size = UDim2.new(1, -78, 0, 12),
	})
	local mute = UI.Create("TextButton", {
		Name = "Mute",
		Parent = frame,
		Text = "M",
		Font = "Bold",
		TextSize = 11,
		BackgroundColor3 = "Hover",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -28, 0.5, 0),
		Size = UDim2.fromOffset(20, 20),
		Corner = 4,
		Tooltip = "Mute: skip this track in previews and in game",
	})
	local lock = UI.Create("TextButton", {
		Name = "Lock",
		Parent = frame,
		Text = "",
		BackgroundColor3 = "Hover",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(20, 20),
		Corner = 4,
		Tooltip = "Lock: protect this track's clips from edits",
	})
	local lockIcon = UI.Icons.Draw(if info.Locked then "Lock" else "Unlock", lock, "Dim", 14)
	local entry = { Frame = frame }
	local hover, hoverMute, hoverLock = false, false, false
	function entry.Render()
		local selected = entry.Selected
		UI.Set(frame, "BackgroundColor3", if selected then "Selection" elseif hover then UI.Color("Panel", "Text", 0.04) else "Panel")
		UI.Set(name, "TextColor3", if info.Muted then "Dim" else "Text")
		accent.BackgroundTransparency = if info.Muted then 0.6 else 0
		UI.Set(mute, "BackgroundColor3", if info.Muted then UI.Color("Window", "Mute", 0.28) else "Hover")
		mute.BackgroundTransparency = if info.Muted or hoverMute then 0 else 1
		UI.Set(mute, "TextColor3", if info.Muted then "Mute" elseif hoverMute then "Text" elseif hover or selected then "Dim" else "Faint")
		UI.Set(lock, "BackgroundColor3", if info.Locked then UI.Color("Window", "Lock", 0.28) else "Hover")
		lock.BackgroundTransparency = if info.Locked or hoverLock then 0 else 1
		UI.Icons.Recolor(lockIcon, if info.Locked then "Lock" elseif hoverLock then "Text" elseif hover or selected then "Dim" else "Faint")
	end
	frame.MouseEnter:Connect(function()
		hover = true
		entry.Render()
	end)
	frame.MouseLeave:Connect(function()
		hover = false
		entry.Render()
	end)
	for _, pair in { { mute, "Mute" }, { lock, "Lock" } } do
		pair[1].MouseEnter:Connect(function()
			if pair[2] == "Mute" then
				hoverMute = true
			else
				hoverLock = true
			end
			entry.Render()
		end)
		pair[1].MouseLeave:Connect(function()
			if pair[2] == "Mute" then
				hoverMute = false
			else
				hoverLock = false
			end
			entry.Render()
		end)
	end
	frame.Activated:Connect(function(_, clicks)
		if clicks == 2 then
			self:Rename(track, name)
		else
			app:Select(track)
		end
	end)
	frame.MouseButton2Click:Connect(function()
		app:Select(track)
		self:TrackMenu(row, frame)
	end)
	mute.Activated:Connect(function()
		if app.Document then
			app.Document:SetAttribute(track, "Muted", not info.Muted)
		end
	end)
	lock.Activated:Connect(function()
		if app.Document then
			app.Document:SetAttribute(track, "Locked", not info.Locked)
		end
	end)
	entry.Index = index
	entry.NameLabel = name
	return entry
end

function LaneHeaders:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Viewport:Destroy()
	for _, child in self.Frame:GetChildren() do
		child:Destroy()
	end
end

require(script.Menus)(LaneHeaders)

return LaneHeaders
