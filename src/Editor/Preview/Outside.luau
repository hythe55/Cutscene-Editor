local Selection = game:GetService("Selection")

local Outside = {}
Outside.__index = Outside

Outside.Services = {
	Workspace = true,
	ReplicatedStorage = true,
	ReplicatedFirst = true,
	ServerStorage = true,
	ServerScriptService = true,
	StarterGui = true,
	StarterPack = true,
	StarterPlayer = true,
	Lighting = true,
	SoundService = true,
	Teams = true,
	TextChatService = true,
	MaterialService = true,
	Chat = true,
	LocalizationService = true,
}

Outside.Ignored = {
	LocalTransparencyModifier = true,
}

function Outside.new()
	local self = setmetatable({}, Outside)
	self.Changed = false
	self.Reason = nil
	self.Cache = setmetatable({}, { __mode = "k" })
	self.Connections = {
		game.ItemChanged:Connect(function(instance, property)
			if Outside.Ignored[property] then
				return
			end
			if property == "Parent" then
				self.Cache[instance] = nil
			end
			self:_check(instance, property)
		end),
		game.DescendantAdded:Connect(function(instance)
			self.Cache[instance] = nil
			self:_check(instance, "added")
		end),
		game.DescendantRemoving:Connect(function(instance)
			self.Cache[instance] = nil
			self:_check(instance, "removed")
		end),
		Selection.SelectionChanged:Connect(function()
			self:Mark("selection changed")
		end),
	}
	for _, instance in Selection:Get() do
		table.insert(self.Connections, instance.AttributeChanged:Connect(function(name)
			self:Mark(`{instance:GetFullName()} attribute {name}`)
		end))
	end
	return self
end

function Outside:_saved(instance)
	local known = self.Cache[instance]
	if known ~= nil then
		return known
	end
	local saved = instance ~= workspace.CurrentCamera
	local current = instance
	while saved and current and current.Parent ~= game do
		saved = current.Archivable
		current = current.Parent
	end
	saved = saved and current ~= nil and current.Archivable and Outside.Services[current.ClassName] == true
	self.Cache[instance] = saved
	return saved
end

function Outside:_check(instance, what)
	if self.Changed then
		return
	end
	local ok, saved = pcall(self._saved, self, instance)
	if ok and saved then
		self:Mark(`{instance:GetFullName()} ({what})`)
	end
end

function Outside:Mark(reason)
	if self.Changed then
		return
	end
	self.Changed = true
	self.Reason = reason
	self:_disconnect()
end

function Outside:_disconnect()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
end

function Outside:Destroy()
	self:_disconnect()
	table.clear(self.Cache)
end

return Outside
