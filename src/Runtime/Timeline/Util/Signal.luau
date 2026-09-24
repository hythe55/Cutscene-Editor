local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local handlers = self.Signal.Handlers
	local index = table.find(handlers, self)
	if index then
		table.remove(handlers, index)
	end
end

Connection.Destroy = Connection.Disconnect

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ Handlers = {}, Waiting = {} }, Signal)
end

function Signal:Connect(callback)
	local connection = setmetatable({ Connected = true, Signal = self, Callback = callback }, Connection)
	table.insert(self.Handlers, connection)
	return connection
end

function Signal:Once(callback)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function Signal:Wait()
	table.insert(self.Waiting, coroutine.running())
	return coroutine.yield()
end

function Signal:Fire(...)
	for _, connection in table.clone(self.Handlers) do
		if connection.Connected then
			task.spawn(connection.Callback, ...)
		end
	end
	local waiting = self.Waiting
	if #waiting > 0 then
		self.Waiting = {}
		for _, thread in waiting do
			task.spawn(thread, ...)
		end
	end
end

function Signal:DisconnectAll()
	for _, connection in self.Handlers do
		connection.Connected = false
	end
	table.clear(self.Handlers)
end

function Signal:Destroy()
	self:DisconnectAll()
	local waiting = self.Waiting
	self.Waiting = {}
	for _, thread in waiting do
		task.spawn(thread)
	end
end

return Signal
