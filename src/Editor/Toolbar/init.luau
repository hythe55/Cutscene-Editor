local UI = require(script.Parent.UI)
local Menus = require(script.Menus)
local Runtime = require(script.Runtime)

local Toolbar = {}
Toolbar.__index = Toolbar

local ZOOM_STEP = 1.35
local STATUS_COLORS = { Current = "Success", Newer = "Accent", Outdated = "Warning", Missing = "Warning", Unknown = "Warning" }

function Toolbar.FormatTime(t)
	t = math.max(t or 0, 0)
	local minutes = math.floor(t / 60)
	return string.format("%d:%05.2f", minutes, t - minutes * 60)
end

function Toolbar.ParseTime(text)
	text = string.gsub(text or "", "%s", "")
	local minutes, seconds = string.match(text, "^(%d+):(%d*%.?%d*)$")
	if minutes then
		return tonumber(minutes) * 60 + (tonumber(seconds) or 0)
	end
	return tonumber(text)
end

local function separator(parent, order)
	return UI.Create("Frame", {
		Parent = parent,
		LayoutOrder = order,
		Size = UDim2.fromOffset(9, 20),
	}, {
		UI.Create("Frame", {
			BackgroundColor3 = "Divider",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.new(0, 1, 1, 0),
		}),
	})
end

