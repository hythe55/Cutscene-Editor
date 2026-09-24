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
				table.insert(rows, {
					Type = "Track",
					Actor = lane.Actor,
					Lane = lane,
					Track = info.Track,
					Kind = info.Kind,
					Info = info,
					Index = trackIndex,
					Y = y,
					Height = app.RowHeight,
				})
				y += app.RowHeight
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
		if row.Track == track then
			return row
		end
	end
	return nil
end

return Rows
