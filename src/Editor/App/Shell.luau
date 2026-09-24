local UI = require(script.Parent.Parent.UI)

local Shell = {}
Shell.__index = Shell

Shell.Tabs = {
	{ Name = "Inspector", Text = "Inspector" },
	{ Name = "Script", Text = "Script" },
	{ Name = "Keys", Text = "Keys" },
	{ Name = "Pose", Text = "Pose" },
}

local MIN_TIMELINE = 360
local MIN_SIDE = 240
local MAX_SIDE = 520
local NARROW = 900

local function tabButton(shell, tab, parent, order)
	local button = UI.Create("TextButton", {
		Name = tab.Name,
		Parent = parent,
		Text = tab.Text,
		Font = "Medium",
		TextSize = 13,
		LayoutOrder = order,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Padding = { Left = 10, Right = 10 },
	})
	local underline = UI.Create("Frame", {
		Name = "Underline",
		Parent = button,
		BackgroundColor3 = "Accent",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, -10, 1, 0),
		Size = UDim2.new(1, 20, 0, 2),
		Visible = false,
	})
	local hover = false
	local function render()
		local active = shell.ActiveTab == tab.Name
		underline.Visible = active
		UI.Set(button, "TextColor3", if active then "Text" elseif hover then "SubText" else "Dim")
	end
	button.MouseEnter:Connect(function()
		hover = true
		render()
	end)
	button.MouseLeave:Connect(function()
		hover = false
		render()
	end)
	button.Activated:Connect(function()
		shell:ShowTab(tab.Name)
	end)
	shell.TabRenderers[tab.Name] = render
	return button
end

function Shell.new(app, container)
	local self = setmetatable({}, Shell)
	self.App = app
	self.Connections = {}
	self.TabRenderers = {}
	self.Pages = {}
	self.SideWidth = app:GetSetting("SideWidth")
	self.SideCollapsed = app:GetSetting("SideCollapsed", false) == true
	local root = UI.Create("Frame", {
		Name = "CutsceneEditor",
		BackgroundColor3 = "Window",
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Parent = container,
	})
	self.Root = root
	self.Toolbar = UI.Create("Frame", {
		Name = "Toolbar",
		Parent = root,
		BackgroundColor3 = "Surface",
		Size = UDim2.new(1, 0, 0, app.ToolbarHeight),
		ZIndex = 3,
	})
	UI.Divider({ Parent = self.Toolbar, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), BackgroundColor3 = "Border" })
	local body = UI.Create("Frame", {
		Name = "Body",
		Parent = root,
		Position = UDim2.fromOffset(0, app.ToolbarHeight),
		Size = UDim2.new(1, 0, 1, -(app.ToolbarHeight + app.StatusHeight)),
		BackgroundColor3 = "Window",
	})
	self.Body = body
	self.Headers = UI.Create("Frame", { Name = "Headers", Parent = body, BackgroundColor3 = "Panel", ClipsDescendants = true })
	self.HeadersDivider = UI.Divider({ Parent = body, Vertical = true, BackgroundColor3 = "Border" })
	self.Timeline = UI.Create("Frame", { Name = "Timeline", Parent = body, BackgroundColor3 = "Lane", ClipsDescendants = true })
	self.SideDivider = UI.Divider({ Parent = body, Vertical = true, BackgroundColor3 = "Border", ZIndex = 2 })
	self.Side = UI.Create("Frame", { Name = "Side", Parent = body, BackgroundColor3 = "Panel", ClipsDescendants = true })
	local tabBar = UI.Create("Frame", {
		Name = "Tabs",
		Parent = self.Side,
		BackgroundColor3 = "Surface",
		Size = UDim2.new(1, 0, 0, app.TabHeight),
		Padding = { Left = 4 },
		List = { FillDirection = "Horizontal", Padding = 0 },
	})
	UI.Divider({ Parent = self.Side, Position = UDim2.fromOffset(0, app.TabHeight - 1), BackgroundColor3 = "Border", ZIndex = 2 })
	for index, tab in Shell.Tabs do
		tabButton(self, tab, tabBar, index)
		self.Pages[tab.Name] = UI.Create("Frame", {
			Name = tab.Name .. "Page",
			Parent = self.Side,
			Position = UDim2.fromOffset(0, app.TabHeight),
			Size = UDim2.new(1, 0, 1, -app.TabHeight),
			Visible = false,
			ClipsDescendants = true,
		})
	end
	self.Status = UI.Create("Frame", {
		Name = "Status",
		Parent = root,
		BackgroundColor3 = "Surface",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, app.StatusHeight),
	})
	UI.Divider({ Parent = self.Status, BackgroundColor3 = "Border" })
	self:_buildEmpty(body)
	self:_buildSplitter(body)
	self.Layer = UI.Create("Frame", { Name = "Layer", Parent = root, Size = UDim2.fromScale(1, 1), ZIndex = 50 })
	table.insert(self.Connections, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:Layout()
	end))
	self:Layout()
	self:ShowTab(app:GetSetting("Tab", "Inspector"))
	return self
end

