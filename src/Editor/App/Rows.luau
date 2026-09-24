local JointGroups = require(script.Parent.Parent.JointGroups)

local Rows = {}

function Rows.Build(app)
	local rows = {}
	local y = 0
	local document = app.Document
	if not document then
		return rows, 0
	end
	for index, lane in document:GetLanes() do
		local collapsed = app:IsCollapsed(lane.Actor)
		table.insert(rows, {
			Type = "Group",
			Actor = lane.Actor,
			Lane = lane,
			Index = index,
			Collapsed = collapsed,
			Y = y,
			Height = app.GroupHeight,
		})
		y += app.GroupHeight
		if not collapsed then
			for trackIndex, info in lane.Tracks do
				local expandable = info.Kind == "Animation"
				local expanded = expandable and app:IsExpanded(info.Track)
				local trackRow = {
					Type = "Track",
					Actor = lane.Actor,
					Lane = lane,
					Track = info.Track,
					Kind = info.Kind,
					Info = info,
					Index = trackIndex,
					Expandable = expandable,
					Expanded = expanded,
					Y = y,
					Height = app.RowHeight,
				}
				table.insert(rows, trackRow)
				y += app.RowHeight
				if expanded then
					local ok, groups = pcall(JointGroups.ForTrack, document, info)
					for _, group in if ok then groups else {} do
						local groupExpanded = app:IsExpanded(info.Track, group.Name)
						table.insert(rows, {
							Type = "KeyGroup",
							Actor = lane.Actor,
							Lane = lane,
							Track = info.Track,
							Kind = info.Kind,
							Info = info,
							Parent = trackRow,
							Group = group.Name,
							Joints = group.Joints,
							Expanded = groupExpanded,
							Y = y,
							Height = app.SubRowHeight,
						})
						y += app.SubRowHeight
						if groupExpanded then
							for _, joint in group.Joints do
								table.insert(rows, {
									Type = "KeyJoint",
									Actor = lane.Actor,
									Lane = lane,
									Track = info.Track,
									Kind = info.Kind,
									Info = info,
									Parent = trackRow,
									Group = group.Name,
									Joint = joint,
									Joints = { joint },
									Y = y,
									Height = app.SubRowHeight,
								})
								y += app.SubRowHeight
							end
						end
					end
				end
			end
		end
	end
	return rows, y
end

function Rows.At(app, y)
	local rows = app:GetRows()
	for _, row in rows do
		if y >= row.Y and y < row.Y + row.Height then
			return row
		end
	end
	return nil
end

function Rows.ForTrack(app, track)
	local rows = app:GetRows()
	for _, row in rows do
		if row.Track == track and row.Type == "Track" then
			return row
		end
	end
	return nil
end

return Rows
