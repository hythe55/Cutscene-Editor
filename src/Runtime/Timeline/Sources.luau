local ServerStorage = game:GetService("ServerStorage")

local Sampler = require(script.Parent.Sampler)

local Sources = {}

Sources.FolderName = "CutsceneSources"

function Sources.Root(create)
	local ok, root = pcall(function()
		return ServerStorage:FindFirstChild(Sources.FolderName)
	end)
	root = ok and root or nil
	if not root and create then
		root = Instance.new("Folder")
		root.Name = Sources.FolderName
		root.Parent = ServerStorage
	end
	return root
end

function Sources.Find(clip)
	local id = clip:GetAttribute("SourceId")
	if type(id) ~= "string" or id == "" then
		return nil
	end
	local root = Sources.Root(false)
	local found = root and root:FindFirstChild(id, true)
	if found and found:IsA("KeyframeSequence") then
		return found
	end
	return nil
end

function Sources.Replica(clip)
	local replica = clip:FindFirstChild("Keyframes")
	if replica and replica:IsA("KeyframeSequence") then
		return replica
	end
	return clip:FindFirstChildOfClass("KeyframeSequence")
end

function Sources.Keyframes(clip)
	return Sources.Find(clip) or Sources.Replica(clip)
end

function Sources.Hash(sequence)
	return Sampler.Hash(sequence)
end

function Sources.ContentHash(clip, sequence)
	local stored = clip:GetAttribute("ContentHash")
	if type(stored) == "string" and stored ~= "" then
		return stored
	end
	sequence = sequence or Sources.Keyframes(clip)
	return sequence and Sources.Hash(sequence) or nil
end

function Sources.IsExported(clip, sequence)
	local id = clip:GetAttribute("AnimationId")
	local exported = clip:GetAttribute("ExportedHash")
	if type(id) ~= "string" or id == "" or type(exported) ~= "string" or exported == "" then
		return false
	end
	return exported == Sources.ContentHash(clip, sequence)
end

return Sources
