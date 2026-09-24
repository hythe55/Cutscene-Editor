local TextService = game:GetService("TextService")

local UI = require(script.Parent)

local DELAY = 0.45
local MAX_WIDTH = 280

local current = nil

local function hide()
	if current then
		current:Destroy()
		current = nil
	end
end

local function measure(text)
	local ok, size = pcall(TextService.GetTextSize, TextService, text, 13, Enum.Font.BuilderSans, Vector2.new(MAX_WIDTH, 1000))
	return if ok then size else Vector2.new(math.min(#text * 7, MAX_WIDTH), 16)
end

local function show(guiObject, text)
	hide()
	local layer = UI.Layer
	if not layer or not guiObject.Parent or text == nil or text == "" then
		return
	end
	local size = measure(text)
	local frame = UI.Create("Frame", {
		Name = "Tooltip",
		Parent = layer,
		BackgroundColor3 = "Tooltip",
		Size = UDim2.fromOffset(size.X + 16, size.Y + 10),
		ZIndex = 200,
		Corner = 4,
		Stroke = { Color = "Border", Thickness = 1 },
	}, {
		UI.Create("TextLabel", {
			Text = text,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = "Text",
			Position = UDim2.fromOffset(8, 5),
			Size = UDim2.fromOffset(size.X + 1, size.Y),
			ZIndex = 201,
		}),
	})
	local layerPosition, layerSize = layer.AbsolutePosition, layer.AbsoluteSize
	local position, objectSize = guiObject.AbsolutePosition, guiObject.AbsoluteSize
	local width, height = size.X + 16, size.Y + 10
	local x = position.X + objectSize.X / 2 - width / 2
	local y = position.Y + objectSize.Y + 6
	if y + height > layerPosition.Y + layerSize.Y - 4 then
		y = position.Y - height - 6
	end
	x = math.clamp(x, layerPosition.X + 4, math.max(layerPosition.X + 4, layerPosition.X + layerSize.X - width - 4))
	frame.Position = UDim2.fromOffset(x - layerPosition.X, y - layerPosition.Y)
	current = frame
end

local function attach(guiObject, text)
	local token = 0
	local function resolve()
		if type(text) == "function" then
			return text()
		end
		return guiObject:GetAttribute("TooltipText") or text
	end
	guiObject.MouseEnter:Connect(function()
		token += 1
		local mine = token
		task.delay(DELAY, function()
			if token == mine then
				show(guiObject, resolve())
			end
		end)
	end)
	guiObject.MouseLeave:Connect(function()
		token += 1
		hide()
	end)
	guiObject.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
			token += 1
			hide()
		end
	end)
	guiObject.Destroying:Connect(function()
		token += 1
		hide()
	end)
	return guiObject
end

return setmetatable({ Attach = attach, Hide = hide }, {
	__call = function(_, guiObject, text)
		return attach(guiObject, text)
	end,
})
