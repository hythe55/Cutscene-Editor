local TextService = game:GetService("TextService")

local UI = require(script.Parent)
local Icons = require(script.Parent.Icons)
local Popup = require(script.Parent.Popup)

local Menu = {}

local ITEM_HEIGHT = 26
local MAX_HEIGHT = 360

local function textWidth(text, size)
	local ok, bounds = pcall(TextService.GetTextSize, TextService, text, size, Enum.Font.BuilderSans, Vector2.new(1000, 100))
	return if ok then bounds.X else #text * 7
end

local function row(parent, item, order, close)
	if item.Separator then
		UI.Create("Frame", {
			Parent = parent,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 9),
		}, {
			UI.Create("Frame", {
				BackgroundColor3 = "Divider",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 6, 0.5, 0),
				Size = UDim2.new(1, -12, 0, 1),
			}),
		})
		return
	end
	if item.Header then
		UI.Create("TextLabel", {
			Parent = parent,
			LayoutOrder = order,
			Text = item.Text,
			TextSize = 11,
			Font = "Bold",
			TextColor3 = "Dim",
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, 0, 0, 22),
			Padding = { Left = 10, Right = 10, Top = 4 },
		})
		return
	end
	local info = item.Info == true
	local enabled = item.Enabled ~= false and not info
	local button = UI.Create("TextButton", {
		Parent = parent,
		LayoutOrder = order,
		Text = "",
		BackgroundColor3 = "Hover",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, ITEM_HEIGHT),
		Corner = 4,
	})
	local left = 28
	if item.Checked then
		local holder = UI.Create("Frame", { Parent = button, Position = UDim2.fromOffset(6, 5), Size = UDim2.fromOffset(16, 16) })
		Icons.Draw("Check", holder, "Accent", 14)
	elseif item.Color then
		UI.Create("Frame", {
			Parent = button,
			BackgroundColor3 = item.Color,
			Position = UDim2.fromOffset(10, 9),
			Size = UDim2.fromOffset(8, 8),
			Corner = 2,
		})
	elseif item.Icon then
		local holder = UI.Create("Frame", { Parent = button, Position = UDim2.fromOffset(6, 5), Size = UDim2.fromOffset(16, 16) })
		Icons.Draw(item.Icon, holder, item.IconColor or (if enabled or info then "SubText" else "Faint"), 16)
	end
	local label = UI.Create("TextLabel", {
		Parent = button,
		Text = item.Text or "",
		TextSize = 13,
		TextColor3 = if info then item.TextColor or "SubText" elseif not enabled then "Faint" elseif item.Danger then "Error" else "Text",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(left, 0),
		Size = UDim2.new(1, -left - 10, 1, 0),
	})
	if item.Hint then
		local hintWidth = math.ceil(textWidth(item.Hint, 12)) + 2
		UI.Create("TextLabel", {
			Parent = button,
			Text = item.Hint,
			TextSize = 12,
			Font = if info then "Medium" else nil,
			TextColor3 = if info then "Text" else "Dim",
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.new(0, hintWidth, 1, 0),
		})
		label.Size = UDim2.new(1, -left - hintWidth - 18, 1, 0)
	end
	if item.Tooltip or (info and item.Text) then
		UI.Tooltip(button, item.Tooltip or item.Text)
	end
	button.MouseEnter:Connect(function()
		if enabled then
			button.BackgroundTransparency = 0
		end
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundTransparency = 1
	end)
	button.Activated:Connect(function()
		if not enabled then
			return
		end
		close()
		if item.OnClick then
			task.spawn(item.OnClick, item)
		end
	end)
end

function Menu.Show(items, options)
	options = options or {}
	local width = options.Width or 0
	if width == 0 then
		for _, item in items do
			if item.Text and not item.Separator then
				local extra = if item.Hint then textWidth(item.Hint, 12) + 24 else 0
				width = math.max(width, textWidth(item.Text, if item.Header then 11 else 13) + 48 + extra)
			end
		end
		width = math.clamp(width, options.MinWidth or 180, options.MaxWidth or 420)
	end
	local height = 8
	for _, item in items do
		height += if item.Separator then 9 elseif item.Header then 22 else ITEM_HEIGHT
	end
	local card = Popup.Card({
		Name = "Menu",
		Size = UDim2.fromOffset(width, math.min(height, MAX_HEIGHT)),
	})
	local list = UI.Create("ScrollingFrame", {
		Parent = card,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.fromOffset(0, height - 8),
		ScrollBarThickness = if height > MAX_HEIGHT then 4 else 0,
		ScrollBarImageColor3 = "ScrollBar",
		ScrollingDirection = Enum.ScrollingDirection.Y,
		BorderSizePixel = 0,
		Padding = 4,
		List = { Padding = 0 },
	})
	local handle
	local function close()
		if handle then
			handle.Close()
		end
	end
	for index, item in items do
		row(list, item, index, close)
	end
	handle = Popup.Open(card, {
		Anchor = options.Anchor,
		Position = options.Position,
		AlignRight = options.AlignRight,
		Align = options.Align,
		OnClose = options.OnClose,
	})
	return handle
end

return Menu
