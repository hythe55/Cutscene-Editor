local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fallback = require(script.Parent.Fallback.DialogueBox)
local Copy = require(script.Parent.Util.Copy)
local Lines = require(script.Parent.Lines)

local Speech = {}

local DEFAULT_TYPE_SPEED = 40
local SEARCH_STEPS = 40
local PROBE_ELAPSED = 1e6

local function graphemes(text)
	local count = 0
	local ok = pcall(function()
		for _ in utf8.graphemes(text) do
			count += 1
		end
	end)
	return if ok then count else utf8.len(text) or #text
end

local function readField(object, field)
	local ok, value = pcall(function()
		return object[field]
	end)
	return if ok then value else nil
end

local function readNumber(object, field)
	local value = readField(object, field)
	return if type(value) == "number" then value else nil
end

local function typingTime(source, text, speed, mood)
	local method = readField(source, "TypingTime")
	if type(method) == "function" then
		local ok, value = pcall(method, text, speed, mood)
		if ok and type(value) == "number" and value == value and value >= 0 then
			return value
		end
	end
	return math.max(graphemes(text) - 1, 0) / (speed or DEFAULT_TYPE_SPEED)
end

local function resolvePath(path)
	if type(path) ~= "string" then
		return nil
	end
	path = string.gsub(path, "^game%.", "")
	if path == "" then
		return nil
	end
	local segments = string.split(path, ".")
	local ok, current = pcall(game.FindService, game, segments[1])
	if not ok or not current then
		current = game:FindFirstChild(segments[1])
	end
	for i = 2, #segments do
		if not current then
			return nil
		end
		current = current:FindFirstChild(segments[i])
	end
	return current
end

local function cloneTemplate(template)
	local copy = Copy.Clone(template)
	if copy then
		copy.Archivable = false
	end
	return copy
end

function Speech:ActorForSpeaker(id)
	if not id or id == "" then
		return nil
	end
	local actors = self.Timeline.Actors
	if actors[id] then
		return actors[id]
	end
	for _, actor in actors do
		if actor.RoleId == id then
			return actor
		end
	end
	return nil
end

function Speech:ResolveSpeaker(id)
	local info = { Name = id or "", PortraitKind = "None" }
	local actor = self:ActorForSpeaker(id)
	if actor then
		local attributes = actor.Attributes
		info.Actor = actor
		info.Name = if attributes.DisplayName ~= "" then attributes.DisplayName else actor.Id
		info.PortraitKind = attributes.Portrait
		info.PortraitJoint = attributes.PortraitJoint
		local player = actor.Players and actor.Players[1]
		if player then
			info.UserId = player.UserId
			info.Name = player.DisplayName
		end
		return info
	end
	local userId = id and self.Roles[id]
	if userId then
		local player = Players:GetPlayerByUserId(userId)
		info.UserId = userId
		info.Name = if player then player.DisplayName else id
		info.PortraitKind = "Headshot"
	end
	return info
end

local function registers(folder)
	local path = folder and folder:GetAttribute("DialogueModule")
	return type(path) == "string" and path ~= ""
end

function Speech:_dialogueRegistry()
	local parent = self.Timeline.Folder.Parent
	if registers(parent) then
		return parent
	end
	local cutscenes = ReplicatedStorage:FindFirstChild("Cutscenes")
	return if registers(cutscenes) then cutscenes else nil
end

function Speech:DialogueProvider()
	if self.Provider == nil then
		self.Provider = Fallback
		local registry = self:_dialogueRegistry()
		if registry then
			local path = registry:GetAttribute("DialogueModule")
			local module = resolvePath(path)
			local ok, provider = false, nil
			if module and module:IsA("ModuleScript") then
				ok, provider = pcall(require, module)
			end
			if ok and type(provider) == "table" and type(provider.new) == "function" then
				self.Provider = provider
				local gui = resolvePath(registry:GetAttribute("DialogueGui"))
				self.ProviderGui = if gui and gui:IsA("LayerCollector") then gui else nil
			else
				warn(`Timeline: dialogue provider "{path}" could not be loaded ({provider}); using the built-in box`)
			end
		end
	end
	return self.Provider, self.ProviderGui
