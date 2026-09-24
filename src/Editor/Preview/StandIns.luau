local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local StandIns = {}

StandIns.SeatHeight = 2.25
StandIns.CenterOffset = 0.27
StandIns.RootAboveSeat = 1.5
StandIns.DefaultCount = 4
StandIns.Cache = {}

local SHIRTS = {
	Color3.fromRGB(70, 130, 220),
	Color3.fromRGB(220, 90, 80),
	Color3.fromRGB(90, 180, 100),
	Color3.fromRGB(230, 180, 60),
	Color3.fromRGB(160, 100, 210),
	Color3.fromRGB(60, 190, 190),
	Color3.fromRGB(230, 130, 180),
	Color3.fromRGB(140, 140, 150),
}
local SKINS = {
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(160, 110, 80),
	Color3.fromRGB(245, 205, 170),
	Color3.fromRGB(110, 75, 55),
}
local PANTS = Color3.fromRGB(50, 55, 75)

local SEATED = {
	LeftHip = CFrame.Angles(math.rad(90), 0, math.rad(-4)),
	RightHip = CFrame.Angles(math.rad(90), 0, math.rad(4)),
	LeftKnee = CFrame.Angles(math.rad(-88), 0, 0),
	RightKnee = CFrame.Angles(math.rad(-88), 0, 0),
	LeftShoulder = CFrame.Angles(math.rad(30), 0, math.rad(-6)),
	RightShoulder = CFrame.Angles(math.rad(30), 0, math.rad(6)),
	LeftElbow = CFrame.Angles(math.rad(50), 0, 0),
	RightElbow = CFrame.Angles(math.rad(50), 0, 0),
}

local function saved(instance)
	local current = instance
	while current and current ~= game do
		if not current.Archivable then
			return false
		end
		current = current.Parent
	end
	return current == game
end

local function flat(vector)
	local v = Vector3.new(vector.X, 0, vector.Z)
	return if v.Magnitude > 0.5 then v.Unit else Vector3.new(0, 0, -1)
end

local function measure(chair)
	local center, size
	if chair:IsA("Model") then
		local cframe
		cframe, size = chair:GetBoundingBox()
		center = cframe.Position
	elseif chair:IsA("BasePart") then
		center, size = chair.Position, chair.Size
	else
		return nil
	end
	local facing = flat(chair:GetPivot().LookVector)
	local origin = center + facing * StandIns.CenterOffset
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { chair }
	local floorY = center.Y - size.Y / 2
	for _ = 1, 8 do
		local hit = workspace:Raycast(origin, Vector3.new(0, -8, 0), params)
		if not hit then
			break
		elseif hit.Instance.Anchored then
			floorY = hit.Position.Y
			break
		end
		params:AddToFilter(hit.Instance)
	end
	return {
		Chair = chair,
		Seat = Vector3.new(origin.X, floorY + StandIns.SeatHeight, origin.Z),
		Facing = facing,
	}
end

local function tagged(tag)
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("PVInstance") and saved(instance) and instance:IsDescendantOf(workspace) then
			return instance
		end
	end
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("PVInstance") and saved(instance) then
			return instance
		end
	end
	return nil
end

local function isRig(model)
	return model:FindFirstChildOfClass("Humanoid") ~= nil
		or model:FindFirstChildOfClass("AnimationController") ~= nil
		or model:FindFirstChildWhichIsA("Bone", true) ~= nil
end

function StandIns.Focus(document)
	local folder = document.Folder
	local focus = folder:GetAttribute("ChairFocus")
	if typeof(focus) == "Vector3" then
		return focus
	end
	local fallback
	for _, actor in document:GetActors() do
		local tag = actor:GetAttribute("Tag")
		if actor:GetAttribute("Source") == "Tag" and type(tag) == "string" and tag ~= "" then
			local model = tagged(tag)
			if model then
				if isRig(model) then
					return model:GetPivot().Position
				end
				fallback = fallback or model:GetPivot().Position
			end
		end
	end
	return fallback
end

function StandIns.Chairs(document)
	local tag = document.Folder:GetAttribute("ChairTag")
	if type(tag) ~= "string" or tag == "" then
		return {}
	end
	local chairs = {}
	for _, chair in CollectionService:GetTagged(tag) do
		if chair:IsDescendantOf(workspace) and saved(chair) then
			local seat = measure(chair)
			if seat then
				table.insert(chairs, seat)
			end
		end
	end
	local focus = StandIns.Focus(document)
	if not focus and #chairs > 0 then
		local sum = Vector3.zero
		for _, seat in chairs do
			sum += seat.Seat
		end
		focus = sum / #chairs
	end
	for _, seat in chairs do
		seat.Distance = if focus then (seat.Seat - focus).Magnitude else 0
	end
	table.sort(chairs, function(a, b)
		if a.Distance ~= b.Distance then
			return a.Distance < b.Distance
		end
		return a.Seat.X < b.Seat.X
	end)
	return chairs
end

