local CoreGui = game:GetService("CoreGui")
local SoundService = game:GetService("SoundService")

local Signal = require(script.Parent.Parent.Signal)

local Audition = {}

Audition.Changed = Signal.new()
Audition.Current = nil
Audition.MaxSeconds = 30

local function folder()
	local existing = CoreGui:FindFirstChild("CutsceneEditorAudition")
	if existing then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "CutsceneEditorAudition"
	created.Archivable = false
	created.Parent = CoreGui
	return created
end

function Audition.Play(sound, options)
	Audition.Stop()
	options = options or {}
	if not sound or not sound:IsA("Sound") or sound.SoundId == "" then
		return false
	end
	local archivable = sound.Archivable
	if not archivable then
		sound.Archivable = true
	end
	local ok, copy = pcall(sound.Clone, sound)
	if not archivable then
		sound.Archivable = false
	end
	if not ok or not copy then
		return false
	end
	copy.Name = "Audition"
	copy.Archivable = false
	copy.PlaybackSpeed = sound.PlaybackSpeed * (options.Speed or 1)
	copy.TimePosition = math.max(options.Offset or 0, 0)
	copy.Parent = folder()
	local played, err = pcall(SoundService.PlayLocalSound, SoundService, copy)
	if not played then
		copy:Destroy()
		warn("CutsceneEditor: sound preview failed: " .. tostring(err))
		return false
	end
	local token = {}
	Audition.Current = { Sound = copy, Source = sound, Token = token, Started = os.clock() }
	local seconds = math.min(options.Duration or math.huge, Audition.MaxSeconds)
	task.delay(seconds, function()
		local current = Audition.Current
		if current and current.Token == token then
			Audition.Stop()
		end
	end)
	Audition.Changed:Fire(sound)
	return true
end

function Audition.Stop()
	local current = Audition.Current
	Audition.Current = nil
	if not current then
		return
	end
	pcall(current.Sound.Stop, current.Sound)
	pcall(game.Destroy, current.Sound)
	local holder = CoreGui:FindFirstChild("CutsceneEditorAudition")
	if holder and #holder:GetChildren() == 0 then
		holder:Destroy()
	end
	Audition.Changed:Fire(nil)
end

function Audition.IsPlaying(sound)
	local current = Audition.Current
	return current ~= nil and (sound == nil or current.Source == sound)
end

return Audition
