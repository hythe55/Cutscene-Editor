local Selection = game:GetService("Selection")

local UI = require(script.Parent.Parent.Parent.UI)
local Layout = require(script.Parent.Parent.Layout)

local Header = {}

local SOURCE_TEXT = {
	Tag = function(actor)
		return "tag " .. tostring(actor:GetAttribute("Tag") or "?")
	end,
	Role = function(actor)
		return "role " .. tostring(actor:GetAttribute("Role") or actor.Name)
	end,
	Group = function(actor)
		return "group " .. tostring(actor:GetAttribute("Group") or "Players")
	end,
	Template = function()
		return "template"
	end,
}

function Header.Subtitle(inspector, kind, target)
	local app = inspector.App
	local document = app.Document
	if kind == "Clip" then
		local track = target.Parent
		local count = 0
		for _ in app.Selection.Clips do
			count += 1
		end
		local parts = { `{document:KindOf(target)} clip`, track.Name }
		if count > 1 then
			table.insert(parts, `{count} selected, showing this one`)
		end
		if track:GetAttribute("Locked") == true then
			table.insert(parts, "track locked")
		end
		return table.concat(parts, " · ")
	elseif kind == "Track" then
		local actor = target:GetAttribute("Actor")
		local clips = #document:GetClips(target)
		return `{target:GetAttribute("Kind")} track · {if actor and actor ~= "" then actor else "scene"} · {clips} clip{if clips == 1 then "" else "s"}`
	elseif kind == "Actor" then
		local source = target:GetAttribute("Source") or "Tag"
		local describe = SOURCE_TEXT[source]
		return "Actor · " .. (if describe then describe(target) else source)
	end
	return `Cutscene · {Layout.FormatTime(app:GetLength())} · {#document:GetActors()} actors · {#document:GetTracks()} tracks`
end

function Header.Build(inspector, kind, target, order)
	local app = inspector.App
	local document = app.Document
	local color = if kind == "Clip" then UI.Kind(document:KindOf(target)) elseif kind == "Track" then UI.Kind(target:GetAttribute("Kind")) else "Accent"
	local header = UI.Create("Frame", {
		Name = "Header",
		Parent = inspector.Content,
		LayoutOrder = order,
		BackgroundColor3 = "Surface",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	UI.Create("Frame", {
		Name = "Accent",
		Parent = header,
		BackgroundColor3 = color,
		Size = UDim2.new(0, 3, 1, 0),
	})
	local card = UI.Create("Frame", {
		Name = "Body",
		Parent = header,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = { Left = 12, Right = 8, Top = 8, Bottom = 8 },
		List = { Padding = 2 },
	})
	local top = UI.Create("Frame", {
		Parent = card,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 26),
	})
	local name = UI.Create("TextBox", {
		Name = "Name",
		Parent = top,
		Text = target.Name,
		Font = "Bold",
		TextSize = 16,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -64, 1, 0),
		Tooltip = "Click to rename",
	})
	name.FocusLost:Connect(function()
		local text = string.gsub(name.Text, "^%s*(.-)%s*$", "%1")
		if text ~= "" and text ~= target.Name then
			inspector:Commit(function()
				document:Rename(target, text)
			end)
		else
			name.Text = target.Name
		end
	end)
	inspector:Bind(function()
		if not name:IsFocused() then
			name.Text = target.Name
		end
	end)
	UI.Button({
		Name = "SelectInExplorer",
		Parent = top,
		Text = "Select",
		Style = "Ghost",
		Height = 24,
		TextSize = 12,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Tooltip = "Select this instance in the Explorer",
		OnClick = function()
			Selection:Set({ target })
		end,
	})
	local subtitle = Layout.Text(card, 2, Header.Subtitle(inspector, kind, target), { Name = "Subtitle" })
	inspector:Bind(function()
		subtitle.Text = Header.Subtitle(inspector, kind, target)
	end)
	return header
end

return Header
