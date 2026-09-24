local UI = require(script.Parent.Parent.UI)
local Widgets = require(script.Parent.Widgets)
local PoseStrip = require(script.Parent.PoseStrip)

local PosePanel = {}
PosePanel.__index = PosePanel

function PosePanel.new(tool, parent)
	local self = setmetatable({}, PosePanel)
	self.Tool = tool
	self.Root = UI.Create("Frame", { Name = "PoseTool", Parent = parent, Size = UDim2.fromScale(1, 1) })
	self.Empty = Widgets.Empty(self.Root, "No animation clip selected", "Select an Animation clip, scrub to the frame that looks wrong, then click the joint in the viewport and drag its rings.")
	local page = Widgets.Page(self.Root)
	self.Page = page
	local header = Widgets.Row(page, 1, 20)
	self.Title = UI.Label({ Parent = header, LayoutOrder = 1, Text = "", Font = "Bold", TextSize = 14, Size = UDim2.new(1, -70, 1, 0) })
	self.SmoothButton = Widgets.Button(header, "Smooth", function()
		tool:ToggleSmooth()
	end, { LayoutOrder = 2, Height = 20, TextSize = 12, Tooltip = "Velocity-continuous playback: pass keys glide, stop keys ease to rest" })
	self.Status = Widgets.Caption(page, "", 2)
	local stripRow = Widgets.Row(page, 3, 30)
	Widgets.Button(stripRow, "<", function()
		tool:StepKeyframe(-1)
	end, { LayoutOrder = 1, Height = 30, PaddingX = 6, Tooltip = "Previous keyframe" })
	self.Strip = PoseStrip.new({
		Parent = stripRow,
		LayoutOrder = 2,
		OnKeyframe = function(keyframe)
			tool:JumpToKeyframe(keyframe)
		end,
		OnScrub = function(clipTime)
			tool:ScrubClip(clipTime)
		end,
	})
	self.Strip.Root.Size = UDim2.new(1, -56, 0, 30)
	Widgets.Button(stripRow, ">", function()
		tool:StepKeyframe(1)
	end, { LayoutOrder = 3, Height = 30, PaddingX = 6, Tooltip = "Next keyframe" })
	local jointRow = Widgets.Row(page, 4)
	self.JointDropdown = UI.Dropdown({
		Parent = jointRow,
		LayoutOrder = 1,
		Size = UDim2.new(1, -118, 0, Widgets.Height),
		Height = Widgets.Height,
		Searchable = true,
		Placeholder = "Pick a joint",
		Options = function()
			return tool:JointOptions()
		end,
		OnChanged = function(value)
			tool:SelectJoint(value)
		end,
	})
	self.PickButton = Widgets.Button(jointRow, "Pick", function()
		tool:SetPicking(not tool.Picking)
	end, { LayoutOrder = 2, Icon = "Search", Tooltip = "Click the rig in the viewport to choose the nearest joint" })
	Widgets.Button(jointRow, "Up", function()
		tool:SelectParent()
	end, { LayoutOrder = 3, Tooltip = "Select the parent joint" })
	local modeRow = Widgets.Row(page, 5)
	self.ModeControl = Widgets.Segmented(modeRow, {
		{ Value = "Rotate", Text = "Rotate", Tooltip = "Rings turn the joint around its own axes" },
		{ Value = "Move", Text = "Move", Tooltip = "Arrows move the joint (for COG and roots)" },
	}, tool.Mode, function(mode)
		tool:SetMode(mode)
	end, { LayoutOrder = 1 })
	self.StepControl = Widgets.Segmented(modeRow, {
		{ Value = 1, Text = "1°" },
		{ Value = 5, Text = "5°" },
		{ Value = 15, Text = "15°" },
	}, tool.Step, function(step)
		tool:SetStep(step)
	end, { LayoutOrder = 2 })
	local nudgeRow = Widgets.Row(page, 6)
	for index, entry in { { "X", -1 }, { "X", 1 }, { "Y", -1 }, { "Y", 1 }, { "Z", -1 }, { "Z", 1 } } do
		Widgets.Button(nudgeRow, entry[1] .. (if entry[2] > 0 then "+" else "−"), function()
			tool:Nudge(Enum.Axis[entry[1]], entry[2])
		end, { LayoutOrder = index, PaddingX = 6, Tooltip = "Nudge the joint one step: degrees around its own axis in Rotate mode, studs along it in Move mode" })
	end
	local keyRow = Widgets.Wrap(page, 7)
	self.KeyButton = Widgets.Button(keyRow, "Key pose at playhead", function()
		tool:KeyPose()
	end, { LayoutOrder = 1, Icon = "Diamond", Style = "Primary", Tooltip = "Adds a keyframe here holding the current pose of every joint" })
	self.DeleteButton = Widgets.Button(keyRow, "Delete keyframe", function()
		tool:DeleteKeyframe()
	end, { LayoutOrder = 2, Style = "Danger" })
	local poseRow = Widgets.Wrap(page, 8)
	Widgets.Button(poseRow, "Copy pose", function()
		tool:CopyPose()
	end, { LayoutOrder = 1, Tooltip = "Copies every joint of this clip at the playhead" })
	self.PasteButton = Widgets.Button(poseRow, "Paste pose", function()
		tool:PastePose()
	end, { LayoutOrder = 2, Tooltip = "Writes the copied pose into the keyframe at the playhead (adds one if needed)" })
	self.ResetButton = Widgets.Button(poseRow, "Reset joint", function()
		tool:ResetJoint()
	end, { LayoutOrder = 3, Tooltip = "Puts the joint back to its rest pose at this keyframe" })
	local roleRow = Widgets.Row(page, 9)
	UI.Label({ Parent = roleRow, LayoutOrder = 0, Text = "Key", TextSize = 12, TextColor3 = "Dim", Size = UDim2.fromOffset(24, Widgets.Height) })
	self.RoleControl = Widgets.Segmented(roleRow, {
		{ Value = "Pass", Text = "Pass", Tooltip = "Linear: motion flows through the key" },
		{ Value = "Stop", Text = "Stop", Tooltip = "CubicV2 InOut: eases to rest at the key" },
		{ Value = "Snap", Text = "Snap", Tooltip = "Keeps a deliberate In/Out/Constant snap" },
		{ Value = "Auto", Text = "Auto", Tooltip = "Pass where the motion continues, Stop where it turns or rests" },
	}, nil, function(role)
		tool:SetRole(role)
	end, { LayoutOrder = 1 })
	local scopeRow = Widgets.Row(page, 10)
	UI.Label({ Parent = scopeRow, LayoutOrder = 0, Text = "For", TextSize = 12, TextColor3 = "Dim", Size = UDim2.fromOffset(24, Widgets.Height) })
	self.ScopeControl = Widgets.Segmented(scopeRow, {
		{ Value = "Joint", Text = "This joint" },
		{ Value = "Keyframe", Text = "Whole keyframe" },
	}, tool.RoleScope, function(scope)
		tool:SetRoleScope(scope)
	end, { LayoutOrder = 1 })
	return self
