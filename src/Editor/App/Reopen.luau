return function(App)
	function App:_stopWatching()
		for _, connection in self.ReopenConnections or {} do
			connection:Disconnect()
		end
		self.ReopenConnections = nil
	end

	function App:_watchReopen(name, view)
		self:_stopWatching()
		local connections = {}
		self.ReopenConnections = connections
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local function consider(folder)
			if folder.Name ~= name or not folder:IsA("Folder") then
				return
			end
			task.delay(0.25, function()
				if self.Destroyed or self.Document or self.ReopenConnections ~= connections then
					return
				end
				if folder.Parent and folder:GetAttribute("Timeline") == true then
					self:_stopWatching()
					self:OpenCutscene(folder)
					self:SetView({ PixelsPerSecond = view.PixelsPerSecond, ScrollTime = view.ScrollTime, ScrollY = view.ScrollY })
					self.Time = view.Time
					self.Signals.TimeChanged:Fire(self.Time)
					self:Notify(`Reopened "{name}"`, "Info")
				end
			end)
		end
		local function watch(root)
			table.insert(connections, root.ChildAdded:Connect(consider))
			local existing = root:FindFirstChild(name)
			if existing then
				consider(existing)
			end
		end
		local root = ReplicatedStorage:FindFirstChild("Cutscenes")
		if root then
			watch(root)
		else
			table.insert(connections, ReplicatedStorage.ChildAdded:Connect(function(child)
				if child.Name == "Cutscenes" then
					watch(child)
				end
			end))
		end
	end
end