function Toolbar.new(app, frame)
	local self = setmetatable({}, Toolbar)
	self.App = app
	self.Frame = frame
	self.Connections = {}
	local left = UI.Create("Frame", {
		Name = "Left",
		Parent = frame,
		Size = UDim2.fromScale(1, 1),
		Padding = { Left = 8 },
		List = { FillDirection = "Horizontal", Padding = 4, VerticalAlignment = Enum.VerticalAlignment.Center },
	})
	local right = UI.Create("Frame", {
		Name = "Right",
		Parent = frame,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Padding = { Right = 8, Left = 8 },
		BackgroundColor3 = "Surface",
		List = {
			FillDirection = "Horizontal",
			Padding = 4,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		},
	})
	self.Left, self.Right = left, right
	self.Picker = UI.Button({
		Parent = left,
		LayoutOrder = 1,
		Style = "Toolbar",
		Icon = "Film",
		Text = "No cutscene",
		Trailing = "ChevronDown",
		Height = 28,
		Font = "Bold",
		Tooltip = "Open a cutscene from ReplicatedStorage.Cutscenes",
		OnClick = function()
			self:OpenPicker()
		end,
	})
	separator(left, 2)
	self.SkipStart = UI.IconButton({
		Parent = left,
		LayoutOrder = 3,
		Icon = "SkipStart",
		Size = 28,
		Tooltip = "Go to start (Home)",
		OnClick = function()
			app:SetTime(0)
		end,
	})
	self.PlayButton = UI.IconButton({
		Parent = left,
		LayoutOrder = 4,
		Icon = "Play",
		Size = 28,
		Style = "Default",
		Tooltip = "Play / pause (Space)",
		OnClick = function()
			app.Preview:Toggle()
		end,
	})
	self.StopButton = UI.IconButton({
		Parent = left,
		LayoutOrder = 5,
		Icon = "Stop",
		Size = 28,
		Tooltip = "Stop the preview and restore the scene",
		OnClick = function()
			app.Preview:Stop()
		end,
	})
	self:_buildTime(left, 6)
	separator(left, 7)
	self.SnapButton = UI.IconButton({
		Parent = left,
		LayoutOrder = 8,
		Icon = "Snap",
		Size = 28,
		Toggle = true,
		Value = app.Snap,
		Tooltip = "Snap to clip edges, keys, the playhead and frames (hold Alt to bypass)",
		OnChanged = function(value)
			app:SetSnap(value)
		end,
	})
	self.ZoomOut = UI.IconButton({
		Parent = left,
		LayoutOrder = 9,
		Icon = "Minus",
		Size = 28,
		Tooltip = "Zoom out (Ctrl+wheel)",
		OnClick = function()
			app:SetZoom(app.PixelsPerSecond / ZOOM_STEP)
		end,
	})
	self.ZoomIn = UI.IconButton({
		Parent = left,
		LayoutOrder = 10,
		Icon = "Plus",
		Size = 28,
		Tooltip = "Zoom in (Ctrl+wheel)",
		OnClick = function()
			app:SetZoom(app.PixelsPerSecond * ZOOM_STEP)
		end,
	})
	self.FitButton = UI.Button({
		Parent = left,
		LayoutOrder = 11,
		Text = "Fit",
		Style = "Toolbar",
		Height = 28,
		Tooltip = "Fit the whole cutscene in view",
		OnClick = function()
			app:FitView()
		end,
	})
	separator(left, 12)
	self.CameraButton = UI.Button({
		Parent = left,
		LayoutOrder = 13,
		Icon = "Eye",
		Text = "Camera",
		Style = "Default",
		Height = 28,
		Tooltip = "Look through the cutscene camera (C). Moving the view unlocks it.",
		OnClick = function()
			app.Preview:ToggleCameraLock()
		end,
	})
	self.ProviderButton = UI.Button({
		Parent = right,
		LayoutOrder = 1,
		Icon = "Chat",
		Text = "Dialogue",
		Trailing = "ChevronDown",
		Style = "Toolbar",
		Height = 28,
		Tooltip = "Dialogue provider and preview stand-ins",
		OnClick = function(button)
			Menus.Provider(app, button.Instance)
		end,
	})
	self.RuntimeButton = UI.Button({
		Parent = right,
		LayoutOrder = 2,
		Icon = "Runtime",
		Text = "Runtime",
		Trailing = "ChevronDown",
		Style = "Toolbar",
		Height = 28,
		Tooltip = "Timeline runtime installed in this place",
		OnClick = function(button)
			Menus.Runtime(app, button.Instance)
		end,
	})
	self.RuntimeDot = UI.Create("Frame", {
		Parent = self.RuntimeButton.Instance,
		BackgroundColor3 = "Dim",
		Position = UDim2.fromOffset(17, 5),
		Size = UDim2.fromOffset(7, 7),
		Corner = UDim.new(1, 0),
		Stroke = { Color = "Surface", Thickness = 1.5 },
		ZIndex = 3,
	})
	separator(right, 3)
	self.ExportButton = UI.Button({
		Parent = right,
		LayoutOrder = 4,
		Icon = "Export",
		Text = "Export",
		Style = "Default",
		Height = 28,
		Tooltip = "Upload changed animations to Roblox",
		OnClick = function()
			self:Export()
		end,
	})
	local signals = app.Signals
	table.insert(self.Connections, signals.TimeChanged:Connect(function()
		self:_renderTime()
	end))
	for _, name in { "PreviewChanged", "DocumentChanged" } do
		table.insert(self.Connections, signals[name]:Connect(function()
			self:Render()
		end))
	end
	table.insert(self.Connections, signals.ViewChanged:Connect(function()
		if self.SnapButton:Get() ~= app.Snap then
			self.SnapButton:Set(app.Snap)
		end
	end))
	table.insert(self.Connections, frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_responsive()
	end))
	table.insert(self.Connections, app.Shell.Root.InputBegan:Connect(function(input)
		self:_key(input)
	end))
	self:Render()
	self:_responsive()
	return self
end

function Toolbar:_buildTime(parent, order)
	local app = self.App
	local holder = UI.Create("TextButton", {
		Name = "Time",
		Parent = parent,
		LayoutOrder = order,
		Text = "",
		BackgroundColor3 = "Sunken",
		Size = UDim2.fromOffset(150, 28),
		Corner = 4,
		Tooltip = "Playhead time. Click to type a time (seconds or m:ss.ss).",
	})
	self.TimeLabel = UI.Create("TextLabel", {
		Parent = holder,
		Text = "0:00.00",
		Font = "MonoBold",
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(0.5, 4, 1, 0),
	})
	self.LengthLabel = UI.Create("TextLabel", {
		Parent = holder,
		Text = "/ 0:00.00",
		Font = "Mono",
		TextSize = 12,
		TextColor3 = "Dim",
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0.5, 10, 0, 0),
		Size = UDim2.new(0.5, -12, 1, 0),
	})
	local box = UI.Create("TextBox", {
		Parent = holder,
		Text = "",
		Font = "MonoBold",
		TextSize = 14,
		Visible = false,
		BackgroundColor3 = "Sunken",
		Size = UDim2.fromScale(1, 1),
		Corner = 4,
		Stroke = { Color = "Accent", Thickness = 1 },
	})
	holder.Activated:Connect(function()
		box.Text = Toolbar.FormatTime(app.Time)
		box.Visible = true
		box:CaptureFocus()
		box.SelectionStart = 1
		box.CursorPosition = #box.Text + 1
	end)
	box.FocusLost:Connect(function(enter)
		box.Visible = false
		local t = Toolbar.ParseTime(box.Text)
		if enter and t then
			app:SetTime(t)
		end
	end)
	self.TimeHolder = holder
