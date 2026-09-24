local UI = require(script.Parent.Parent.UI)
local Widgets = require(script.Parent.Widgets)
local KeyMath = require(script.Parent.KeyMath)

local KeyPanel = {}
KeyPanel.__index = KeyPanel

local ROW = 22

local function format(seconds)
	return string.format("%.2fs", seconds)
end

local function easingText(key)
	local easing = key:GetAttribute("Easing")
	if not easing or easing == "Linear" then
		return "Linear"
	end
	return easing .. " " .. tostring(key:GetAttribute("EasingDirection") or "InOut")
end

function KeyPanel.new(tool, parent)
	local self = setmetatable({}, KeyPanel)
	self.Tool = tool
	self.Root = UI.Create("Frame", { Name = "KeyTool", Parent = parent, Size = UDim2.fromScale(1, 1) })
	self.Empty = Widgets.Empty(self.Root, "No keys to edit", "Select a Camera, Move or Attach clip. Its keys show in the viewport; click a marker to select a key.")
	local page = Widgets.Page(self.Root)
	self.Page = page
	self.Title = Widgets.Title(page, "", 1)
	self.Status = Widgets.Caption(page, "", 2)
	local modes = Widgets.Row(page, 3)
	self.ModeControl = Widgets.Segmented(modes, {
		{ Value = "Move", Text = "Move", Tooltip = "Drag arrows along the key's own axes" },
		{ Value = "Rotate", Text = "Rotate", Tooltip = "Drag rings to turn the key" },
	}, tool.Mode, function(mode)
		tool:SetMode(mode)
	end, { LayoutOrder = 1 })
	self.PathButton = Widgets.Button(modes, "Path", function()
		tool:SetShowPath(not tool.ShowPath)
	end, { LayoutOrder = 2, Tooltip = "Show the key path in the viewport" })
	self.CameraRow = Widgets.Wrap(page, 4)
	Widgets.Button(self.CameraRow, "Add key from view at playhead", function()
		tool:AddFromView()
	end, { Icon = "Camera", Style = "Primary", LayoutOrder = 1, Tooltip = "Adds (or updates) a key at the playhead from the view in the viewport" })
	self.ViewButton = Widgets.Button(self.CameraRow, "View through key", function()
		tool:ViewThrough()
	end, { Icon = "Eye", LayoutOrder = 2 })
	self.UpdateButton = Widgets.Button(self.CameraRow, "Update key from view", function()
		tool:UpdateFromView()
	end, { LayoutOrder = 3 })
	self.MoveRow = Widgets.Wrap(page, 5)
	Widgets.Button(self.MoveRow, "Add key from actor's current pivot", function()
		tool:AddFromActor()
	end, { Icon = "Actor", Style = "Primary", LayoutOrder = 1, Tooltip = "Adds (or updates) a key at the playhead where the actor stands in the preview; then drag its arrows" })
	Widgets.Button(self.MoveRow, "Select actor", function()
		tool:SelectActor()
	end, { LayoutOrder = 2, Tooltip = "Selects the actor's preview copy so you can move it with Studio's tools; the real model is never moved" })
	self.AttachRow = Widgets.Wrap(page, 6)
	Widgets.Button(self.AttachRow, "Offset from prop's pivot", function()
		tool:OffsetFromProp()
	end, { LayoutOrder = 1, Tooltip = "Sets the offset so the prop stays where its preview copy is now" })
	Widgets.Button(self.AttachRow, "Reset offset", function()
		tool:ResetOffset()
	end, { LayoutOrder = 2 })
	self.KeyRow = Widgets.Row(page, 7)
	self.FovField = UI.NumberField({
		Parent = self.KeyRow,
		LayoutOrder = 1,
		Label = "FOV",
		LabelWidth = 30,
		Min = 1,
		Max = 120,
		Step = 1,
		Decimals = 0,
		Size = UDim2.fromOffset(110, Widgets.Height),
		OnCommit = function(value)
			tool:SetFov(value)
		end,
	})
	self.DeleteButton = Widgets.Button(self.KeyRow, "Delete key", function()
		tool:DeleteKey()
	end, { Style = "Danger", LayoutOrder = 2 })
	self.ListCaption = Widgets.Caption(page, "Keys", 8)
	self.List = UI.Create("Frame", {
		Parent = page,
		LayoutOrder = 9,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		List = { Padding = 1 },
	})
	self.Rows = {}
	return self
end

function KeyPanel:_row(index)
	local row = self.Rows[index]
	if row then
		row.Button.Visible = true
		return row
	end
	local button = UI.Create("TextButton", {
		Parent = self.List,
		LayoutOrder = index,
		Text = "",
		Size = UDim2.new(1, 0, 0, ROW),
		BackgroundColor3 = "Hover",
		BackgroundTransparency = 1,
		Corner = 3,
	})
	local label = UI.Label({ Parent = button, Text = "", TextSize = 13, Position = UDim2.fromOffset(8, 0), Size = UDim2.new(0.55, -8, 1, 0) })
	local hint = UI.Label({
		Parent = button,
		Text = "",
		TextSize = 12,
		TextColor3 = "Dim",
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 0),
		Size = UDim2.new(0.45, 0, 1, 0),
	})
	row = { Button = button, Label = label, Hint = hint }
	button.Activated:Connect(function()
		if row.Key then
			self.Tool:SelectKey(row.Key)
		end
	end)
	self.Rows[index] = row
	return row
end

function KeyPanel:Refresh()
	local tool = self.Tool
	local clip, kind = tool.Clip, tool.Kind
	self.Empty.Instance.Visible = clip == nil
	self.Page.Visible = clip ~= nil
	self.ModeControl:Set(tool.Mode)
	self.PathButton:SetActive(tool.ShowPath)
	if not clip then
		return
	end
	local actor = clip.Parent:GetAttribute("Actor")
	self.Title.Text = if actor and actor ~= "" then `{actor} · {clip.Name}` else clip.Name
	self.Status.Text = tool:StatusText()
	self.CameraRow.Visible = kind == "Camera"
	self.MoveRow.Visible = kind == "Move"
	self.AttachRow.Visible = kind == "Attach"
	local key = tool.Key
	self.ViewButton:SetEnabled(key ~= nil)
	self.UpdateButton:SetEnabled(key ~= nil)
	self.KeyRow.Visible = kind ~= "Attach"
	self.FovField.Instance.Visible = kind == "Camera"
	self.FovField:SetEnabled(key ~= nil)
	if key then
		self.FovField:Set(key:GetAttribute("FOV") or 70)
	end
	self.DeleteButton:SetEnabled(key ~= nil)
	self.ListCaption.Visible = kind ~= "Attach"
	self.List.Visible = kind ~= "Attach"
	local keys = if kind == "Attach" then {} else tool.Keys
	self.ListCaption.Text = `{#keys} key{if #keys == 1 then "" else "s"} · click a row or a marker to select`
	for index, entry in keys do
		local row = self:_row(index)
		row.Key = entry
		local time = KeyMath.KeyTime(entry)
		row.Label.Text = `{index}   {format(time)}`
		row.Hint.Text = easingText(entry) .. (if kind == "Camera" then ` · {entry:GetAttribute("FOV") or 70}°` else "")
		local selected = entry == key
		UI.Set(row.Button, "BackgroundColor3", if selected then "AccentSoft" else "Hover")
		row.Button.BackgroundTransparency = if selected then 0 else 1
	end
	for index = #keys + 1, #self.Rows do
		self.Rows[index].Button.Visible = false
		self.Rows[index].Key = nil
	end
end

function KeyPanel:Destroy()
	self.Root:Destroy()
end

return KeyPanel