end

function PosePanel:Refresh()
	local tool = self.Tool
	local info = tool.Info
	self.Empty.Instance.Visible = info == nil
	self.Page.Visible = info ~= nil
	if not info then
		return
	end
	local actor = info.Actor
	self.Title.Text = if actor and actor ~= "" then `{actor} · {info.Clip.Name}` else info.Clip.Name
	self.SmoothButton:SetActive(info.Smooth)
	self.Status.Text = tool:StatusText()
	self.Strip:Render(info, tool.ClipTime, tool.Keyframe, tool.Joint)
	if self.ShownJoint ~= tool.Joint then
		self.ShownJoint = tool.Joint
		self.JointDropdown:Set(tool.Joint)
	end
	self.PickButton:SetActive(tool.Picking)
	self.ModeControl:Set(tool.Mode)
	self.StepControl:Set(tool.Step)
	if self.StepUnits ~= tool.Mode then
		self.StepUnits = tool.Mode
		for value, button in self.StepControl.Buttons do
			button:SetText(if tool.Mode == "Move" then `{value / 10} st` else `{value}°`)
		end
	end
	self.DeleteButton:SetEnabled(tool.Keyframe ~= nil)
	self.PasteButton:SetEnabled(tool.Clipboard ~= nil)
	self.ResetButton:SetEnabled(tool.Joint ~= nil)
	self.KeyButton:SetEnabled(tool.ClipTime ~= nil)
	self.RoleControl:Set(tool:CurrentRole())
	self.ScopeControl:Set(tool.RoleScope)
end

function PosePanel:Destroy()
	self.Root:Destroy()
end

return PosePanel
