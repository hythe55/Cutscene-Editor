local Selection = game:GetService("Selection")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent.Parent.UI)
local Document = require(script.Parent.Parent.Document)

local function typing(app)
	local timeline = app.Features.TimelineView
	local keyboard = timeline and not timeline.Placeholder and timeline.Keyboard
	if keyboard then
		return keyboard:IsTyping()
	end
	for _, descendant in app.Widget:GetDescendants() do
		if descendant:IsA("TextBox") and descendant:IsFocused() then
			return true
		end
	end
	return UserInputService:GetFocusedTextBox() ~= nil
end

return function(Toolbar)
	Toolbar.Typing = typing

	function Toolbar:_key(input)
		local app = self.App
		if input.UserInputType ~= Enum.UserInputType.Keyboard or typing(app) then
			return
		end
		if input.KeyCode == Enum.KeyCode.C and not input:IsModifierKeyDown(Enum.ModifierKey.Ctrl) and not input:IsModifierKeyDown(Enum.ModifierKey.Meta) then
			if app.Document then
				app.Preview:ToggleCameraLock()
			end
		elseif input.KeyCode == Enum.KeyCode.Space then
			local timeline = app.Features.TimelineView
			if app.Document and (not timeline or timeline.Placeholder) then
				app.Preview:Toggle()
			end
		end
	end

	function Toolbar:OpenPicker()
		local app = self.App
		local items = { { Header = true, Text = "CUTSCENES" } }
		local list = Document.List()
		for _, folder in list do
			local ok, length = pcall(app.Deps.Timeline.GetLength, folder)
			table.insert(items, {
				Text = folder.Name,
				Hint = if ok then Toolbar.FormatTime(length) else nil,
				Checked = app.Document ~= nil and app.Document.Folder == folder,
				OnClick = function()
					app:OpenCutscene(folder)
				end,
			})
		end
		if #list == 0 then
			table.insert(items, { Text = "No cutscenes in this place", Enabled = false })
		end
		table.insert(items, { Separator = true })
		table.insert(items, {
			Text = "New cutscene…",
			Icon = "Plus",
			OnClick = function()
				require(script.Parent.Parent.App.Shell).PromptCreate(app)
			end,
		})
		table.insert(items, {
			Text = "Select folder in Explorer",
			Enabled = app.Document ~= nil,
			OnClick = function()
				Selection:Set({ app.Document.Folder })
			end,
		})
		table.insert(items, {
			Text = "Close cutscene",
			Enabled = app.Document ~= nil,
			OnClick = function()
				app:OpenCutscene(nil)
			end,
		})
		return UI.Menu.Show(items, { Anchor = self.Picker.Instance, MinWidth = 240 })
	end

	function Toolbar:Export()
		local app = self.App
		local module = script.Parent.Parent:FindFirstChild("Export")
		if not module or not module:IsA("ModuleScript") then
			app:Notify("Export is not installed in this build", "Warn")
			return
		end
		local ok, export = pcall(require, module)
		if not ok or type(export) ~= "table" then
			app:Notify("Export failed to load: " .. tostring(export), "Error")
			return
		end
		task.spawn(function()
			local success, err = pcall(function()
				for _, name in { "Run", "Start", "Open" } do
					if type(export[name]) == "function" then
						return export[name](app)
					end
				end
				if type(export.new) == "function" then
					local flow = self.ExportFlow
					if not flow then
						flow = export.new(app, app.Shell.Layer)
						self.ExportFlow = flow
					end
					for _, name in { "Run", "Start", "Open" } do
						if type(flow[name]) == "function" then
							return flow[name](flow)
						end
					end
				end
				error("the Export module has no Run, Start or Open")
			end)
			if not success then
				app:Notify("Export failed: " .. tostring(err), "Error")
			end
		end)
	end
end
