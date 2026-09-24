local AssetService = game:GetService("AssetService")
local LogService = game:GetService("LogService")
local Selection = game:GetService("Selection")

local Collect = require(script.Parent.Collect)
local Creator = require(script.Parent.Creator)

local Upload = {}

Upload.Gap = 0.4
Upload.RetryWait = 5
Upload.Retries = 2

local function contains(text, words)
	text = string.lower(text)
	for _, word in words do
		if string.find(text, word, 1, true) then
			return true
		end
	end
	return false
end

function Upload.Direct(app, hooks, item, creator)
	local create = hooks and hooks.Create or function(object, params)
		return AssetService:CreateAssetAsync(object, Enum.AssetType.Animation, params)
	end
	local prepared, object = pcall(Collect.Prepare, app.Deps, item)
	if not prepared then
		return { Error = tostring(object) }
	end
	local messages = {}
	local connection = LogService.MessageOut:Connect(function(message, kind)
		if kind == Enum.MessageType.MessageWarning or kind == Enum.MessageType.MessageError then
			table.insert(messages, message)
		end
	end)
	local ok, result, detail = pcall(create, object, Creator.Params(creator, item))
	connection:Disconnect()
	Collect.Cleanup()
	if ok and result == Enum.CreateAssetResult.Success then
		local id = Collect.ParseId(detail)
		return if id then { Id = id } else { Error = "Roblox reported success but returned no id" }
	end
	local message
	if not ok then
		message = tostring(result)
	else
		message = if typeof(result) == "EnumItem" then result.Name else "no result"
		if detail ~= nil and tostring(detail) ~= "" then
			message ..= ": " .. tostring(detail)
		end
	end
	local everything = message .. " " .. table.concat(messages, " ")
	return {
		Error = message,
		Unavailable = (ok and result == nil) or contains(everything, { "not available yet", "beta feature", "lacking capability", "cannot be called" }),
		Denied = ok and result == Enum.CreateAssetResult.PermissionDenied,
		Limited = contains(everything, { "too many requests", "rate limit", "ratelimit", "429" }),
	}
end

function Upload.WithRetry(app, hooks, item, creator, stopped)
	local result
	for attempt = 0, Upload.Retries do
		result = Upload.Direct(app, hooks, item, creator)
		if not result.Limited or attempt == Upload.Retries or stopped() then
			break
		end
		app:Notify(`Roblox asked to slow down; retrying {item.Name} in {Upload.RetryWait} s`, "Warn")
		task.wait(Upload.RetryWait)
	end
	return result
end

function Upload.ByHand(app, ask, hooks, item, creator, title)
	local prepared, object = pcall(Collect.Prepare, app.Deps, item)
	if not prepared then
		return { Error = tostring(object) }
	end
	local save = hooks and hooks.Save or function(plugin)
		return plugin:SaveSelectedToRoblox()
	end
	local function open()
		local previous = Selection:Get()
		Selection:Set({ object })
		local ok, err = pcall(save, app.Plugin, object)
		pcall(Selection.Set, Selection, previous)
		if not ok then
			app:Notify("Could not open Roblox's upload window: " .. tostring(err), "Error")
		end
	end
	open()
	local result
	while not result do
		local choice, text = ask({
			Title = title,
			Text = `Roblox's upload window is open for this animation. Set the Creator to {Creator.Name(creator)}, finish the upload, then paste the id Roblox shows.`,
			Input = { Placeholder = "1234567890 or rbxassetid://1234567890" },
			Buttons = { "Stop", "Skip", "Open window again", "Save id" },
			Primary = "Save id",
			Width = 480,
		})
		if choice == "Save id" then
			local id = Collect.ParseId(text)
			if id then
				result = { Id = id }
			else
				app:Notify("That is not an asset id", "Warn")
			end
		elseif choice == "Open window again" then
			open()
		elseif choice == "Skip" then
			result = { Skipped = true }
		else
			result = { Stop = true }
		end
	end
	Collect.Cleanup()
	return result
end

return Upload
