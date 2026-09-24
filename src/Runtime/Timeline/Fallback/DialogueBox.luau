local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Signal = require(script.Parent.Parent.Util.Signal)

local DialogueBox = {}
DialogueBox.__index = DialogueBox

DialogueBox.Moods = { "Normal", "Shout", "Whisper" }
DialogueBox.Fields = {}
DialogueBox.StartDelay = 0.1
DialogueBox.TypeSpeed = 40
DialogueBox.DisplayOrder = 100

local FAMILY = "rbxasset://fonts/families/GothamSSm.json"
local MIN_HOLD = 2
local WORDS_PER_SECOND = 2.2
local HOLD_BASE = 0.8

local MOODS = {
	Normal = { Color = Color3.fromRGB(245, 245, 245), Size = 22, Weight = Enum.FontWeight.Regular, Style = Enum.FontStyle.Normal },
	Shout = { Color = Color3.fromRGB(255, 128, 116), Size = 26, Weight = Enum.FontWeight.Bold, Style = Enum.FontStyle.Normal },
	Whisper = { Color = Color3.fromRGB(170, 170, 182), Size = 20, Weight = Enum.FontWeight.Regular, Style = Enum.FontStyle.Italic },
}

local Handle = {}
Handle.__index = Handle

local Done = {}
Done.__index = Done

function Done:Wait() end

function Done:Connect(callback)
	task.spawn(callback)
	return { Connected = false, Disconnect = function() end }
end

Done.Once = Done.Connect

local DONE = setmetatable({}, Done)

local function create(className, props, parent)
	local instance = Instance.new(className)
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function graphemes(text)
	local count = 0
	local ok = pcall(function()
		for _ in utf8.graphemes(text) do
			count += 1
		end
	end)
	return if ok then count else utf8.len(text) or #text
end

local function defaultParent(preview)
	if preview or not RunService:IsRunning() then
		return game:GetService("CoreGui")
	end
	local player = Players.LocalPlayer
	return player and player:FindFirstChildOfClass("PlayerGui")
end

local function build(self, options)
	local gui = options.Gui
	if typeof(gui) == "Instance" and gui:IsA("LayerCollector") then
		self.Gui = gui
	else
		self.Gui = create("ScreenGui", {
			Name = "TimelineDialogue",
			Archivable = false,
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			DisplayOrder = DialogueBox.DisplayOrder,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		}, options.GuiParent or defaultParent(options.Preview))
		self.OwnsGui = true
	end
	local box = create("Frame", {
		Name = "TimelineDialogueBox",
		Archivable = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = UDim2.new(0.62, 0, 0.19, 0),
		BackgroundColor3 = Color3.fromRGB(18, 18, 24),
		BackgroundTransparency = 0.12,
		Visible = false,
	}, self.Gui)
	create("UISizeConstraint", { MinSize = Vector2.new(360, 110), MaxSize = Vector2.new(920, 170) }, box)
	create("UICorner", { CornerRadius = UDim.new(0, 14) }, box)
	create("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.8, Thickness = 1.5 }, box)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
	}, box)
	create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, box)
	local portrait = create("ImageLabel", {
		Name = "Portrait",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(44, 44, 56),
		Visible = false,
	}, box)
	create("UIAspectRatioConstraint", { AspectRatio = 1 }, portrait)
	create("UICorner", { CornerRadius = UDim.new(0, 10) }, portrait)
	local content = create("Frame", { Name = "Content", LayoutOrder = 1, Size = UDim2.fromScale(0, 1), BackgroundTransparency = 1 }, box)
	create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }, content)
	local name = create("TextLabel", {
		Name = "Speaker",
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		FontFace = Font.new(FAMILY, Enum.FontWeight.Bold),
		TextSize = 22,
		TextColor3 = Color3.fromRGB(255, 214, 102),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, content)
	local text = create("TextLabel", {
		Name = "Text",
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 1, -32),
		BackgroundTransparency = 1,
		FontFace = Font.new(FAMILY),
		TextSize = 22,
		TextColor3 = MOODS.Normal.Color,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
	}, content)
	self.UI = { Box = box, Portrait = portrait, Name = name, Text = text }
end

local function finish(self, cancelled)
	local typing = self.Typing
	if not typing then
		return
	end
	self.Typing = nil
	local handle = typing.Handle
	handle.Done = true
	handle.Cancelled = cancelled
	handle.Finished:Fire()
end

