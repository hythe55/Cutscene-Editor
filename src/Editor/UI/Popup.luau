local UI = require(script.Parent)

local Popup = {}

local open = {}

local function layerOf(options)
	return options.Layer or UI.Layer
end

local function place(content, layer, options)
	local layerPosition, layerSize = layer.AbsolutePosition, layer.AbsoluteSize
	local size = content.AbsoluteSize
	local margin = 4
	local x, y
	local anchor = options.Anchor
	if anchor then
		local position, anchorSize = anchor.AbsolutePosition, anchor.AbsoluteSize
		if options.Align == "Right" then
			x = position.X + anchorSize.X + 2
			y = position.Y
		elseif options.Align == "Above" then
			x = position.X
			y = position.Y - size.Y - margin
		else
			x = position.X
			y = position.Y + anchorSize.Y + margin
			if y + size.Y > layerPosition.Y + layerSize.Y - margin then
				y = position.Y - size.Y - margin
			end
		end
		if options.AlignRight then
			x = position.X + anchorSize.X - size.X
		end
	else
		local point = options.Position or layerPosition
		x, y = point.X, point.Y
		if y + size.Y > layerPosition.Y + layerSize.Y - margin then
			y = point.Y - size.Y
		end
	end
	x = math.clamp(x, layerPosition.X + margin, math.max(layerPosition.X + margin, layerPosition.X + layerSize.X - size.X - margin))
	y = math.clamp(y, layerPosition.Y + margin, math.max(layerPosition.Y + margin, layerPosition.Y + layerSize.Y - size.Y - margin))
	content.Position = UDim2.fromOffset(x - layerPosition.X, y - layerPosition.Y)
end

function Popup.Open(content, options)
	options = options or {}
	local layer = layerOf(options)
	if not layer then
		content:Destroy()
		return { Close = function() end }
	end
	local handle = { Frame = content, Closed = false }
	local catcher = UI.Create("TextButton", {
		Name = "PopupCatcher",
		Parent = layer,
		Text = "",
		BackgroundTransparency = if options.Scrim then 0.55 else 1,
		BackgroundColor3 = if options.Scrim then "Scrim" else nil,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 100 + #open * 2,
	})
	content.ZIndex = 101 + #open * 2
	content.Visible = false
	content.Parent = layer
	function handle.Close()
		if handle.Closed then
			return
		end
		handle.Closed = true
		local index = table.find(open, handle)
		if index then
			table.remove(open, index)
		end
		catcher:Destroy()
		content:Destroy()
		if options.OnClose then
			task.spawn(options.OnClose)
		end
	end
	function handle.Reposition()
		if not handle.Closed then
			place(content, layer, options)
		end
	end
	local function dismiss()
		if not options.Sticky then
			handle.Close()
		end
	end
	catcher.MouseButton1Down:Connect(dismiss)
	catcher.MouseButton2Down:Connect(dismiss)
	table.insert(open, handle)
	task.defer(function()
		if handle.Closed then
			return
		end
		place(content, layer, options)
		content.Visible = true
	end)
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(handle.Reposition)
	return handle
end

function Popup.CloseAll()
	for i = #open, 1, -1 do
		open[i].Close()
	end
end

function Popup.IsOpen()
	return #open > 0
end

function Popup.Card(props)
	props = props or {}
	props.BackgroundColor3 = props.BackgroundColor3 or "Raised"
	props.Corner = props.Corner or 6
	props.Stroke = props.Stroke or { Color = "Border", Thickness = 1 }
	local card = UI.Create("Frame", props)
	return card
end

return Popup
