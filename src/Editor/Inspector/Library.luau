local UI = require(script.Parent.Parent.UI)
local Popup = require(script.Parent.Parent.UI.Popup)
local Context = require(script.Parent.Context)
local Audition = require(script.Parent.Audition)

local Library = {}

local ROW = 28
local MAX_ROWS = 10
local WIDTH = 320

local function detail(instance)
	if instance:IsA("Sound") then
		return if instance.TimeLength > 0 then string.format("%.1f s", instance.TimeLength) else "…"
	end
	local emitters = 0
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			emitters += 1
		end
	end
	return if emitters > 0 then `{emitters} emitter{if emitters == 1 then "" else "s"}` else instance.ClassName
end

local function row(list, index, item, pick, sounds, connections)
	local button = UI.Create("TextButton", {
		Name = item.Name,
		Parent = list,
		LayoutOrder = index,
		Text = "",
		BackgroundColor3 = "Hover",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, ROW),
		Corner = 3,
	})
	local right = if sounds then 34 else 8
	UI.Create("TextLabel", {
		Parent = button,
		Text = item.Name,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(0.62, -8, 1, 0),
	})
	UI.Create("TextLabel", {
		Parent = button,
		Text = (if item.Group then item.Group .. " · " else "") .. detail(item.Instance),
		TextSize = 11,
		TextColor3 = "Dim",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -right, 0, 0),
		Size = UDim2.new(0.38, -right + 8, 1, 0),
	})
	if sounds then
		local play
		play = UI.IconButton({
			Parent = button,
			Icon = "Play",
			Size = 22,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Tooltip = "Listen",
			OnClick = function()
				if Audition.IsPlaying(item.Instance) then
					Audition.Stop()
				else
					Audition.Play(item.Instance, { Duration = 8 })
				end
			end,
		})
		table.insert(connections, Audition.Changed:Connect(function()
			if button.Parent then
				play:SetIcon(if Audition.IsPlaying(item.Instance) then "Stop" else "Play")
			end
		end))
	end
	button.MouseEnter:Connect(function()
		button.BackgroundTransparency = 0
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundTransparency = 1
	end)
	button.Activated:Connect(function()
		pick(item.Instance)
	end)
	return button
end

function Library.Pick(anchor, options)
	local category = options.Category
	local items, path = Context.LibraryItems(category)
	local sounds = category == "Sounds"
	local listHeight = math.max(math.min(#items, MAX_ROWS), 2) * ROW + 8
	local card = Popup.Card({
		Name = "LibraryPicker",
		Size = UDim2.fromOffset(WIDTH, listHeight + 74),
	})
	UI.Create("TextLabel", {
		Parent = card,
		Text = options.Title or ("Replace from " .. category),
		Font = "Bold",
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 18),
	})
	UI.Create("TextLabel", {
		Parent = card,
		Text = path,
		TextSize = 11,
		TextColor3 = "Dim",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(10, 22),
		Size = UDim2.new(1, -20, 0, 14),
	})
	local box = UI.Create("TextBox", {
		Name = "Search",
		Parent = card,
		Text = "",
		PlaceholderText = `Search {#items} item{if #items == 1 then "" else "s"}`,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = "Sunken",
		Position = UDim2.fromOffset(6, 40),
		Size = UDim2.new(1, -12, 0, 26),
		Corner = 3,
		Padding = { Left = 8, Right = 8 },
	})
	local list = UI.Create("ScrollingFrame", {
		Name = "List",
		Parent = card,
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 1, -70),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = "ScrollBar",
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Padding = 4,
		List = { Padding = 0 },
	})
	local handle
	local function pick(instance)
		Audition.Stop()
		handle.Close()
		options.OnPick(instance)
	end
	local rows, connections = {}, {}
	for index, item in items do
		rows[index] = { Button = row(list, index, item, pick, sounds, connections), Item = item }
	end
	card.Destroying:Connect(function()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
	end)
	if #items == 0 then
		UI.Create("TextLabel", {
			Parent = list,
			Text = `Nothing found in {path}. Set the AssetLibrary attribute on ReplicatedStorage.Cutscenes to use another library folder.`,
			TextSize = 12,
			TextColor3 = "Dim",
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -12, 0, 0),
			Position = UDim2.fromOffset(6, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		})
	end
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local query = string.lower(box.Text)
		for _, entry in rows do
			local haystack = string.lower(entry.Item.Name .. " " .. (entry.Item.Group or ""))
			entry.Button.Visible = query == "" or string.find(haystack, query, 1, true) ~= nil
		end
	end)
	box.FocusLost:Connect(function(enter)
		if not enter then
			return
		end
		for _, entry in rows do
			if entry.Button.Visible then
				pick(entry.Item.Instance)
				return
			end
		end
	end)
	handle = Popup.Open(card, {
		Anchor = anchor,
		OnClose = function()
			if sounds then
				Audition.Stop()
			end
		end,
	})
	task.defer(function()
		if box.Parent then
			box:CaptureFocus()
		end
	end)
	return handle, card
end

return Library
