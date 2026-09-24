local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent.Parent.Parent.UI)

local Text = {}
Text.__index = Text

local function newlines(text)
	local _, count = string.gsub(text, "[\r\n]", "")
	return count
end

local function shiftDown()
	local ok, down = pcall(function()
		return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	end)
	return ok and down
end

function Text.new(entry, ctx)
	local theme = UI.Theme
	local self = setmetatable({
		Value = if ctx.Value == nil then "" else tostring(ctx.Value),
		Commit = ctx.Commit,
		Changed = ctx.Changed,
		Cursor = nil,
		Focused = false,
		Hover = false,
		ReadOnly = ctx.ReadOnly == true,
		Compact = ctx.Compact == true,
	}, Text)
	local root = UI.Create("Frame", {
		Name = "TextArea",
		Parent = ctx.Parent,
		LayoutOrder = ctx.LayoutOrder or 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = "Sunken",
		Corner = theme.Radius,
		Stroke = { Color = "Border", Thickness = 1 },
		Padding = if ctx.Compact then { X = 4, Y = 2 } else { X = 8, Y = 6 },
	})
	UI.Create("UISizeConstraint", { Parent = root, MinSize = Vector2.new(0, ctx.MinHeight or 44) })
	local box = UI.Create("TextBox", {
		Name = "Box",
		Parent = root,
		Text = self.Value,
		PlaceholderText = ctx.Placeholder or entry.Placeholder or "",
		TextSize = ctx.TextSize or 14,
		MultiLine = true,
		TextWrapped = true,
		TextEditable = not self.ReadOnly,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	self.Instance = root
	self.Box = box
	self.Last = self.Value
	root.MouseEnter:Connect(function()
		self.Hover = true
		self:_render()
	end)
	root.MouseLeave:Connect(function()
		self.Hover = false
		self:_render()
	end)
	box.Focused:Connect(function()
		self.Focused = true
		self.Last = box.Text
		self:_render()
		if ctx.OnFocus then
			ctx.OnFocus(self)
		end
	end)
	box.FocusLost:Connect(function()
		self.Focused = false
		self:_render()
		self:_commit()
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if not self.Focused then
			return
		end
		local text = box.Text
		if newlines(text) > newlines(self.Last) and not shiftDown() then
			box.Text = self.Last
			box:ReleaseFocus(true)
			return
		end
		self.Last = text
		if self.Changed then
			self.Changed(text, self)
		end
	end)
	box:GetPropertyChangedSignal("CursorPosition"):Connect(function()
		if self.Focused and box.CursorPosition > 0 then
			self.Cursor = box.CursorPosition
		end
	end)
	theme:Watch(root, function()
		self:_render()
	end)
	return self
end

function Text:_render()
	local theme = UI.Theme
	local stroke = self.Instance:FindFirstChild("Stroke")
	if stroke then
		stroke.Color = theme:Get(if self.Focused then "Accent" elseif self.Hover and not self.ReadOnly then "Outline" else "Border")
		stroke.Transparency = if self.Compact and not self.Focused and not self.Hover then 1 else 0
	end
	if self.Compact then
		self.Instance.BackgroundTransparency = if self.Focused then 0 else 1
	end
	self.Box.TextColor3 = theme:Get(if self.ReadOnly then "Dim" else "Text")
end

function Text:_commit()
	local text = self.Box.Text
	if text == self.Value then
		return
	end
	self.Value = text
	if self.Commit then
		self.Commit(text)
	end
end

function Text:Busy()
	return self.Focused
end

function Text:Set(value)
	value = if value == nil then "" else tostring(value)
	if self.Focused then
		return
	end
	self.Value = value
	self.Last = value
	self.Box.Text = value
end

function Text:Get()
	return self.Box.Text
end

function Text:Insert(token)
	local text = self.Box.Text
	local position = self.Cursor or (#text + 1)
	position = math.clamp(position, 1, #text + 1)
	local updated = string.sub(text, 1, position - 1) .. token .. string.sub(text, position)
	self.Box.Text = updated
	self.Cursor = position + #token
	self:_commit()
	task.defer(function()
		if self.Box.Parent then
			self.Box:CaptureFocus()
			self.Box.CursorPosition = self.Cursor
		end
	end)
end

function Text:Focus()
	self.Box:CaptureFocus()
	self.Box.CursorPosition = #self.Box.Text + 1
end

function Text:SetEnabled(enabled)
	self.ReadOnly = not enabled
	self.Box.TextEditable = enabled
	self:_render()
end

function Text:Destroy()
	self.Instance:Destroy()
end

return {
	text = function(entry, ctx)
		return Text.new(entry, ctx)
	end,
	new = Text.new,
	Class = Text,
}