function StandIns.Needed(document)
	for _, actor in document:GetActors() do
		local source = actor:GetAttribute("Source")
		if source == "Role" or source == "Group" then
			return true
		end
	end
	return false
end

local STRIP = { WrapTarget = true, WrapLayer = true, WrapDeformer = true, BaseScript = true, FaceControls = true }

local function strip(model)
	for _, descendant in model:GetDescendants() do
		for className in STRIP do
			if descendant:IsA(className) then
				descendant:Destroy()
				break
			end
		end
	end
end

local function convertJoints(model)
	local motors = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("AnimationConstraint") then
			local a0, a1 = descendant.Attachment0, descendant.Attachment1
			if a0 and a1 and a0.Parent and a1.Parent then
				local motor = Instance.new("Motor6D")
				motor.Name = descendant.Name
				motor.Part0 = a0.Parent
				motor.Part1 = a1.Parent
				motor.C0 = a0.CFrame
				motor.C1 = a1.CFrame
				motor.Parent = a1.Parent
				motors[a1.Parent] = motor
			end
			descendant:Destroy()
		elseif descendant:IsA("Motor6D") then
			motors[descendant.Part1] = descendant
		elseif descendant:IsA("BallSocketConstraint") or descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end
	return motors
end

local function pose(model, motors, root, rootCFrame, seated, baseC0)
	for _, motor in motors do
		local base = baseC0[motor] or motor.C0
		local rotation = if seated then SEATED[motor.Name] else nil
		motor.C0 = if rotation then base * rotation else base
	end
	root.CFrame = rootCFrame
	local placed = { [root] = true }
	local function place(part)
		if placed[part] then
			return
		end
		placed[part] = true
		local motor = motors[part]
		if not motor or not motor.Part0 then
			return
		end
		place(motor.Part0)
		part.CFrame = motor.Part0.CFrame * motor.C0 * motor.C1:Inverse()
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			place(part)
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = part == root
			part.Anchored = part == root
		end
	end
end

local function build(index)
	local description = Instance.new("HumanoidDescription")
	local skin = SKINS[(index - 1) % #SKINS + 1]
	description.HeadColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.TorsoColor = SHIRTS[(index - 1) % #SHIRTS + 1]
	description.LeftLegColor = PANTS
	description.RightLegColor = PANTS
	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	model.Name = "StandIn" .. index
	model.Archivable = false
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.DisplayName = " "
	end
	strip(model)
	local motors = convertJoints(model)
	local baseC0 = {}
	for _, motor in motors do
		baseC0[motor] = motor.C0
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	model.PrimaryPart = root
	return { Model = model, Motors = motors, Root = root, BaseC0 = baseC0 }
end

function StandIns.Create(index, rootCFrame, seated)
	local entry = StandIns.Cache[index]
	if not entry or not entry.Model or not pcall(function()
		entry.Model.Parent = nil
	end) then
		entry = build(index)
		StandIns.Cache[index] = entry
	end
	if entry.Root then
		pose(entry.Model, entry.Motors, entry.Root, rootCFrame, seated, entry.BaseC0)
	end
	return entry.Model
end

function StandIns.Release()
	for _, entry in StandIns.Cache do
		if entry.Model then
			entry.Model.Parent = nil
		end
	end
end

function StandIns.Clear()
	for index, entry in StandIns.Cache do
		if entry.Model then
			pcall(game.Destroy, entry.Model)
		end
		StandIns.Cache[index] = nil
	end
end

function StandIns.Build(document, count, parent)
	local result = { Models = {}, Characters = {}, Roles = {}, Students = {} }
	if not StandIns.Needed(document) then
		return result
	end
	count = math.clamp(math.floor(count or StandIns.DefaultCount), 1, 16)
	local chairs = StandIns.Chairs(document)
	local focus = StandIns.Focus(document) or Vector3.new(0, 0, 0)
	for index = 1, count do
		local seat = chairs[index]
		local rootCFrame, seated
		if seat then
			local position = seat.Seat + Vector3.new(0, StandIns.RootAboveSeat, 0)
			rootCFrame = CFrame.lookAt(position, position + seat.Facing)
			seated = true
		else
			local position = focus + Vector3.new((index - (count + 1) / 2) * 4, 3, 12)
			rootCFrame = CFrame.lookAt(position, Vector3.new(focus.X, position.Y, focus.Z))
			seated = false
		end
		local ok, model = pcall(StandIns.Create, index, rootCFrame, seated)
		if ok and model then
			model.Parent = parent
			local userId = -index
			table.insert(result.Models, model)
			table.insert(result.Students, userId)
			result.Characters[userId] = model
		else
			warn("CutsceneEditor: stand-in failed: " .. tostring(model))
		end
	end
	local students = result.Students
	if #students > 0 then
		for index, role in document:GetRoles() do
			result.Roles[role] = students[(index - 1) % #students + 1]
		end
	end
	result.Chairs = #chairs
	return result
end

return StandIns
