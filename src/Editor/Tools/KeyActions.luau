local CollectionService = game:GetService("CollectionService")
local Selection = game:GetService("Selection")

local Live = require(script.Parent.Live)
local KeyMath = require(script.Parent.KeyMath)

local function round(value)
	return math.round(value * 10000) / 10000
end

local function viewCamera(app)
	local session = app.Preview and app.Preview.Active and app.Preview.Session
	local lock = session and session.Lock
	if lock and lock.Engaged and lock.Proxy and lock:Owner() then
		return lock.Proxy.CFrame, lock.Proxy.FieldOfView
	end
	local camera = workspace.CurrentCamera
	return camera.CFrame, camera.FieldOfView
end

local function conventionDirection(count, index)
	if count == 2 and index == 1 then
		return "InOut"
	elseif count >= 3 and index == 1 then
		return "In"
	elseif count >= 3 and index == count - 1 then
		return "Out"
	end
	return nil
end

local function followsConvention(key, count, index)
	if index == count then
		return true
	end
	local style, direction = key:GetAttribute("Easing"), key:GetAttribute("EasingDirection")
	local expected = conventionDirection(count, index)
	if expected == nil then
		return style == nil or style == "Linear"
	end
	return style ~= nil and style ~= "Linear" and style ~= "Constant" and (direction or "InOut") == expected
end

