local TextService = game:GetService("TextService")

local UI = require(script.Parent.Parent.UI)
local Model = require(script.Parent.Model)

local Hover = {}
Hover.__index = Hover

Hover.Delay = 0.5
Hover.MaxWidth = 320

function Hover.new(view)
	local self = setmetatable({}, Hover)
	self.View = view
	self.Token = 0
	self.Tip = nil
	return self
end

local function same(a, b)
	if a == nil or b == nil then
		return a == b
	end
	return a.Item == b.Item and a.Zone == b.Zone and a.Key == b.Key
end

function Hover:Update(hit, position)
	local view = self.View
	local state = if hit and hit.Item then { Item = hit.Item, Zone = hit.Zone, Key = hit.Key } else nil
	if not same(state, view.HoverState) then
		local itemChanged = (state and state.Item) ~= (view.HoverState and view.HoverState.Item)
		view.HoverState = state
		view:Invalidate("Hover")
		if itemChanged then
			self:_schedule(state and state.Item, position)
		end
	end
	self.Position = position
end

function Hover:Clear()
	self:Update(nil, nil)
	self:HideTip()
end

function Hover:_schedule(item, position)
	self.Token += 1
	self:HideTip()
	if not item then
		return
	end
	local token = self.Token
	self.Position = position
	task.delay(Hover.Delay, function()
		if self.Token == token and not self.View.Destroyed and not self.View.Interaction.Drag then
			self:ShowTip(Model.Describe(item), self.Position)
		end
	end)
end

function Hover:HideTip()
	if self.Tip then
		self.Tip:Destroy()
		self.Tip = nil
	end
end

function Hover:ShowTip(text, position)
	self:HideTip()
	local layer = UI.Layer
	if not layer or not position or text == "" then
		return
	end
	local ok, size = pcall(TextService.GetTextSize, TextService, text, 13, Enum.Font.BuilderSans, Vector2.new(Hover.MaxWidth, 1000))
	if not ok then
		size = Vector2.new(Hover.MaxWidth, 48)
	end
	local width, height = size.X + 18, size.Y + 12
	local origin, area = layer.AbsolutePosition, layer.AbsoluteSize
	local x = math.clamp(position.X + 14, origin.X + 4, math.max(origin.X + 4, origin.X + area.X - width - 4))
	local y = position.Y + 18
	if y + height > origin.Y + area.Y - 4 then
		y = position.Y - height - 8
	end
	self.Tip = UI.Create("Frame", {
		Name = "TimelineTooltip",
		Parent = layer,
		BackgroundColor3 = "Tooltip",
		Position = UDim2.fromOffset(x - origin.X, y - origin.Y),
		Size = UDim2.fromOffset(width, height),
		ZIndex = 200,
		Corner = 4,
		Stroke = { Color = "Border", Thickness = 1 },
	}, {
		UI.Create("TextLabel", {
			Text = text,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(9, 6),
			Size = UDim2.fromOffset(size.X + 1, size.Y),
			ZIndex = 201,
		}),
	})
end

function Hover:Destroy()
	self.Token += 1
	self:HideTip()
end

return Hover
