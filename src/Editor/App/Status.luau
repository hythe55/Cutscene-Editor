local UI = require(script.Parent.Parent.UI)

local Status = {}
Status.__index = Status

local COLORS = { Info = "Accent", Warn = "Warning", Error = "Error", Success = "Success" }
local HOLD = { Info = 6, Success = 6, Warn = 10, Error = 14 }

local function formatTime(t)
	local minutes = math.floor(t / 60)
	return string.format("%d:%05.2f", minutes, t - minutes * 60)
end

local function badge(parent, order, text, color)
	local frame = UI.Create("Frame", {
		Parent = parent,
		LayoutOrder = order,
		BackgroundColor3 = UI.Color("Window", color, 0.2),
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		Corner = UDim.new(1, 0),
		Padding = { Left = 8, Right = 8 },
		Visible = false,
	})
	local label = UI.Create("TextLabel", {
		Parent = frame,
		Text = text,
		Font = "Medium",
		TextSize = 12,
		TextColor3 = color,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
	})
	return frame, label
end

function Status.new(app, frame)
	local self = setmetatable({}, Status)
	self.App = app
	self.Frame = frame
	self.Connections = {}
	self.Token = 0
	local left = UI.Create("Frame", {
		Name = "Message",
		Parent = frame,
		Size = UDim2.new(0.6, 0, 1, 0),
		Padding = { Left = 10 },
		List = { FillDirection = "Horizontal", Padding = 7, VerticalAlignment = Enum.VerticalAlignment.Center },
	})
	self.Dot = UI.Create("Frame", {
		Parent = left,
		LayoutOrder = 1,
		BackgroundColor3 = "Dim",
		Size = UDim2.fromOffset(6, 6),
		Corner = UDim.new(1, 0),
	})
	self.Label = UI.Create("TextLabel", {
		Parent = left,
		LayoutOrder = 2,
		Text = "Ready",
		TextSize = 12,
		TextColor3 = "SubText",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -20, 1, 0),
	})
	local right = UI.Create("Frame", {
		Name = "State",
		Parent = frame,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.4, 0, 1, 0),
		Padding = { Right = 10 },
		List = {
			FillDirection = "Horizontal",
			Padding = 10,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		},
	})
	self.GameplayBadge = badge(right, 1, "Gameplay camera", "Warning")
	self.LockBadge = badge(right, 2, "Viewing through cutscene camera", "Accent")
	self.PreviewBadge, self.PreviewLabel = badge(right, 3, "Preview", "Success")
	self.Length = UI.Create("TextLabel", {
		Parent = right,
		LayoutOrder = 4,
		Text = "",
		TextSize = 12,
		TextColor3 = "Dim",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
	})
	local shell = app.Shell
	self.SideToggle = UI.IconButton({
		Name = "SideToggle",
		Parent = right,
		LayoutOrder = 5,
		Icon = "Panel",
		Size = 20,
		Toggle = true,
		Value = not shell.SideCollapsed,
		Tooltip = "Show or hide the side panel (inspector, script, keys, pose)",
		OnChanged = function(value)
			shell:SetSideCollapsed(not value)
		end,
	})
	shell.SideToggle = self.SideToggle
	local signals = app.Signals
	for _, name in { "PreviewChanged", "DocumentChanged" } do
		table.insert(self.Connections, signals[name]:Connect(function()
			self:Render()
		end))
	end
	self:Render()
	return self
end

function Status:Render()
	local app = self.App
	local preview = app.Preview
	local active = preview and preview.Active
	self.PreviewBadge.Visible = active == true
	if active then
		self.PreviewLabel.Text = if preview.Playing then "Playing" elseif preview.Suspended then "Updating" else "Preview paused"
	end
	local engaged = preview and preview.CameraLock and active
	local gap = engaged and preview:InCameraGap()
	self.GameplayBadge.Visible = gap == true
	self.LockBadge.Visible = engaged == true and not gap
	self.Length.Text = if app.Document then "Length " .. formatTime(app:GetLength()) else ""
end

function Status:Notify(text, kind)
	self.Token += 1
	local token = self.Token
	self.Label.Text = text
	UI.Set(self.Dot, "BackgroundColor3", COLORS[kind] or "Accent")
	UI.Set(self.Label, "TextColor3", if kind == "Error" then "Error" elseif kind == "Warn" then "Warning" else "Text")
	if kind == "Error" or kind == "Warn" then
		print(`CutsceneEditor: {text}`)
	end
	task.delay(HOLD[kind] or 6, function()
		if self.Token == token and self.Label.Parent then
			self.Label.Text = "Ready"
			UI.Set(self.Dot, "BackgroundColor3", "Dim")
			UI.Set(self.Label, "TextColor3", "SubText")
		end
	end)
end

function Status:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
end

return Status