end

function Speech:_buildBox(provider, template)
	local gui = template and cloneTemplate(template)
	if gui then
		self:Track(gui)
	end
	local ok, box = pcall(provider.new, { Gui = gui, GuiParent = self.GuiParent, Preview = self.Preview })
	if ok and type(box) == "table" then
		self:OnCleanup(function()
			box:Destroy()
		end)
		return box
	end
	warn(`Timeline: dialogue box could not be built: {box}`)
	if gui then
		gui:Destroy()
	end
	return nil
end

function Speech:Dialogue()
	local options = self.Timeline.Options
	if options.DialogueBox then
		return options.DialogueBox
	end
	if self.Box == nil then
		self.Box = false
		local provider, template = self:DialogueProvider()
		local box = self:_buildBox(provider, template)
		if not box and provider ~= Fallback then
			box = self:_buildBox(Fallback)
		end
		self.Box = box or false
	end
	return self.Box or nil
end

function Speech:SetActiveSpeaker(id, talking)
	if id == nil then
		self.SpeakerOverride = nil
	else
		self.SpeakerOverride = id
		self.SpeakerTalking = talking ~= false
	end
end

function Speech:ActiveSpeaker()
	local override = self.SpeakerOverride
	if override == "" then
		override = false
	end
	local overrideId
	if override then
		local actor = self:ActorForSpeaker(override)
		overrideId = if actor then actor.Id else override
	end
	local t = self.Time
	local current
	for _, line in self.Lines do
		if line.Start > t then
			break
		end
		if t < line.Finish then
			current = line
		end
	end
	if current then
		if current.ActorId == nil then
			local actor = self:ActorForSpeaker(current.Speaker)
			current.ActorId = if actor then actor.Id else false
		end
		local id = current.ActorId or nil
		if overrideId and overrideId == id and not self.Seeking then
			return id, self.SpeakerTalking
		end
		return id, t < self:_talkEnd(current)
	end
	if overrideId then
		return overrideId, self.SpeakerTalking
	end
	return nil, false
end

local function typingEnd(box, line, limit)
	local method = box and readField(box, "VisibleCharacters")
	if type(method) ~= "function" then
		return nil
	end
	local ok, full = pcall(method, box, line, PROBE_ELAPSED)
	if not ok or type(full) ~= "number" or full ~= full then
		return nil
	end
	local function reached(elapsed)
		local okAt, count = pcall(method, box, line, elapsed)
		return okAt and type(count) == "number" and count >= full
	end
	if not reached(limit) then
		return limit
	end
	local low, high = 0, limit
	for _ = 1, SEARCH_STEPS do
		local middle = (low + high) / 2
		if reached(middle) then
			high = middle
		else
			low = middle
		end
	end
	return high
end

function Speech:_talkEnd(line)
	if line.TalkEnd then
		return line.TalkEnd
	end
	local props = line.Props
	local speed = if props.TypeSpeed > 0 then props.TypeSpeed else nil
	local previous = Lines.Previous(self.Lines, line)
	local probe = {
		Speaker = (Lines.Speaker(self, props.Speaker)),
		Text = Lines.Substitute(props.Text or "", self),
		TypeSpeed = speed,
		Mood = props.Mood or "Normal",
		PreviousSpeaker = if previous then (Lines.Speaker(self, previous.Speaker)) else nil,
	}
	local limit = props.Duration * props.Speed
	local typing = typingEnd(self:Dialogue(), probe, limit)
	if not typing then
		local source = self.Timeline.Options.DialogueBox or self:DialogueProvider()
		typing = (readNumber(source, "StartDelay") or 0) + typingTime(source, probe.Text, speed, props.Mood)
	end
	line.TalkEnd = props.Start + math.min(props.Duration, typing / props.Speed)
	return line.TalkEnd
end

function Speech:AddLine(props)
	table.insert(self.Lines, {
		Start = props.Start,
		Finish = props.Start + props.Duration,
		Speaker = props.Speaker,
		Props = props,
	})
	Lines.Link(self.Lines)
end

return Speech
