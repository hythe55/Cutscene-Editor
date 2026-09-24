local UI = require(script.Parent.Parent.Parent.UI)
local Context = require(script.Parent.Parent.Context)
local Basic = require(script.Parent.Basic)

local Pickers = {}

local JOINT_CACHE_SECONDS = 2

function Pickers.actor(entry, ctx)
	local app = ctx.App
	local widget = UI.Dropdown({
		Parent = ctx.Parent,
		Value = ctx.Value,
		AllowCustom = true,
		Placeholder = "(none)",
		Options = ctx.Options or function()
			return Context.ActorOptions(app, entry)
		end,
		OnChanged = function(value)
			ctx.Commit(value)
		end,
	})
	return Basic.Wrap(widget)
end

function Pickers.joint(_entry, ctx)
	local app = ctx.App
	local cache = { Actor = nil, Time = -math.huge, Options = nil }
	local function options()
		local actor = if ctx.JointActor then ctx.JointActor() else nil
		local now = os.clock()
		if cache.Options and cache.Actor == actor and now - cache.Time < JOINT_CACHE_SECONDS then
			return cache.Options
		end
		cache.Actor, cache.Time = actor, now
		cache.Options = Context.JointOptions(app, actor)
		return cache.Options
	end
	local widget = UI.Dropdown({
		Parent = ctx.Parent,
		Value = ctx.Value,
		Searchable = true,
		AllowCustom = true,
		Placeholder = "(pivot)",
		Options = options,
		OnChanged = function(value)
			ctx.Commit(value)
		end,
	})
	return Basic.Wrap(widget, {
		Invalidate = function()
			cache.Options = nil
		end,
	})
end

return Pickers