local function show(self, line)
	local ui = self.UI
	local speaker = if type(line.Speaker) == "table" then line.Speaker else { Name = tostring(line.Speaker or "") }
	local mood = MOODS[line.Mood or "Normal"] or MOODS.Normal
	local text = tostring(line.Text or "")
	ui.Name.Text = tostring(speaker.Name or "")
	ui.Name.Visible = ui.Name.Text ~= ""
	local userId = tonumber(speaker.UserId)
	ui.Portrait.Visible = userId ~= nil and userId > 0
	ui.Portrait.Image = if ui.Portrait.Visible then `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150` else ""
	ui.Text.Text = text
	ui.Text.TextColor3 = mood.Color
	ui.Text.TextSize = mood.Size
	ui.Text.FontFace = Font.new(FAMILY, mood.Weight, mood.Style)
	ui.Box.Visible = true
	return graphemes(text)
end

local function step(self)
	local typing = self.Typing
	if not typing then
		return
	end
	local typed = os.clock() - typing.StartAt
	if typed < 0 then
		return
	end
	local visible = math.floor(typed * typing.Speed) + 1
	if visible >= typing.Count then
		self.UI.Text.MaxVisibleGraphemes = -1
		finish(self, false)
	else
		self.UI.Text.MaxVisibleGraphemes = visible
	end
end

local function setUpConnections(self)
	self.Connections = {}
	self.Connections.Step = RunService.PreRender:Connect(function()
		step(self)
	end)
end

function DialogueBox.new(options)
	if typeof(options) == "Instance" then
		options = { Gui = options }
	end
	local self = setmetatable({}, DialogueBox)
	self.IsOpen = false
	self.Destroyed = false
	build(self, options or {})
	setUpConnections(self)
	return self
end

function DialogueBox:Open()
	if self.IsOpen or self.Destroyed then
		return
	end
	self.IsOpen = true
	self.UI.Box.Visible = true
end

function DialogueBox:Close()
	if self.Destroyed then
		return DONE
	end
	self.IsOpen = false
	finish(self, true)
	local ui = self.UI
	ui.Box.Visible = false
	ui.Text.Text = ""
	ui.Name.Text = ""
	return DONE
end

function DialogueBox:Say(line)
	line = if type(line) == "table" then line else { Text = tostring(line) }
	local handle = setmetatable({ Box = self, Done = false, Cancelled = false, Finished = Signal.new(), Line = line }, Handle)
	if self.Destroyed then
		handle.Done = true
		handle.Cancelled = true
		return handle
	end
	finish(self, true)
	self:Open()
	local count = show(self, line)
	self.UI.Text.MaxVisibleGraphemes = 0
	local speed = if line.TypeSpeed and line.TypeSpeed > 0 then line.TypeSpeed else DialogueBox.TypeSpeed
	self.Typing = { Handle = handle, StartAt = os.clock() + DialogueBox.StartDelay, Count = count, Speed = speed }
	handle.StartDelay = DialogueBox.StartDelay
	if count == 0 then
		finish(self, false)
	end
	return handle
end

function DialogueBox:Render(line, visibleCharacters)
	if self.Destroyed then
		return
	end
	finish(self, true)
	if not line then
		self:Close()
		return
	end
	self.IsOpen = true
	local count = show(self, line)
	local visible = if visibleCharacters then math.floor(visibleCharacters) else count
	self.UI.Text.MaxVisibleGraphemes = if visible >= count then -1 else math.max(visible, 0)
end

function DialogueBox:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	finish(self, true)
	if self.OwnsGui then
		self.Gui:Destroy()
	else
		self.UI.Box:Destroy()
	end
end

function DialogueBox:VisibleCharacters(line, elapsed)
	line = if type(line) == "table" then line else { Text = tostring(line) }
	local delay = if type(line.StartDelay) == "number" then line.StartDelay else DialogueBox.StartDelay
	local typed = elapsed - delay
	if typed < 0 then
		return 0
	end
	local speed = if line.TypeSpeed and line.TypeSpeed > 0 then line.TypeSpeed else DialogueBox.TypeSpeed
	return math.min(math.floor(typed * speed) + 1, graphemes(tostring(line.Text or "")))
end

function Handle:Complete()
	local box = self.Box
	if self.Done or not box.Typing or box.Typing.Handle ~= self then
		return
	end
	box.UI.Text.MaxVisibleGraphemes = -1
	finish(box, false)
end

function DialogueBox.TypingTime(text, typeSpeed)
	local speed = if typeSpeed and typeSpeed > 0 then typeSpeed else DialogueBox.TypeSpeed
	return math.max(graphemes(tostring(text or "")) - 1, 0) / speed
end

function DialogueBox.ReadingTime(text, typeSpeed)
	text = tostring(text or "")
	local words = 0
	for _ in string.gmatch(text, "%S+") do
		words += 1
	end
	return DialogueBox.StartDelay + DialogueBox.TypingTime(text, typeSpeed) + math.max(MIN_HOLD, words / WORDS_PER_SECOND + HOLD_BASE)
end

return DialogueBox