return function(KeyTool)
	KeyTool.ViewCamera = viewCamera
	KeyTool.ConventionDirection = conventionDirection

	function KeyTool:_insertKey(localTime, value, attrs)
		local clip = self.Clip
		return self.App.Document:Batch("Add key", function(document)
			local before = document:GetKeys(clip)
			local marked = {}
			for index, key in before do
				if key:GetAttribute("AutoEase") ~= true and followsConvention(key, #before, index) then
					local style = key:GetAttribute("Easing")
					marked[key] = if style == nil or style == "Linear" then "Sine" else style
				end
			end
			local key = document:WriteKey(clip, localTime, value, attrs)
			local after = document:GetKeys(clip)
			for index, other in after do
				local style = marked[other]
				if style then
					local direction = conventionDirection(#after, index)
					document:WriteAttribute(other, "Easing", if direction then style else nil)
					document:WriteAttribute(other, "EasingDirection", direction)
				end
			end
			document:AutoEase(clip)
			return key
		end)
	end

	function KeyTool:Open(clip)
		if clip and self.App.Selection.Primary ~= clip then
			self.App:Select(clip, "Replace")
		end
		self:Sync()
		return self.Clip ~= nil
	end

	function KeyTool:AddKeyFromView(clip)
		self:Open(clip)
		return self:AddFromView()
	end

	function KeyTool:_editable()
		if not self.Clip then
			return false
		end
		if Live.Locked(self.Clip) then
			self.App:Notify("This track is locked; unlock it to edit its keys", "Warn")
			return false
		end
		return true
	end

	function KeyTool:_requirePlayhead()
		if not self:_editable() then
			return nil
		end
		local props = self.Props
		if not KeyMath.Inside(props, self.App.Time) then
			self.App:Notify("Move the playhead inside the clip first", "Warn")
			return nil
		end
		return round(math.max(KeyMath.ToLocal(props, self.App.Time), 0))
	end

	function KeyTool:_writeKey(localTime, value, attrs)
		local document = self.App.Document
		local existing = KeyMath.FindKey(self.Keys, localTime)
		local key
		if existing then
			key = document:SetKey(existing, value, attrs)
		else
			key = self:_insertKey(localTime, value, attrs)
		end
		if key then
			self.App:SelectKey(key)
			self.App:Notify(if existing then `Updated the key at {localTime}s` else `Added a key at {localTime}s`, "Info")
		end
		return key
	end

	function KeyTool:AddFromView()
		if self.Kind ~= "Camera" then
			return nil
		end
		local localTime = self:_requirePlayhead()
		if not localTime then
			return nil
		end
		local view, fov = viewCamera(self.App)
		local value = KeyMath.WorldToKey(self.App, "Camera", self.Props, view, localTime)
		if not value then
			self.App:Notify("The camera anchor is not available; start the preview", "Warn")
			return nil
		end
		return self:_writeKey(localTime, value, { FOV = round(fov) })
	end

	function KeyTool:UpdateFromView()
		local key = self.Key
		if self.Kind ~= "Camera" or not key or not self:_editable() then
			return nil
		end
		local view, fov = viewCamera(self.App)
		local value = KeyMath.WorldToKey(self.App, "Camera", self.Props, view, KeyMath.KeyTime(key))
		if not value then
			self.App:Notify("The camera anchor is not available; start the preview", "Warn")
			return nil
		end
		return self.App.Document:SetKey(key, value, { FOV = round(fov) })
	end

	function KeyTool:ViewThrough()
		local key = self.Key
		if self.Kind ~= "Camera" or not key then
			return false
		end
		local app = self.App
		local preview = app.Preview
		if preview.CameraLock then
			preview:SetCameraLock(false)
		end
		app:SetTime(KeyMath.ToCutscene(self.Props, KeyMath.KeyTime(key)))
		local world = self:KeyWorld(key)
		if not world then
			app:Notify("The camera anchor is not available; start the preview", "Warn")
			return false
		end
		local camera = workspace.CurrentCamera
		camera.CFrame = world
		camera.Focus = world * CFrame.new(0, 0, -10)
		camera.FieldOfView = key:GetAttribute("FOV") or 70
		return true
	end

	function KeyTool:ActorModel(actorId)
		local app = self.App
		local actor = Live.Actor(app, actorId)
		if actor and actor.Model then
			return actor.Model
		end
		local config = app.Document and app.Document:GetActor(actorId)
		if config then
			local source = config:GetAttribute("Source")
			if source == "Tag" then
				local best, rank = nil, math.huge
				for _, instance in CollectionService:GetTagged(config:GetAttribute("Tag") or "") do
					local current, saved = instance, true
					while current do
						if not current.Archivable then
							saved = false
						end
						current = current.Parent
					end
					if saved and instance:IsA("PVInstance") then
						local score = if instance:IsDescendantOf(workspace) then 1 else 2
						if score < rank then
							best, rank = instance, score
						end
					end
				end
				if best then
					return best
				end
			elseif source == "Template" then
				local template = config:FindFirstChild("Template")
				if template and template:IsA("PVInstance") then
					return template
				end
			end
		end
		return nil
	end

	function KeyTool:AddFromActor()
		if self.Kind ~= "Move" then
			return nil
		end
		local localTime = self:_requirePlayhead()
		if not localTime then
			return nil
		end
		Live.Ensure(self.App)
		local model = self:ActorModel(self.Clip.Parent:GetAttribute("Actor"))
		if not model then
			self.App:Notify("The actor's model was not found", "Warn")
			return nil
		end
		return self:_writeKey(localTime, model:GetPivot())
	end

	function KeyTool:SelectActor()
		local app = self.App
		local id = if self.Kind == "Attach" or self.Kind == "Move" then self.Clip.Parent:GetAttribute("Actor") else nil
		if not id then
			return nil
		end
		Live.Ensure(app)
		local actor = Live.Actor(app, id)
		local model = actor and actor.Model
		if not model then
			app:Notify("Start the preview to select the actor's preview copy", "Warn")
			return nil
		end
		Selection:Set({ model })
		app:Notify("Selected the preview copy: move it with Studio's tools, then add the key", "Info")
		return model
	end

	function KeyTool:OffsetFromProp()
		if self.Kind ~= "Attach" or not self:_editable() then
			return nil
		end
		local app = self.App
		local model = self:ActorModel(self.Clip.Parent:GetAttribute("Actor"))
		local frame = KeyMath.Frame(app, "Attach", self.Props, KeyMath.AttachTime(app, self.Props))
		if not model or not frame then
			app:Notify("Needs the prop's model and a running preview", "Warn")
			return nil
		end
		return app.Document:SetAttribute(self.Clip, "Offset", frame:ToObjectSpace(model:GetPivot()))
	end

	function KeyTool:ResetOffset()
		if self.Kind == "Attach" and self:_editable() then
			return self.App.Document:SetAttribute(self.Clip, "Offset", CFrame.identity)
		end
		return nil
	end

	function KeyTool:SetFov(value)
		if self.Kind == "Camera" and self.Key and self:_editable() then
			return self.App.Document:SetKey(self.Key, nil, { FOV = value })
		end
		return nil
	end

	function KeyTool:DeleteKey()
		local key = self.Key
		if key and self:_editable() then
			self.App:SelectKey(nil)
			return self.App.Document:DeleteKey(key)
		end
		return nil
	end
end
