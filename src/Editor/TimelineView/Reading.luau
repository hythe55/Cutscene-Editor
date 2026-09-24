local Provider = require(script.Parent.Parent.Preview.Provider)

local Reading = {}
Reading.__index = Reading

function Reading.new(view)
	local self = setmetatable({}, Reading)
	self.View = view
	self.Key = nil
	self.Source = nil
	self.Cache = {}
	return self
end

function Reading:Reset()
	self.Key = nil
	self.Source = nil
	table.clear(self.Cache)
end

function Reading:_resolve()
	local app = self.View.App
	local deps = app.Deps
	local fallback = deps and deps.FallbackDialogueBox
	local document = app.Document
	local ok, info = pcall(Provider.Resolve, document and document.Folder)
	if ok and info.Kind == "Game" and info.Module then
		if self.Key == info.Module and self.Source then
			return self.Source, info.Module
		end
		local loaded = Provider.Load(info)
		if type(loaded) == "table" and type(loaded.ReadingTime) == "function" then
			return loaded, info.Module
		end
	end
	return fallback, fallback
end

function Reading:Refresh()
	local source, key = self:_resolve()
	if key ~= self.Key then
		self.Key = key
		self.Source = source
		table.clear(self.Cache)
		return true
	end
	self.Source = source
	return false
end

function Reading:Provider()
	if not self.Source then
		self:Refresh()
	end
	return self.Source
end

function Reading:Time(text, typeSpeed, mood)
	local source = self:Provider()
	if type(source) ~= "table" or type(source.ReadingTime) ~= "function" then
		return nil
	end
	text = tostring(text or "")
	local speed = if type(typeSpeed) == "number" and typeSpeed > 0 then typeSpeed else nil
	local moodName = if type(mood) == "string" and mood ~= "" then mood else nil
	local key = table.concat({ text, tostring(speed), tostring(moodName) }, "\0")
	local cached = self.Cache[key]
	if cached == nil then
		local ok, value = pcall(source.ReadingTime, text, speed, moodName)
		cached = if ok and type(value) == "number" and value == value then value else false
		self.Cache[key] = cached
	end
	return if cached == false then nil else cached
end

return Reading
