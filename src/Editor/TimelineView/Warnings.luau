local Warnings = {}

Warnings.Tolerance = 1e-3

local function add(item, text)
	item.Warnings = item.Warnings or {}
	table.insert(item.Warnings, text)
end

function Warnings.Apply(view, model)
	local reading = view.Reading
	local cameras = {}
	for _, item in model.Items do
		item.Warnings = nil
		item.ReadingShort = nil
		item.Need = nil
		if item.Kind == "Dialogue" then
			local need = reading:Time(item.Spoken or item.Text, item.TypeSpeed, item.Mood)
			item.Need = need
			if need and item.Duration + Warnings.Tolerance < need then
				item.ReadingShort = true
				add(item, string.format("needs %.1fs to read (has %.1fs)", need, item.Duration))
			end
		elseif item.Kind == "Camera" and not item.Muted then
			if #item.Keys == 0 then
				add(item, "Camera clip has no keys")
			end
			table.insert(cameras, item)
		end
	end
	table.sort(cameras, function(a, b)
		return a.Start < b.Start
	end)
	for index, first in cameras do
		local finish = first.Start + first.Duration
		for next = index + 1, #cameras do
			local second = cameras[next]
			if second.Start >= finish - Warnings.Tolerance then
				break
			end
			add(first, `Overlaps camera clip "{second.Clip.Name}"`)
			add(second, `Overlaps camera clip "{first.Clip.Name}"`)
		end
	end
end

function Warnings.Count(model)
	local count = 0
	for _, item in model.Items do
		if item.Warnings then
			count += 1
		end
	end
	return count
end

return Warnings
