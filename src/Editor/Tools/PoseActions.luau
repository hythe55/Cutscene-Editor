local Live = require(script.Parent.Live)
local PoseMath = require(script.Parent.PoseMath)
local PoseEdit = require(script.Parent.PoseEdit)

return function(PoseTool)
	function PoseTool:Open(clip)
		if clip and self.App.Selection.Primary ~= clip then
			self.App:Select(clip, "Replace")
		end
		self:Sync()
		return self.Info ~= nil
	end

	function PoseTool:CurrentRole()
		local keyframe = self.Keyframe
		if not keyframe then
			return nil
		end
		if self.RoleScope == "Keyframe" or not self.Joint then
			return (PoseMath.KeyframeRole(keyframe))
		end
		local pose = PoseMath.PoseOf(keyframe, self.Joint)
		return if pose and pose.Weight > 0 then PoseMath.Role(pose) else nil
	end

	function PoseTool:_editable()
		local app = self.App
		if not self.Info then
			return false
		end
		if app.Preview and app.Preview.Playing then
			app:Notify("Pause the preview before editing", "Warn")
			return false
		end
		if Live.Locked(self.Info.Clip) then
			app:Notify("This track is locked; unlock it to edit the pose", "Warn")
			return false
		end
		return true
	end

	function PoseTool:_ready(needJoint)
		local app = self.App
		if not self:_editable() then
			return false
		end
		if not self.ClipTime then
			app:Notify("Move the playhead inside the clip first", "Warn")
			return false
		end
		if needJoint and not self.Joint then
			app:Notify("Pick a joint first", "Warn")
			return false
		end
		return true
	end

	function PoseTool:Nudge(axis, sign)
		if not self:_ready(true) then
			return nil
		end
		local base = self.Drag:BaseValue(self.Joint, self.ClipTime)
		local hold = if self.Keyed[self.Joint] then nil else base
		local value
		if self.Mode == "Move" then
			local rig = self:Rig()
			value = PoseMath.Translate(base, Vector3.FromAxis(axis) * sign * self.Step / 10, rig and rig.Scale or 1)
		else
			value = PoseMath.Rotate(base, axis, math.rad(self.Step) * sign)
		end
		return PoseEdit.SetJoint(self.App.Document, self.Info, self.ClipTime, self.Joint, value, hold)
	end

	function PoseTool:KeyPose()
		if not self:_ready(false) then
			return nil
		end
		local poses = PoseMath.SampleAll(self.App.Deps, self.Info, self.ClipTime)
		return PoseEdit.SetPoses(self.App.Document, self.Info, self.ClipTime, poses, "Key pose")
	end

	function PoseTool:CopyPose()
		if not self.Info or not self.ClipTime then
			self.App:Notify("Move the playhead inside the clip first", "Warn")
			return nil
		end
		self.Clipboard = PoseMath.SampleAll(self.App.Deps, self.Info, self.ClipTime)
		local count = 0
		for _ in self.Clipboard do
			count += 1
		end
		self.App:Notify(`Copied {count} joints`, "Info")
		self.PanelDirty = true
		return self.Clipboard
	end

	function PoseTool:PastePose()
		if not self.Clipboard or not self:_ready(false) then
			return nil
		end
		return PoseEdit.SetPoses(self.App.Document, self.Info, self.ClipTime, self.Clipboard, "Paste pose")
	end

	function PoseTool:ResetJoint()
		if not self:_ready(true) then
			return nil
		end
		return PoseEdit.ResetJoint(self.App.Document, self.Info, self.ClipTime, self.Joint)
	end

	function PoseTool:DeleteKeyframe()
		if not self.Keyframe or not self:_editable() then
			return nil
		end
		return PoseEdit.DeleteKeyframe(self.App.Document, self.Keyframe)
	end

	function PoseTool:SetRole(role)
		local keyframe = self.Keyframe
		if not keyframe or not self.Info then
			self.App:Notify("Roles apply to the keyframe at the playhead", "Warn")
			self.PanelDirty = true
			return nil
		end
		if not self:_editable() then
			self.PanelDirty = true
			return nil
		end
		local keys = {}
		if self.RoleScope == "Keyframe" or not self.Joint then
			for key in PoseMath.Weighted(keyframe) do
				table.insert(keys, key)
			end
		else
			keys = { self.Joint }
		end
		local result = PoseEdit.SetRoles(self.App.Document, self.Info, keyframe, keys, role)
		self.PanelDirty = true
		return result
	end

	function PoseTool:ToggleSmooth()
		local info = self.Info
		if info and self:_editable() then
			return PoseEdit.SetSmooth(self.App.Document, info, not info.Smooth)
		end
		return nil
	end
end
