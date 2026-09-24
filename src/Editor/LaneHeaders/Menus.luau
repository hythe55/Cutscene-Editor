local CollectionService = game:GetService("CollectionService")
local Selection = game:GetService("Selection")

local UI = require(script.Parent.Parent.UI)

return function(LaneHeaders)
	function LaneHeaders:Rename(instance, label)
		local app = self.App
		local document = app.Document
		if not document then
			return
		end
		local box = UI.Create("TextBox", {
			Parent = label.Parent,
			Text = instance.Name,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = "Sunken",
			Position = label.Position - UDim2.fromOffset(4, 0),
			Size = UDim2.new(label.Size.X.Scale, label.Size.X.Offset, 0, 20),
			Corner = 3,
			Padding = { Left = 4 },
			Stroke = { Color = "Accent", Thickness = 1 },
			ZIndex = 5,
		})
		box:CaptureFocus()
		box.SelectionStart = 1
		box.CursorPosition = #box.Text + 1
		box.FocusLost:Connect(function(enter)
			local text = box.Text
			box:Destroy()
			if enter and text ~= "" and text ~= instance.Name then
				document:Rename(instance, text)
			end
		end)
	end

	local function kindItems(app, actorId, onlyActorKinds)
		local schema = app.Deps.Schema
		local items = {}
		for _, kind in schema.Order do
			local definition = schema.Kinds[kind]
			if definition and (definition.UsesActor == onlyActorKinds) then
				table.insert(items, {
					Text = kind,
					Color = definition.Color,
					OnClick = function()
						local track = app.Document:AddTrack(kind, actorId)
						if track then
							app:Select(track)
						end
					end,
				})
			end
		end
		return items
	end

	function LaneHeaders:AddTrackMenu(actor, anchor)
		local app = self.App
		if not app.Document then
			return
		end
		local items = { { Header = true, Text = if actor then "ADD TRACK FOR " .. string.upper(actor.Name) else "ADD SCENE TRACK" } }
		for _, item in kindItems(app, if actor then actor.Name else nil, actor ~= nil) do
			table.insert(items, item)
		end
		if actor then
			table.insert(items, { Separator = true })
			table.insert(items, { Header = true, Text = "SCENE KINDS (ANCHORED HERE)" })
			for _, item in kindItems(app, actor.Name, false) do
				if item.Text == "Sound" or item.Text == "VFX" then
					table.insert(items, item)
				end
			end
		end
		return UI.Menu.Show(items, { Anchor = anchor, MinWidth = 200 })
	end

	function LaneHeaders:TrackMenu(row, frame)
		local app = self.App
		local document = app.Document
		local track = row.Track
		local info = row.Info
		local items = {
			{ Header = true, Text = string.upper(track.Name) },
			{
				Text = "Add clip at playhead",
				Enabled = not info.Locked,
				OnClick = function()
					local clip = document:AddClip(track, app.Time)
					if clip then
						app:Select(clip)
					end
				end,
			},
			{
				Text = "Rename",
				OnClick = function()
					for _, entry in self.RowFrames do
						if entry.Row.Track == track and entry.NameLabel then
							self:Rename(track, entry.NameLabel)
						end
					end
				end,
			},
			{ Separator = true },
			{
				Text = if info.Muted then "Unmute" else "Mute",
				OnClick = function()
					document:SetAttribute(track, "Muted", not info.Muted)
				end,
			},
			{
				Text = if info.Locked then "Unlock" else "Lock",
				OnClick = function()
					document:SetAttribute(track, "Locked", not info.Locked)
				end,
			},
			{
				Text = "Select in Explorer",
				OnClick = function()
					Selection:Set({ track })
				end,
			},
			{ Separator = true },
			{
				Text = "Delete track",
				Danger = true,
				Enabled = not info.Locked,
				OnClick = function()
					local count = #info.Clips
					local choice = app:Modal({
						Title = "Delete track",
						Text = `Delete "{track.Name}" and its {count} clip{if count == 1 then "" else "s"}? You can undo this with Ctrl+Z.`,
						Buttons = { "Cancel", "Delete" },
						Danger = "Delete",
						Primary = "Delete",
					})
					if choice == "Delete" then
						document:DeleteTrack(track)
					end
				end,
			},
		}
		local position = frame.AbsolutePosition + Vector2.new(24, frame.AbsoluteSize.Y)
		return UI.Menu.Show(items, { Position = position })
	end

	function LaneHeaders:GroupMenu(row, frame)
		local app = self.App
		local document = app.Document
		local actor = row.Actor
		local items = {
			{ Header = true, Text = if actor then string.upper(actor.Name) else "SCENE" },
			{
				Text = "Add track…",
				OnClick = function()
					self:AddTrackMenu(actor, frame)
				end,
			},
			{
				Text = if row.Collapsed then "Expand" else "Collapse",
				OnClick = function()
					app:SetCollapsed(actor, not row.Collapsed)
				end,
			},
		}
		if actor then
			table.insert(items, {
				Text = "Rename actor",
				OnClick = function()
					task.spawn(function()
						local choice, text = app:Modal({
							Title = "Rename actor",
							Text = "Tracks and clips that reference this actor are updated too.",
							Input = { Value = actor.Name },
							Buttons = { "Cancel", "Rename" },
						})
						if choice == "Rename" and text and text ~= "" then
							document:RenameActor(actor, text)
						end
					end)
				end,
			})
			table.insert(items, {
				Text = "Select in Explorer",
				OnClick = function()
					Selection:Set({ actor })
				end,
			})
			table.insert(items, { Separator = true })
			table.insert(items, {
				Text = "Delete actor",
				Danger = true,
				OnClick = function()
					local choice = app:Modal({
						Title = "Delete actor",
						Text = `Delete the actor "{actor.Name}"? Its tracks stay and move to the Scene group.`,
						Buttons = { "Cancel", "Delete" },
						Danger = "Delete",
						Primary = "Delete",
					})
					if choice == "Delete" then
						document:DeleteActor(actor)
					end
				end,
			})
		end
		local position = frame.AbsolutePosition + Vector2.new(24, frame.AbsoluteSize.Y)
		return UI.Menu.Show(items, { Position = position })
	end

	local function uniqueId(document, base)
		local id, index = base, 1
		while document:GetActor(id) do
			index += 1
			id = base .. index
		end
		return id
	end

	function LaneHeaders:AddActorMenu(anchor)
		local app = self.App
		local document = app.Document
		if not document then
			return
		end
		local selected = Selection:Get()[1]
		local function add(props)
			local config = document:AddActor(props)
			if config then
				app:Select(config)
				app:Notify(`Added actor {config.Name}`, "Success")
			end
		end
		local items = {
			{ Header = true, Text = "ADD ACTOR" },
			{
				Text = "Tagged model…",
				Hint = "Source Tag",
				OnClick = function()
					local suggestion = ""
					if selected then
						suggestion = CollectionService:GetTags(selected)[1] or ""
					end
					local choice, tag = app:Modal({
						Title = "Tagged model",
						Text = "The actor is the model carrying this CollectionService tag. The preview and the game clone it.",
						Input = { Placeholder = "Cutscene2Teacher", Value = suggestion },
						Buttons = { "Cancel", "Add" },
					})
					if choice == "Add" and tag and tag ~= "" then
						add({ Id = uniqueId(document, if selected then selected.Name else tag), Source = "Tag", Tag = tag })
					end
				end,
			},
			{
				Text = "Selected model as template",
				Hint = "Source Template",
				Enabled = selected ~= nil and selected:IsA("PVInstance"),
				OnClick = function()
					add({ Id = uniqueId(document, selected.Name), Source = "Template", Template = selected })
				end,
			},
			{
				Text = "Player role…",
				Hint = "Source Role",
				OnClick = function()
					local choice, role = app:Modal({
						Title = "Player role",
						Text = "A role is filled by one of the players (Student1 to Student4 in Chapter 2).",
						Input = { Value = "Student" .. (#document:GetRoles() + 1) },
						Buttons = { "Cancel", "Add" },
					})
					if choice == "Add" and role and role ~= "" then
						add({ Id = uniqueId(document, role), Source = "Role", Role = role, Mode = "Original", Portrait = "Headshot", Anchor = false })
					end
				end,
			},
			{
				Text = "All players",
				Hint = "Source Group",
				OnClick = function()
					add({ Id = uniqueId(document, "Students"), Source = "Group", Group = "Students", Mode = "Original", Portrait = "None", Anchor = false })
				end,
			},
		}
		return UI.Menu.Show(items, { Anchor = anchor, AlignRight = true, MinWidth = 250 })
	end
end
