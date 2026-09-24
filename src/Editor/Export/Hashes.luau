local Hashes = {}
Hashes.__index = Hashes

Hashes.MaxAge = 60
Hashes.FrameBudget = 0.008

function Hashes.new(deps)
	return setmetatable({ Deps = deps, Entries = {} }, Hashes)
end

function Hashes:_drop(sequence)
	local entry = self.Entries[sequence]
	if not entry then
		return
	end
	self.Entries[sequence] = nil
	for _, connection in entry.Connections do
		connection:Disconnect()
	end
end

function Hashes:Peek(sequence)
	local entry = self.Entries[sequence]
	if entry and os.clock() - entry.Time < Hashes.MaxAge then
		return true, entry.Hash
	end
	return false, nil
end

function Hashes:Put(sequence, hash)
	self:_drop(sequence)
	local function drop()
		self:_drop(sequence)
	end
	self.Entries[sequence] = {
		Hash = hash,
		Time = os.clock(),
		Connections = {
			sequence.DescendantAdded:Connect(drop),
			sequence.DescendantRemoving:Connect(drop),
			sequence.AttributeChanged:Connect(drop),
			sequence.AncestryChanged:Connect(drop),
		},
	}
	return hash
end

function Hashes:Get(sequence)
	local cached, hash = self:Peek(sequence)
	if cached then
		return hash
	end
	local ok, value = pcall(self.Deps.Timeline.ComputeHash, sequence)
	return self:Put(sequence, if ok then value else nil)
end

function Hashes:Fill(sequences, shouldStop)
	local started = os.clock()
	for _, sequence in sequences do
		if shouldStop and shouldStop() then
			return false
		end
		if not self:Peek(sequence) and sequence.Parent then
			self:Get(sequence)
			if os.clock() - started > Hashes.FrameBudget then
				task.wait()
				started = os.clock()
			end
		end
	end
	return not (shouldStop and shouldStop())
end

function Hashes:Invalidate(changes)
	if type(changes) ~= "table" or changes.Undo or changes.Redo or changes.Opened then
		self:Clear()
		return
	end
	for instance in changes.Instances or {} do
		local current = instance
		while current do
			if self.Entries[current] then
				self:_drop(current)
				break
			end
			current = current.Parent
		end
	end
end

function Hashes:Clear()
	local sequences = {}
	for sequence in self.Entries do
		table.insert(sequences, sequence)
	end
	for _, sequence in sequences do
		self:_drop(sequence)
	end
end

function Hashes:Destroy()
	self:Clear()
end

return Hashes
