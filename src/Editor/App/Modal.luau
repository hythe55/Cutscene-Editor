local UI = require(script.Parent.Parent.UI)
local Signal = require(script.Parent.Parent.Signal)

local Modal = {}

function Modal.Show(app, props)
	props = props or {}
	local layer = app.Shell and app.Shell.Layer
	if not layer then
		return nil
	end
	local buttons = props.Buttons or { "OK" }
	local primary = props.Primary or buttons[#buttons]
	local done = Signal.new()
	local finished = false
	local input
	local scrim = UI.Create("TextButton", {
		Name = "ModalScrim",
		Parent = layer,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = "Scrim",
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 400,
	})
	local card = UI.Create("Frame", {
		Name = "ModalCard",
		Parent = scrim,
		BackgroundColor3 = "Raised",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(props.Width or 380, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 401,
		Corner = 8,
		Stroke = { Color = "Border", Thickness = 1 },
		Padding = { X = 18, Top = 16, Bottom = 14 },
		List = { Padding = 10 },
	})
	UI.Create("UISizeConstraint", { Parent = card, MaxSize = Vector2.new(math.max(layer.AbsoluteSize.X - 32, 200), math.huge) })
	if props.Title then
		UI.Create("TextLabel", {
			Parent = card,
			LayoutOrder = 1,
			Text = props.Title,
			Font = "Bold",
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 22),
			ZIndex = 402,
		})
	end
	if props.Text then
		UI.Create("TextLabel", {
			Parent = card,
			LayoutOrder = 2,
			Text = props.Text,
			TextColor3 = "SubText",
			TextWrapped = true,
			RichText = props.RichText == true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 402,
		})
	end
	if props.Content then
		props.Content.LayoutOrder = 3
		props.Content.Parent = card
	end
	local function finish(choice, destroying)
		if finished then
			return
		end
		finished = true
		local text = input and input.Text or nil
		if not destroying then
			scrim:Destroy()
		end
		done:Fire(choice, text)
	end
	scrim.Destroying:Connect(function()
		finish(nil, true)
	end)
	if props.Input then
		local holder = UI.Create("Frame", {
			Parent = card,
			LayoutOrder = 4,
			BackgroundColor3 = "Sunken",
			Size = UDim2.new(1, 0, 0, if props.Input.MultiLine then 72 else 30),
			ZIndex = 402,
			Corner = 4,
			Stroke = { Color = "Outline", Thickness = 1 },
		})
		input = UI.Create("TextBox", {
			Parent = holder,
			Text = props.Input.Value or "",
			PlaceholderText = props.Input.Placeholder or "",
			MultiLine = props.Input.MultiLine == true,
			TextWrapped = props.Input.MultiLine == true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = if props.Input.MultiLine then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center,
			Size = UDim2.new(1, -16, 1, -8),
			Position = UDim2.fromOffset(8, 4),
			ZIndex = 403,
		})
		input.FocusLost:Connect(function(enter)
			if enter and not props.Input.MultiLine then
				finish(primary)
			end
		end)
		task.defer(function()
			if input.Parent then
				input:CaptureFocus()
				input.CursorPosition = #input.Text + 1
				input.SelectionStart = 1
			end
		end)
	end
	local row = UI.Create("Frame", {
		Parent = card,
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 34),
		Padding = { Top = 6 },
		ZIndex = 402,
		List = { FillDirection = "Horizontal", Padding = 8, HorizontalAlignment = Enum.HorizontalAlignment.Right },
	})
	for index, name in buttons do
		local button = UI.Button({
			Parent = row,
			Text = name,
			LayoutOrder = index,
			Height = 28,
			Style = if name == props.Danger then "Danger" elseif name == primary then "Primary" else "Default",
			OnClick = function()
				finish(name)
			end,
		})
		for _, descendant in button.Instance:GetDescendants() do
			if descendant:IsA("GuiObject") then
				descendant.ZIndex = 404
			end
		end
		button.Instance.ZIndex = 403
	end
	local choice, text = done:Wait()
	done:Destroy()
	return choice, text
end

return Modal
