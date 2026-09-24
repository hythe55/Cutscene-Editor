local CollectionService = game:GetService("CollectionService")

local Copy = {}

local function untag(instance)
	for _, tag in CollectionService:GetTags(instance) do
		CollectionService:RemoveTag(instance, tag)
	end
end

function Copy.StripTags(root)
	untag(root)
	for _, descendant in root:GetDescendants() do
		untag(descendant)
	end
	return root
end

function Copy.Clone(original)
	local archivable = original.Archivable
	if not archivable then
		original.Archivable = true
	end
	local ok, copy = pcall(original.Clone, original)
	if not archivable then
		original.Archivable = false
	end
	if not ok or not copy then
		return nil
	end
	return Copy.StripTags(copy)
end

function Copy.Saved(instance)
	local current = instance
	while current and current ~= game do
		if not current.Archivable then
			return false
		end
		current = current.Parent
	end
	return current == game
end

return Copy
