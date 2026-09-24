local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local StudioService = game:GetService("StudioService")

local UI = require(script.Parent.Parent.UI)

local Creator = {}

Creator.Setting = "ExportCreator"
Creator.NameLimit = 50

local names = {}

function Creator.Me()
	local ok, userId = pcall(function()
		return StudioService:GetUserId()
	end)
	return if ok and type(userId) == "number" and userId > 0 then { Type = "User", Id = userId } else nil
end

function Creator.Owner()
	local ok, creatorType, creatorId = pcall(function()
		return game.CreatorType, game.CreatorId
	end)
	if not ok or type(creatorId) ~= "number" or creatorId <= 0 then
		return nil
	end
	return { Type = if creatorType == Enum.CreatorType.Group then "Group" else "User", Id = creatorId }
end

function Creator.Same(a, b)
	return a ~= nil and b ~= nil and a.Type == b.Type and a.Id == b.Id
end

function Creator.Name(creator)
	if not creator then
		return "nobody"
	end
	local key = creator.Type .. ":" .. creator.Id
	if names[key] then
		return names[key]
	end
	local name
	if creator.Type == "Group" then
		local ok, info = pcall(GroupService.GetGroupInfoAsync, GroupService, creator.Id)
		name = if ok and type(info) == "table" and type(info.Name) == "string" then info.Name else nil
	elseif Creator.Same(creator, Creator.Me()) then
		name = "your account"
	else
		local ok, userName = pcall(Players.GetNameFromUserIdAsync, Players, creator.Id)
		name = if ok then userName else nil
	end
	if name then
		names[key] = name
		return name
	end
	return if creator.Type == "Group" then `group {creator.Id}` else `user {creator.Id}`
end

function Creator.Load(app)
	local saved = app:GetSetting(Creator.Setting, nil)
	if type(saved) == "table" and (saved.Key == "Owner" or saved.Key == "Me" or saved.Key == "Group") then
		return { Key = saved.Key, GroupId = tonumber(saved.GroupId) }
	end
	return { Key = if Creator.Owner() then "Owner" else "Me" }
end

function Creator.Save(app, choice)
	app:SetSetting(Creator.Setting, { Key = choice.Key, GroupId = choice.GroupId })
end

function Creator.Resolve(choice)
	if choice.Key == "Owner" then
		return Creator.Owner() or Creator.Me()
	elseif choice.Key == "Group" then
		local id = tonumber(choice.GroupId)
		return if id and id > 0 then { Type = "Group", Id = math.floor(id) } else nil
	end
	return Creator.Me()
end

function Creator.Params(creator, item)
	local name = string.gsub(`{item.Cutscene.Name} {item.Actor} {item.Name}`, "%s+", " ")
	return {
		Name = string.sub(name, 1, Creator.NameLimit),
		Description = `Exported by Cutscene Editor. Keyframe hash {item.Hash}.`,
		CreatorType = if creator.Type == "Group" then Enum.AssetCreatorType.Group else Enum.AssetCreatorType.User,
		CreatorId = creator.Id,
	}
end

function Creator.Picker(state, onChanged)
	local owner = Creator.Owner()
	local ownerName = owner and Creator.Name(owner)
	local frame = UI.Create("Frame", {
		Name = "UploadTo",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		List = { Padding = 2 },
	})
	local function changed()
		state.Creator = Creator.Resolve(state.Choice)
		if onChanged then
			onChanged()
		end
	end
	local function render()
		UI.Clear(frame, { UIListLayout = true })
		UI.Create("TextLabel", {
			Parent = frame,
			LayoutOrder = 0,
			Text = "Upload to",
			Font = "Bold",
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 20),
		})
		local options = {}
		if owner and owner.Type == "Group" then
			table.insert(options, { Key = "Owner", Text = `{ownerName} (owns this experience)` })
			table.insert(options, { Key = "Me", Text = "My account" })
			table.insert(options, { Key = "Group", Text = "Another group" })
		else
			table.insert(options, { Key = "Me", Text = if owner then "My account (owns this experience)" else "My account" })
			table.insert(options, { Key = "Group", Text = "A group" })
		end
		for index, option in options do
			local selected = state.Choice.Key == option.Key or (option.Key == "Me" and state.Choice.Key == "Owner" and not (owner and owner.Type == "Group"))
			UI.Create("TextButton", {
				Parent = frame,
				LayoutOrder = index,
				Text = (if selected then "●  " else "○  ") .. option.Text,
				TextSize = 13,
				TextColor3 = if selected then "Text" else "SubText",
				TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Size = UDim2.new(1, 0, 0, 22),
				Events = {
					Activated = function()
						state.Choice.Key = option.Key
						changed()
						render()
					end,
				},
			})
		end
		if state.Choice.Key == "Group" then
			local nameLabel
			UI.TextField({
				Parent = frame,
				LayoutOrder = 10,
				Value = if state.Choice.GroupId then tostring(state.Choice.GroupId) else "",
				Placeholder = "Group id, for example 34541080",
				OnCommit = function(text)
					local id = tonumber(string.match(tostring(text), "%d+"))
					state.Choice.GroupId = id
					changed()
					if nameLabel then
						nameLabel.Text = if id then "Checking…" else ""
						task.spawn(function()
							local name = if id then Creator.Name({ Type = "Group", Id = id }) else ""
							if nameLabel.Parent and state.Choice.GroupId == id then
								nameLabel.Text = name
							end
						end)
					end
				end,
			})
			nameLabel = UI.Create("TextLabel", {
				Parent = frame,
				LayoutOrder = 11,
				Text = if state.Choice.GroupId then Creator.Name({ Type = "Group", Id = state.Choice.GroupId }) else "",
				TextSize = 12,
				TextColor3 = "SubText",
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, 0, 0, 18),
			})
		end
		local chosen = Creator.Resolve(state.Choice)
		if owner and chosen and not Creator.Same(owner, chosen) then
			UI.Create("TextLabel", {
				Parent = frame,
				LayoutOrder = 20,
				Text = `{ownerName} owns this experience. Animations uploaded somewhere else will not play in it.`,
				TextSize = 12,
				TextColor3 = "Warning",
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
			})
		end
		if state.Raise then
			state.Raise()
		end
	end
	state.Creator = Creator.Resolve(state.Choice)
	render()
	return frame
end

return Creator
