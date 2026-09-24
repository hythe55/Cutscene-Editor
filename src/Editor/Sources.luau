local ServerStorage = game:GetService("ServerStorage")

local Sources = {}

function Sources.Sequence(target)
	local id = target:GetAttribute("SourceId")
	if type(id) == "string" and id ~= "" then
		local root = ServerStorage:FindFirstChild("CutsceneSources")
		local source = root and root:FindFirstChild(id, true)
		if source and source:IsA("KeyframeSequence") then
			return source
		end
	end
	if target:IsA("KeyframeSequence") then
		return target
	end
	local replica = target:FindFirstChild("Keyframes")
	if replica and replica:IsA("KeyframeSequence") then
		return replica
	end
	return target:FindFirstChildOfClass("KeyframeSequence")
end

return Sources
