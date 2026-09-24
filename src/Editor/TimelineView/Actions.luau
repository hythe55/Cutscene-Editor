local SelectionService = game:GetService("Selection")

local Actions = {}

local TOOLS = { Animation = { "PoseTool", "Pose" }, Camera = { "KeyTool", "Keys" }, Move = { "KeyTool", "Keys" } }
local OPEN_METHODS = { "Open", "Edit", "SetClip", "Show", "Focus" }
local VIEW_METHODS = { "AddKeyFromView", "KeyFromView", "SetKeyFromView" }

local function selected(view)
	local list = {}
	for _, clip in view.App:GetSelectedClips() do
		table.insert(list, clip)
	end
	return list
end

local function call(tool, methods, ...)
	if type(tool) ~= "table" or tool.Placeholder then
		return false
	end
	for _, name in methods do
		if type(tool[name]) == "function" then
			return true, pcall(tool[name], tool, ...)
		end
	end
	return false
end

function Actions.Delete(view, clips)
	local app = view.App
	clips = clips or selected(view)
	if #clips == 0 or not app.Document then
		return 0
	end
	local count = app.Document:DeleteClips(clips)
	if count == nil then
		return 0
	elseif count > 0 then
		app:Notify(`Deleted {count} clip{if count == 1 then "" else "s"}`, "Info")
	else
		app:Notify("Nothing deleted: the track is locked", "Warn")
	end
	return count
end

function Actions.Duplicate(view, clips)
	local app = view.App
	clips = clips or selected(view)
	if #clips == 0 or not app.Document then
		return nil
	end
	local copies = app.Document:DuplicateClips(clips)
	if copies and #copies > 0 then
		app:Select(copies, "Replace")
	end
	return copies
end

function Actions.Split(view, t)
	local app = view.App
	t = t or app.Time
	local targets = {}
	for _, clip in selected(view) do
		local item = view.Model.ByClip[clip]
		if item and t > item.Start + 1e-3 and t < item.Start + item.Duration - 1e-3 then
			table.insert(targets, item)
		end
	end
	if #targets == 0 then
		app:Notify("Put the playhead inside a selected clip to split it", "Info")
		return {}
	end
	local seconds = {}
	for _, item in targets do
		local second = app.Document:SplitClip(item.Clip, t)
		if second then
			table.insert(seconds, second)
		end
	end
	if #seconds > 0 then
		app:Select(seconds, "Replace")
	end
	return seconds
end

function Actions.SelectAll(view)
	local list = {}
	for _, item in view.Model.Items do
		table.insert(list, item.Clip)
	end
	view.App:Select(list, "Replace")
end

function Actions.Frame(view)
	local app = view.App
	local first, last = math.huge, -math.huge
	for clip in app.Selection.Clips do
		local item = view.Model.ByClip[clip]
		if item then
			first = math.min(first, item.Start)
			last = math.max(last, item.Start + item.Duration)
		end
	end
	if first == math.huge then
		app:FitView()
		return
	end
	local span = math.max(last - first, 0.5)
	app:SetView({ PixelsPerSecond = math.max(view:Width() - 60, 60) / (span * 1.1), ScrollTime = math.max(first - span * 0.05, 0) })
	local item = view.Model.ByClip[app.Selection.Primary]
	local row = item and item.Row
	if row then
		local height = view:LaneHeight()
		if row.Y < app.ScrollY or row.Y + row.Height > app.ScrollY + height then
			app:SetScrollY(row.Y - height / 2)
		end
	end
end

function Actions.Step(view, amount)
	local app = view.App
	local t = math.round((app.Time + amount) * 30) / 30
	app:SetTime(math.clamp(t, 0, math.max(view.Model.Length, 0)))
end

function Actions.AddClip(view, track, t)
	local app = view.App
	if not app.Document or track:GetAttribute("Locked") == true then
		return nil
	end
	local clip = app.Document:AddClip(track, math.max(math.round(t * 30) / 30, 0))
	if clip then
		app:Select(clip, "Replace")
	end
	return clip
end

function Actions.Rename(view, clip)
	local app = view.App
	task.spawn(function()
		local choice, text = app:Modal({
			Title = "Rename clip",
			Input = { Value = clip.Name },
			Buttons = { "Cancel", "Rename" },
		})
		if choice == "Rename" and text and text ~= "" and app.Document then
			app.Document:Rename(clip, text)
		end
	end)
end

function Actions.FitReading(view, item)
	local app = view.App
	if not item.Need or not app.Document then
		return nil
	end
	return app.Document:SetClipTiming(item.Clip, item.Start, math.ceil(item.Need * 30 - 1e-6) / 30)
end

function Actions.Explorer(clips)
	SelectionService:Set(clips)
end

function Actions.OpenTool(view, item)
	local app = view.App
	local entry = TOOLS[item.Kind]
	if not entry then
		return false
	end
	app:Select(item.Clip, "Replace")
	app:ShowTab(entry[2])
	local tool = app.Tools and app.Tools[entry[1]]
	local found, ok, err = call(tool, OPEN_METHODS, item.Clip)
	if found and not ok then
		app:Notify(`{entry[1]} could not open {item.Clip.Name}: {err}`, "Error")
	end
	return true
end

local function viewCamera(app)
	local session = app.Preview and app.Preview.Session
	local lock = session and session.Lock
	if lock and lock.Engaged and lock.Saved then
		return lock.Saved.CFrame, lock.Saved.FieldOfView
	end
	local camera = workspace.CurrentCamera
	return camera.CFrame, camera.FieldOfView
end

function Actions.CameraKeyFromView(view, item)
	local app = view.App
	local document = app.Document
	local found, ok, err = call(app.Tools and app.Tools.KeyTool, VIEW_METHODS, item.Clip)
	if found then
		if not ok then
			app:Notify("Key from view failed: " .. tostring(err), "Error")
		end
		return
	end
	local cframe, fov = viewCamera(app)
	if item.Anchor ~= "" then
		local timeline = app.Preview and app.Preview.Timeline
		local ctx = timeline and timeline.Context
		local anchorOk, anchor = false, nil
		if ctx then
			anchorOk, anchor = pcall(ctx.GetJointCFrame, ctx, item.Anchor, if item.AnchorJoint ~= "" then item.AnchorJoint else nil)
		end
		if not anchorOk or typeof(anchor) ~= "CFrame" then
			app:Notify(`Start the preview so the anchor "{item.Anchor}" can be found`, "Warn")
			return
		end
		cframe = anchor:ToObjectSpace(cframe)
	end
	local source = math.clamp((app.Time - item.Start) * item.Speed, 0, item.Duration * item.Speed)
	source = math.round(source * 10000) / 10000
	for _, key in item.Keys do
		if math.abs(key.Source - source) <= 1 / 60 then
			document:SetKey(key.Instance, cframe, { FOV = fov })
			app:SelectKey(key.Instance)
			return key.Instance
		end
	end
	local key = document:AddKey(item.Clip, source, cframe, { FOV = fov })
	if key then
		app:SelectKey(key)
	end
	return key
end

return Actions
