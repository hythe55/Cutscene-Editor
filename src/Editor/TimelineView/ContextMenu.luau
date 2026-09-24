local UI = require(script.Parent.Parent.UI)
local Actions = require(script.Parent.Actions)

local ContextMenu = {}

local function selectedClips(app)
	return app:GetSelectedClips()
end

local function clipItems(view, hit)
	local app = view.App
	local item = hit.Item
	local clips = selectedClips(app)
	local count = #clips
	local plural = if count > 1 then ` {count} clips` else ""
	local locked = item.Locked
	local t = app.Time
	local splittable = t > item.Start + 1e-3 and t < item.Start + item.Duration - 1e-3
	local items = {
		{ Header = true, Text = string.upper(if count > 1 then `{count} clips` else item.Clip.Name) },
	}
	if item.Kind == "Animation" then
		table.insert(items, { Text = "Edit poses", Hint = "Double-click", OnClick = function()
			Actions.OpenTool(view, item)
		end })
	elseif item.Kind == "Camera" or item.Kind == "Move" then
		table.insert(items, { Text = "Edit keys", Hint = "Double-click", OnClick = function()
			Actions.OpenTool(view, item)
		end })
	end
	if item.Kind == "Camera" then
		table.insert(items, {
			Text = "Set camera key from view",
			Enabled = not locked,
			Tooltip = "Adds a key at the playhead from the editor camera, or updates the key already there",
			OnClick = function()
				Actions.CameraKeyFromView(view, item)
			end,
		})
	end
	if item.Kind == "Dialogue" and item.Need then
		table.insert(items, {
			Text = string.format("Fit to reading time (%.1fs)", item.Need),
			Enabled = not locked,
			OnClick = function()
				Actions.FitReading(view, item)
			end,
		})
	end
	if #items > 1 then
		table.insert(items, { Separator = true })
	end
	table.insert(items, { Text = "Split at playhead", Hint = "S", Enabled = splittable and not locked, OnClick = function()
		Actions.Split(view)
	end })
	table.insert(items, { Text = "Duplicate" .. plural, Hint = "Ctrl+D", OnClick = function()
		Actions.Duplicate(view)
	end })
	table.insert(items, { Text = "Rename", Enabled = count <= 1, OnClick = function()
		Actions.Rename(view, item.Clip)
	end })
	table.insert(items, { Text = "Select in Explorer", OnClick = function()
		Actions.Explorer(clips)
	end })
	table.insert(items, { Separator = true })
	table.insert(items, { Text = "Delete" .. plural, Hint = "Del", Danger = true, Enabled = not locked, OnClick = function()
		Actions.Delete(view)
	end })
	return items
end

local function laneItems(view, hit)
	local app = view.App
	local row = hit.Row
	local track = row.Track
	local kind = row.Kind
	local t = math.max(hit.Time, 0)
	local locked = row.Info and row.Info.Locked
	return {
		{ Header = true, Text = string.upper(track.Name) },
		{
			Text = string.format("Add %s clip here", kind),
			Hint = string.format("%.2fs", math.round(t * 30) / 30),
			Enabled = not locked,
			OnClick = function()
				Actions.AddClip(view, track, t)
			end,
		},
		{
			Text = "Add clip at playhead",
			Enabled = not locked,
			OnClick = function()
				Actions.AddClip(view, track, app.Time)
			end,
		},
		{ Separator = true },
		{ Text = "Select all clips on this track", OnClick = function()
			local list = {}
			for _, item in view.Model.ByTrack[track] or {} do
				table.insert(list, item.Clip)
			end
			app:Select(list, "Replace")
		end },
		{ Text = "Select track in Explorer", OnClick = function()
			Actions.Explorer({ track })
		end },
	}
end

function ContextMenu.Items(view, hit)
	if hit.Item then
		return clipItems(view, hit)
	elseif hit.Row and hit.Row.Type == "Track" then
		return laneItems(view, hit)
	end
	return nil
end

function ContextMenu.Show(view, hit, position)
	local items = ContextMenu.Items(view, hit)
	if not items then
		return nil
	end
	view.Hover:HideTip()
	return UI.Menu.Show(items, { Position = position, MinWidth = 210 })
end

return ContextMenu
