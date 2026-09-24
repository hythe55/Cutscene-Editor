local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Schema = require(script.Parent.Schema)
local Sampler = require(script.Parent.Sampler)
local Sources = require(script.Parent.Sources)
local Copy = require(script.Parent.Util.Copy)

local Actors = {}

local function placement(instance)
	if instance:IsDescendantOf(workspace) then
		return 1
	elseif instance:IsDescendantOf(ReplicatedStorage) then
		return 2
	end
	return 3
end

local function findTagged(tag)
	local best, bestPlacement
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("PVInstance") and Copy.Saved(instance) then
			local rank = placement(instance)
			if not best or rank < bestPlacement then
				best, bestPlacement = instance, rank
			end
		end
	end
	return best
end

local function visuals(model)
	local list = {}
	if model:IsA("BasePart") then
		table.insert(list, model)
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			table.insert(list, descendant)
		end
	end
	return list
end

local function rootPart(model)
	if model:IsA("BasePart") then
		return model
	end
	return model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart", true)
end

local function isRig(model)
	return model:FindFirstChildOfClass("Humanoid") ~= nil
		or model:FindFirstChildOfClass("AnimationController") ~= nil
		or model:FindFirstChildWhichIsA("Bone", true) ~= nil
end

local function strip(copy)
	local all = copy:GetDescendants()
	table.insert(all, copy)
	for _, instance in all do
		if instance:IsA("BaseScript") then
			instance:Destroy()
		elseif instance:IsA("Humanoid") then
			instance.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			instance.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
end

local function cloneModel(original, container)
	local copy = Copy.Clone(original)
	if not copy then
		return nil
	end
	strip(copy)
	copy.Parent = container
	return copy
end

local function hide(actor, model)
	for _, instance in visuals(model) do
		if actor.OriginalTransparency[instance] == nil then
			actor.OriginalTransparency[instance] = instance.LocalTransparencyModifier
		end
		instance.LocalTransparencyModifier = 1
	end
end