function Shell:_buildEmpty(body)
	local app = self.App
	local empty = UI.Create("Frame", {
		Name = "Empty",
		Parent = body,
		BackgroundColor3 = "Window",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Visible = false,
	})
	local card = UI.Create("Frame", {
		Name = "Card",
		Parent = empty,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		List = { Padding = 10, HorizontalAlignment = Enum.HorizontalAlignment.Center },
	})
	local badge = UI.Create("Frame", {
		Parent = card,
		LayoutOrder = 1,
		BackgroundColor3 = "AccentSoft",
		Size = UDim2.fromOffset(44, 44),
		Corner = UDim.new(1, 0),
	})
	UI.Icons.Draw("Film", badge, "Accent", 20)
	UI.Create("TextLabel", {
		Parent = card,
		LayoutOrder = 2,
		Text = "No cutscene open",
		Font = "Bold",
		TextSize = 18,
		Size = UDim2.new(1, 0, 0, 24),
	})
	self.EmptyText = UI.Create("TextLabel", {
		Parent = card,
		LayoutOrder = 3,
		Text = "Timeline cutscenes live in ReplicatedStorage.Cutscenes. Create one to start adding actors, cameras and dialogue.",
		TextColor3 = "SubText",
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	local actions = UI.Create("Frame", {
		Parent = card,
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 40),
		Padding = { Top = 8 },
		List = { FillDirection = "Horizontal", Padding = 8, HorizontalAlignment = Enum.HorizontalAlignment.Center },
	})
	UI.Button({
		Parent = actions,
		Text = "Create cutscene",
		Icon = "Plus",
		Style = "Primary",
		Height = 30,
		OnClick = function()
			Shell.PromptCreate(app)
		end,
	})
	self.Empty = empty
end

function Shell.PromptCreate(app)
	task.spawn(function()
		local choice, name = app:Modal({
			Title = "New cutscene",
			Text = "The cutscene is created as a Folder in ReplicatedStorage.Cutscenes.",
			Input = { Placeholder = "Cutscene name", Value = "Cutscene" },
			Buttons = { "Cancel", "Create" },
			Primary = "Create",
		})
		if choice == "Create" and name and name ~= "" then
			app:CreateCutscene(name)
		end
	end)
end

function Shell:_buildSplitter(body)
	local handle = UI.Create("TextButton", {
		Name = "SideSplitter",
		Parent = body,
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0, 7, 1, 0),
		ZIndex = 5,
	})
	self.Splitter = handle
	local dragging = false
	handle.MouseButton1Down:Connect(function(x)
		dragging = true
		local startX = x
		local startWidth = self.SideWidthApplied
		local capture = UI.Create("TextButton", {
			Name = "SplitterCapture",
			Parent = self.Layer,
			Text = "",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 300,
		})
		local function finish()
			if not dragging then
				return
			end
			dragging = false
			capture:Destroy()
			self.App:SetSetting("SideWidth", self.SideWidth)
		end
		capture.MouseMoved:Connect(function(mx)
			self.SideWidth = startWidth - (mx - startX)
			self:Layout()
		end)
		capture.MouseButton1Up:Connect(finish)
		capture.MouseLeave:Connect(finish)
	end)
end

function Shell:Layout()
	local app = self.App
	local width = self.Root.AbsoluteSize.X
	local narrow = width < NARROW
	local headerWidth = math.floor(math.clamp(width * 0.18, if narrow then 150 else 180, 240))
	local collapsed = self.SideCollapsed == true
	local side = self.SideWidth or (if narrow then MIN_SIDE else math.clamp(width * 0.27, 270, 360))
	side = math.floor(math.clamp(side, MIN_SIDE, math.max(MIN_SIDE, math.min(MAX_SIDE, width - headerWidth - MIN_TIMELINE))))
	self.SideWidthApplied = side
	self.HeaderWidth = headerWidth
	self.Headers.Size = UDim2.new(0, headerWidth, 1, 0)
	self.HeadersDivider.Position = UDim2.fromOffset(headerWidth, 0)
	self.Timeline.Position = UDim2.fromOffset(headerWidth + 1, 0)
	self.Side.Visible = not collapsed
	self.SideDivider.Visible = not collapsed
	self.Splitter.Visible = not collapsed
	if collapsed then
		self.Timeline.Size = UDim2.new(1, -(headerWidth + 1), 1, 0)
	else
		self.Timeline.Size = UDim2.new(1, -(headerWidth + side + 2), 1, 0)
	end
	self.SideDivider.Position = UDim2.new(1, -side - 1, 0, 0)
	self.Splitter.Position = UDim2.new(1, -side - 1, 0, 0)
	self.Side.Position = UDim2.new(1, -side, 0, 0)
	self.Side.Size = UDim2.new(0, side, 1, 0)
	if app.Signals and app.Document then
		app:SetView({ ScrollY = app.ScrollY })
	end
end

function Shell:TimelineWidth()
	return self.Timeline.AbsoluteSize.X
end

function Shell:LaneViewportHeight()
	return math.max(self.Timeline.AbsoluteSize.Y - self.App.RulerHeight, 0)
end

function Shell:SetSideCollapsed(collapsed)
	collapsed = collapsed == true
	if self.SideToggle then
		self.SideToggle:Set(not collapsed)
	end
	if collapsed == self.SideCollapsed then
		return
	end
	self.SideCollapsed = collapsed
	self.App:SetSetting("SideCollapsed", collapsed)
	self:Layout()
end

function Shell:ShowTab(name, reveal)
	if not self.Pages[name] then
		name = "Inspector"
	end
	if reveal and self.SideCollapsed then
		self:SetSideCollapsed(false)
	end
	self.ActiveTab = name
	for tabName, page in self.Pages do
		page.Visible = tabName == name
	end
	for _, render in self.TabRenderers do
		render()
	end
	self.App:SetSetting("Tab", name)
	return self.Pages[name]
end

function Shell:Refresh()
	local app = self.App
	self.Empty.Visible = app.Document == nil
end

function Shell:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Root:Destroy()
end

return Shell
