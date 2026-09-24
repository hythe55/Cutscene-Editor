local Lines = {}

Lines.ChainGap = 0.35

local function named(value)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

function Lines.Link(list)
	table.sort(list, function(a, b)
		return a.Start < b.Start
	end)
	for index, line in list do
		local following
		for later = index + 1, #list do
			if list[later].Start > line.Start then
				following = list[later]
				break
			end
		end
		line.Next = following
		line.Gap = if following then following.Start - line.Finish else nil
		line.KeepOpen = following ~= nil and line.Gap <= Lines.ChainGap
	end
end

function Lines.Previous(list, line)
	local best
	for _, other in list do
		if other.Next == line and other.KeepOpen and (not best or other.Start > best.Start) then
			best = other
		end
	end
	return best
end

function Lines.Covered(list, t)
	for _, line in list do
		if line.Start <= t and t < line.Finish then
			return true
		end
	end
	return false
end

function Lines.HeldAt(list, t)
	if Lines.Covered(list, t) then
		return nil
	end
	local best
	for _, line in list do
		if line.KeepOpen and t >= line.Finish and t < line.Next.Start and (not best or line.Start > best.Start) then
			best = line
		end
	end
	return best
end

function Lines.Substitute(text, ctx)
	return (string.gsub(text, "{([%w_]+)}", function(id)
		local resolved = ctx:ResolveSpeaker(id)
		return resolved and resolved.Name or id
	end))
end

local function actorIdOf(resolved, fallback)
	local actor = resolved and resolved.Actor
	if type(actor) == "table" then
		return actor.Id or fallback
	elseif type(actor) == "string" then
		return actor
	end
	return fallback
end

function Lines.Speaker(ctx, id)
	local speakerId = named(id)
	local resolved = speakerId and ctx:ResolveSpeaker(speakerId) or { Name = "" }
	local actorId = actorIdOf(resolved, speakerId)
	local kind = resolved.PortraitKind
	local info = { Id = actorId, Name = resolved.Name or "", Portrait = kind }
	if kind == "None" then
		return info, actorId
	end
	info.UserId = resolved.UserId
	local actor = resolved.Actor
	if type(actor) == "string" then
		actor = ctx:GetActor(actor)
	end
	local model = type(actor) == "table" and actor.Model or nil
	if model then
		info.PortraitModel = model
		info.PortraitJoint = resolved.PortraitJoint
	end
	return info, actorId
end

return Lines