end

function Toolbar:_renderTime()
	local app = self.App
	self.TimeLabel.Text = Toolbar.FormatTime(app.Time)
end

function Toolbar:Render()
	local app = self.App
	local document = app.Document
	local preview = app.Preview
	self.Picker:SetText(if document then document.Folder.Name else "No cutscene")
	self.LengthLabel.Text = "/ " .. Toolbar.FormatTime(app:GetLength())
	self:_renderTime()
	local hasDocument = document ~= nil
	self.PlayButton:SetIcon(if preview.Playing then "Pause" else "Play")
	self.PlayButton:SetEnabled(hasDocument)
	self.PlayButton:SetTooltip(if preview.Playing then "Pause (Space)" else "Play (Space)")
	self.SkipStart:SetEnabled(hasDocument)
	self.StopButton:SetEnabled(preview.Active)
	self.SnapButton:Set(app.Snap)
	self.CameraButton:SetActive(preview.CameraLock)
	self.CameraButton:SetEnabled(hasDocument)
	self.ExportButton:SetEnabled(hasDocument)
	local info = preview:GetProviderInfo()
	local moduleName = if info.ModulePath then string.match(info.ModulePath, "([^%.]+)$") else nil
	self.ProviderLabel = if info.Kind == "Game" then "Game: " .. (moduleName or "module") elseif info.Kind == "Fallback" then "Built-in fallback" else "Dialogue: error"
	local providerShort = if info.Kind == "Game" then "Game" elseif info.Kind == "Fallback" then "Fallback" else "Error"
	self.ProviderButton:SetText(if self.Compact then providerShort else self.ProviderLabel)
	self.ProviderButton:SetTooltip("Dialogue: " .. info.Label .. (if info.Error then "\n" .. info.Error else ""))
	local runtime = Runtime.Detect(app.Deps)
	self.RuntimeInfo = runtime
	local runtimeShort = if runtime.Status == "Missing" then "None" else runtime.Version or "?"
	self.RuntimeButton:SetText(if self.Compact then runtimeShort else runtime.Label)
	UI.Set(self.RuntimeDot, "BackgroundColor3", STATUS_COLORS[runtime.Status] or "Dim")
	self.RuntimeButton:SetTooltip(`{runtime.Label} at {runtime.Path}. Bundled: {runtime.Bundled}.`)
end

function Toolbar:_responsive()
	local width = self.Frame.AbsoluteSize.X
	local compact = width < 1080
	local tight = width < 900
	local narrow = width < 840
	if compact ~= self.Compact or tight ~= self.Tight or narrow ~= self.Narrow then
		self.Compact = compact
		self.Tight = tight
		self.Narrow = narrow
		self.CameraButton:SetText(if tight then "" else "Camera")
		self.FitButton.Instance.Visible = not tight
		self.ZoomOut.Instance.Visible = not narrow
		self.ZoomIn.Instance.Visible = not narrow
		self.ExportButton:SetText(if tight then "" else "Export")
		self:Render()
	end
end

function Toolbar:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	if self.ExportFlow and self.ExportFlow.Destroy then
		pcall(self.ExportFlow.Destroy, self.ExportFlow)
	end
	self.Left:Destroy()
	self.Right:Destroy()
end

require(script.Actions)(Toolbar)

return Toolbar
