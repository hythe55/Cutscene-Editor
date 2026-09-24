local App = require(script.App)

return setmetatable({
	App = App,
	Mount = function(plugin, container, deps)
		return App.new(plugin, container, deps)
	end,
}, {
	__call = function(_, plugin, container, deps)
		return App.new(plugin, container, deps)
	end,
})
