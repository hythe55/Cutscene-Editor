local UserInputService = game:GetService("UserInputService")

local Actions = require(script.Parent.Actions)

local Keyboard = {}
Keyboard.__index = Keyboard

local KEY = Enum.KeyCode

local MODIFIERS = {
	[KEY.LeftShift] = true,
	[KEY.RightShift] = true,
	[KEY.LeftControl] = true,
	[KEY.RightControl] = true,
	[KEY.LeftAlt] = true,
	[KEY.RightAlt] = true,
	[KEY.LeftSuper] = true,
	[KEY.RightSuper] = true,
}

function Keyboard.new(view)
	local self = setmetatable({}, Keyboard)
	self.View = view
	self.Connections = {}
	self.Boxes = {}
	local app = view.App
	local root = app.Shell and app.Shell.Root
	local scope = if typeof(app.Widget) == "Instance" then app.Widget else root
	if scope then
		self:_track(scope)
	end
	if root then
		table.insert(self.Connections, root.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Keyboard then
				self:_began(input)
			end
		end))
		table.insert(self.Connections, root.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Keyboard then
				self:_ended(input)
			end
		end))
	end
	return self
end

function Keyboard:_watch(instance)
	if not instance:IsA("TextBox") or self.Boxes[instance] then
		return
	end
	self.Boxes[instance] = true
end

function Keyboard:_track(scope)
	for _, descendant in scope:GetDescendants() do
		self:_watch(descendant)
	end
	table.insert(self.Connections, scope.DescendantAdded:Connect(function(descendant)
		self:_watch(descendant)
	end))
	table.insert(self.Connections, scope.DescendantRemoving:Connect(function(descendant)
		self.Boxes[descendant] = nil
	end))
end

function Keyboard:IsTyping()
	for box in self.Boxes do
		local ok, focused = pcall(box.IsFocused, box)
		if ok and focused then
			return true
		end
	end
	local ok, focused = pcall(UserInputService.GetFocusedTextBox, UserInputService)
	return ok and focused ~= nil
end

function Keyboard:_began(input)
	local interaction = self.View.Interaction
	if MODIFIERS[input.KeyCode] then
		interaction.Held[input.KeyCode] = true
		interaction:Refresh()
		return
	end
	if self:IsTyping() then
		return
	end
	self:Handle(input.KeyCode, interaction:Modifiers(input))
end

function Keyboard:_ended(input)
	local interaction = self.View.Interaction
	if MODIFIERS[input.KeyCode] then
		interaction.Held[input.KeyCode] = nil
		interaction:Refresh()
	end
end

function Keyboard:Handle(keyCode, mods)
	mods = mods or {}
	local view = self.View
	local app = view.App
	if not app.Document then
		return false
	end
	local ctrl = mods.Ctrl == true
	if keyCode == KEY.Escape then
		if not view.Interaction:Cancel() then
			app:Select({}, "Replace")
		end
	elseif keyCode == KEY.Space and not ctrl then
		app.Preview:Toggle()
	elseif keyCode == KEY.Delete then
		Actions.Delete(view)
	elseif keyCode == KEY.D and ctrl then
		Actions.Duplicate(view)
	elseif keyCode == KEY.A and ctrl then
		Actions.SelectAll(view)
	elseif keyCode == KEY.S and not ctrl then
		Actions.Split(view)
	elseif keyCode == KEY.Home then
		app:SetTime(0)
	elseif keyCode == KEY.End then
		app:SetTime(view.Model.Length)
	elseif keyCode == KEY.Left or keyCode == KEY.Right then
		local step = if mods.Shift then 1 else 1 / 30
		Actions.Step(view, if keyCode == KEY.Left then -step else step)
	elseif keyCode == KEY.F and not ctrl then
		Actions.Frame(view)
	else
		return false
	end
	return true
end

function Keyboard:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	table.clear(self.Boxes)
end

return Keyboard
