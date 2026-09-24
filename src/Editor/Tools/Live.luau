local Live = {}

function Live.Timeline(app)
	local preview = app.Preview
	if preview and preview.Active and not preview.Suspended then
		return preview.Timeline
	end
	return nil
end

function Live.Context(app)
	local timeline = Live.Timeline(app)
	return timeline and timeline.Context
end

function Live.Ensure(app)
	local preview = app.Preview
	if not preview or not app.Document then
		return false
	end
	if not preview.Active then
		preview:Start(app.Time)
	end
	return Live.Timeline(app) ~= nil
end

function Live.Entry(timeline, clip)
	if not timeline or not timeline.Phases or not clip then
		return nil
	end
	local track = clip.Parent
	for _, phase in timeline.Phases do
		for _, group in phase.Groups do
			for _, entry in group.Entries do
				if entry.Name == clip.Name and entry.Track and entry.Track.Instance == track then
					return entry
				end
			end
		end
	end
	return nil
end

function Live.State(app, clip)
	local entry = Live.Entry(Live.Timeline(app), clip)
	return entry and entry.State
end

function Live.Reseek(app)
	local timeline = Live.Timeline(app)
	if not timeline then
		return
	end
	local preview = app.Preview
	local session = preview.Session
	timeline:Seek(timeline.TimePosition)
	if session and session.Lock then
		session.Lock:Write()
	end
end

function Live.Actor(app, actorId)
	local ctx = Live.Context(app)
	return ctx and ctx:GetActor(actorId)
end

function Live.Rig(app, actorId)
	local ctx = Live.Context(app)
	if not ctx then
		return nil
	end
	local ok, rig = pcall(ctx.GetRig, ctx, actorId)
	return if ok then rig else nil
end

function Live.JointFrame(rig, key)
	local joint = rig and rig.Joints[key]
	if not joint then
		return nil
	end
	local ok, cframe = pcall(rig.JointFrame, rig, key)
	if ok and cframe then
		return cframe
	end
	local instance = joint.Instance
	if instance:IsA("Bone") then
		return instance.TransformedWorldCFrame
	end
	return nil
end

function Live.JointCFrame(app, actorId, joint, t)
	local ctx = Live.Context(app)
	if not ctx or not actorId or actorId == "" then
		return nil
	end
	local ok, cframe
	if t and math.abs(t - (ctx.Timeline.TimePosition or 0)) > 1e-4 then
		ok, cframe = pcall(ctx.ProbeJointCFrame, ctx, actorId, if joint ~= "" then joint else nil, t)
	else
		ok, cframe = pcall(ctx.GetJointCFrame, ctx, actorId, if joint ~= "" then joint else nil)
	end
	return if ok and typeof(cframe) == "CFrame" then cframe else nil
end

function Live.Locked(clip)
	local track = clip and clip.Parent
	return track ~= nil and track:GetAttribute("Locked") == true
end

function Live.Patch(app, clip, fn)
	local state = Live.State(app, clip)
	if not state then
		return false
	end
	fn(state)
	return true
end

return Live