local function fillRoles(configs, options)
	local roles = table.clone(options.Roles or {})
	local roleIds, seenRole = {}, {}
	for config, attributes in configs do
		if attributes.Source == "Role" then
			local roleId = if attributes.Role ~= "" then attributes.Role else config.Name
			if not seenRole[roleId] then
				seenRole[roleId] = true
				table.insert(roleIds, roleId)
			end
		end
	end
	table.sort(roleIds)
	local pool = {}
	local listed = options.Players or options.Students
	if listed and #listed > 0 then
		pool = listed
	else
		local names = {}
		for name in roles do
			table.insert(names, name)
		end
		table.sort(names)
		local seen = {}
		for _, name in names do
			local userId = roles[name]
			if not seen[userId] then
				seen[userId] = true
				table.insert(pool, userId)
			end
		end
	end
	local used = 0
	for _, roleId in roleIds do
		if roles[roleId] == nil and #pool > 0 then
			used += 1
			roles[roleId] = pool[(used - 1) % #pool + 1]
		end
	end
	return roles
end

local function character(options, userId, found, players)
	local standIn = options.Characters and options.Characters[userId]
	if typeof(standIn) == "Instance" and standIn:IsA("Model") then
		table.insert(found, standIn)
		return true
	end
	local player = Players:GetPlayerByUserId(userId)
	if player and player.Character then
		table.insert(found, player.Character)
		table.insert(players, player)
		return true
	end
	return false
end

local function playerSources(actor, options, roles)
	local attributes = actor.Attributes
	local found, players = {}, {}
	local standIns = options.RoleModels or {}
	if attributes.Source == "Role" then
		local roleId = if attributes.Role ~= "" then attributes.Role else actor.Id
		actor.RoleId = roleId
		local userId = roles[roleId]
		actor.UserId = userId
		if not (userId and character(options, userId, found, players)) and (standIns[roleId] or standIns[actor.Id]) then
			table.insert(found, standIns[roleId] or standIns[actor.Id])
		end
	else
		for _, userId in options.Players or options.Students or {} do
			character(options, userId, found, players)
		end
		if #found == 0 and type(standIns[actor.Id]) == "table" then
			found = table.clone(standIns[actor.Id])
		end
	end
	return found, players
end

local function resolve(config, attributes, options, roles, container)
	local actor = {
		Id = config.Name,
		Config = config,
		Attributes = attributes,
		Source = attributes.Source,
		Mode = attributes.Mode,
		Kind = "Prop",
		Models = {},
		Originals = {},
		OriginalTransparency = {},
		Transparency = {},
		HideSources = {},
		AppliedHide = 0,
	}
	local sources = {}
	if attributes.Source == "Tag" then
		local model = attributes.Tag ~= "" and findTagged(attributes.Tag)
		sources = if model then { model } else {}
	elseif attributes.Source == "Template" then
		local template = config:FindFirstChild("Template")
		sources = if template and template:IsA("PVInstance") then { template } else {}
		actor.Mode = "Clone"
	else
		actor.Kind = if attributes.Source == "Role" then "Player" else "Group"
		actor.Mode = if config:GetAttribute("Mode") == "Clone" then "Clone" else "Original"
		sources, actor.Players = playerSources(actor, options, roles)
	end
	for _, source in sources do
		if actor.Mode == "Clone" then
			local copy = cloneModel(source, container)
			if copy then
				table.insert(actor.Models, copy)
				if attributes.Source ~= "Template" then
					table.insert(actor.Originals, source)
					hide(actor, source)
				end
			end
		else
			table.insert(actor.Models, source)
		end
	end
	actor.Model = actor.Models[1]
	actor.Original = actor.Originals[1]
	if actor.Kind == "Player" or actor.Kind == "Group" then
		actor.Characters = actor.Models
	elseif actor.Model and isRig(actor.Model) then
		actor.Kind = "Rig"
	end
	if actor.Model then
		actor.SourcePivot = actor.Model:GetPivot()
	end
	local playerLike = actor.Kind == "Player" or actor.Kind == "Group"
	for _, model in actor.Models do
		local root = rootPart(model)
		if actor.Mode ~= "Clone" and not playerLike then
			local parts, cframes = {}, {}
			for _, instance in visuals(model) do
				if instance:IsA("BasePart") then
					table.insert(parts, instance)
					table.insert(cframes, instance.CFrame)
				end
			end
			actor.Restore = actor.Restore or {}
			table.insert(actor.Restore, {
				Model = model,
				WorldPivot = if model:IsA("Model") then model.WorldPivot else nil,
				Parts = parts,
				CFrames = cframes,
				Root = root,
				Anchored = root and root.Anchored,
			})
		end
		if root and attributes.Anchor and not playerLike then
			root.Anchored = true
		end
	end
	local idle = config:FindFirstChild("Idle")
	if idle and idle:IsA("KeyframeSequence") then
		actor.IdleSequence = idle
		local keyframes = Sources.Keyframes(idle)
		actor.Idle = if keyframes then Sampler.new(keyframes) else nil
	end
	return actor
end

function Actors.Build(folder, options, container)
	local configs = {}
	local actorsFolder = folder:FindFirstChild("Actors")
	if actorsFolder then
		for _, config in actorsFolder:GetChildren() do
			if config:IsA("Configuration") then
				configs[config] = Schema.Read(config, "Actor")
			end
		end
	end
	local roles = fillRoles(configs, options)
	local actors = {}
	for config, attributes in configs do
		actors[config.Name] = resolve(config, attributes, options, roles, container)
	end
	return actors, roles
end

function Actors.Refresh(actor)
	if actor.Kind ~= "Player" or actor.Mode == "Clone" then
		return
	end
	local player = actor.Players and actor.Players[1]
	local character = player and player.Character
	if character and character ~= actor.Model then
		actor.Model = character
		actor.Models = { character }
		actor.Characters = actor.Models
		actor.Transparency = {}
		actor.AppliedHide = 0
	end
end

function Actors.SetTransparency(actor, amount)
	if amount == actor.AppliedHide then
		return
	end
	actor.AppliedHide = amount
	for _, model in actor.Models do
		if model.Parent then
			actor.Visuals = actor.Visuals or {}
			local list = actor.Visuals[model]
			if not list then
				list = visuals(model)
				actor.Visuals[model] = list
			end
			for _, instance in list do
				local original = actor.Transparency[instance]
				if original == nil then
					original = instance.LocalTransparencyModifier
					actor.Transparency[instance] = original
				end
				instance.LocalTransparencyModifier = math.max(original, amount)
			end
		end
	end
end

function Actors.Destroy(actor)
	for instance, value in actor.Transparency do
		if instance.Parent then
			instance.LocalTransparencyModifier = value
		end
	end
	if actor.Mode == "Clone" then
		for _, model in actor.Models do
			model:Destroy()
		end
	end
	for instance, value in actor.OriginalTransparency do
		if instance.Parent then
			instance.LocalTransparencyModifier = value
		end
	end
	for _, record in actor.Restore or {} do
		local parts, cframes = {}, {}
		for i, part in record.Parts do
			if part.Parent and part.CFrame ~= record.CFrames[i] then
				table.insert(parts, part)
				table.insert(cframes, record.CFrames[i])
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
		local model = record.Model
		if record.WorldPivot and model.Parent and not model.PrimaryPart and model.WorldPivot ~= record.WorldPivot then
			model.WorldPivot = record.WorldPivot
		end
		if record.Root and record.Root.Parent and record.Root.Anchored ~= record.Anchored then
			record.Root.Anchored = record.Anchored
		end
	end
	table.clear(actor.Models)
	actor.Model = nil
end

return Actors
