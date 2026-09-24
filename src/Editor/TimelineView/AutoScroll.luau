local RunService = game:GetService("RunService")

local AutoScroll = {}
AutoScroll.__index = AutoScroll

AutoScroll.Margin = 28
AutoScroll.Speed = 700
AutoScroll.MaxFactor = 2
AutoScroll.ScrubPastEnd = 1
AutoScroll.MovePastEnd = 60
AutoScroll.Kinds = { Move = "XY", Retime = "X", Fade = "X", Key = "X", Scrub = "X", Marquee = "XY" }

function AutoScroll.new(interaction)
	local self = setmetatable({}, AutoScroll)
	self.Interaction = interaction
	self.View = interaction.View
	self.App = interaction.App
	self.X, self.Y = 0, 0
	self.Connection = nil
	return self
end

local function factor(value, low, high)
	local margin = AutoScroll.Margin
	if value < low + margin then
		return -math.min((low + margin - value) / margin, AutoScroll.MaxFactor)
	elseif value > high - margin then
		return math.min((value - (high - margin)) / margin, AutoScroll.MaxFactor)
	end
	return 0
end

function AutoScroll:Update(position)
	local drag = self.Interaction.Drag
	local axes = drag and drag.Started ~= false and AutoScroll.Kinds[drag.Kind]
	if not axes or not position then
		return self:Stop()
	end
	local view = self.View
	local app = self.App
	local localPosition = view:ToLocal(position)
	local size = view.Root.AbsoluteSize
	self.X = factor(localPosition.X, 0, size.X)
	self.Y = if axes == "XY" then factor(localPosition.Y, app.RulerHeight, size.Y) else 0
	if self.X == 0 and self.Y == 0 then
		return self:Stop()
	end
	if not self.Connection then
		self.Connection = RunService.PreRender:Connect(function(dt)
			self:_step(dt)
		end)
	end
end

function AutoScroll:_step(dt)
	local interaction = self.Interaction
	local drag = interaction.Drag
	if not drag or self.View.Destroyed then
		return self:Stop()
	end
	local app = self.App
	local view = self.View
	dt = math.min(dt, 0.1)
	local pixels = AutoScroll.Speed * dt
	local pps = app.PixelsPerSecond
	local scrollTime = nil
	if self.X < 0 then
		scrollTime = app.ScrollTime + self.X * pixels / pps
	elseif self.X > 0 then
		local limit = view.Model.Length + (if drag.Kind == "Scrub" then AutoScroll.ScrubPastEnd else AutoScroll.MovePastEnd)
		local furthest = math.max(limit - view:Width() / pps, 0)
		if app.ScrollTime < furthest then
			scrollTime = math.min(app.ScrollTime + self.X * pixels / pps, furthest)
		end
	end
	local changed = app:SetView({
		ScrollTime = scrollTime,
		ScrollY = if self.Y ~= 0 then app.ScrollY + self.Y * pixels else nil,
	})
	if changed and interaction.LastPosition then
		drag:Move(interaction.LastPosition, interaction.LastMods)
	end
end

function AutoScroll:Stop()
	self.X, self.Y = 0, 0
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
end

function AutoScroll:Destroy()
	self:Stop()
end

return AutoScroll
