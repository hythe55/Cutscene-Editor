-- RigKit: pure-Luau helpers for posing skinned bone rigs by code. Written for two imported rigs; extend
-- ROLE_NAMES (and check NATURAL's signs with a capture) before using it on another rig. Dev-only, never synced.
--
-- Usage inside execute_luau (the chunk ends in `return RigKit`, so wrap it):
--   local RigKit = (function()
--       <paste this whole file here>
--   end)()
--   local rest = RigKit.getRest(workspace:FindFirstChild("MyRig"))
--   local pose = RigKit.natural(rest, "ElbowFlex", "R", 90)
--   ...
--
-- Conventions
--   Character space (char) = the model pivot's object space at getRest time:
--     +X = character's right, +Y = up, -Z = forward (the way the face looks). True for both rigs.
--   A "pose" is a table { [boneName] = CFrame } of Bone.Transform values. Missing bones = identity.
--   Transform is applied in the bone's local frame: posedChild = parentPosed * bone.CFrame * bone.Transform.
--   Every chain bone points at its principal child along local +Y (Blender convention).
--   Angles are degrees. Positive direction of every natural motion is documented in NATURAL below.
--   "Rest-relative axis": a character-space axis measured at rest and converted to the bone's local frame,
--   so the motion rides along with whatever the parents do (like a local rotation in Blender).
--
-- Functions only read instances, except applyPose / resetPose / restore / stepPreview, which write
-- Bone.Transform (restore also moves parts back; stepPreview cleans up after itself). Those four need the
-- shared Studio lease (if agents share Studio) when run through execute_luau. Everything else returns plain tables/CFrames.
-- Tip: execute_luau keeps _G between calls, so one call can do `_G.RigKit = RigKit` and later calls can reuse
-- it without re-pasting (clear it with `_G.RigKit = nil` when done).

local RigKit = {}
RigKit.__index = RigKit

local UP = Vector3.yAxis
local RIGHT = Vector3.xAxis
local FORWARD = Vector3.new(0, 0, -1)
local EPS = 1e-6

RigKit.UP = UP
RigKit.RIGHT = RIGHT
RigKit.FORWARD = FORWARD

-- Role -> candidate bone names (first existing wins). %s = side letter ("L" / "R").
local ROLE_NAMES = {
	Body = { "COG", "Root" },
	Pelvis = { "Hips", "spine" },
	Spine = { { "Chest" }, { "spine2", "spine3" } },
	Neck = { "Neck", "neck" },
	Head = { "Head", "head" },
	Jaw = { { "jaw.L", "jaw.R" }, { "mouth bot" } },
	Eye = { "Eye.%s" },
	Shoulder = { "DEF_Shoulder.%s", "arm.%s" },
	UpperArm = { "DEF_UpperArm.%s", "arm.%s.001" },
	LowerArm = { "DEF_LowerArm.%s", "arm.%s.002" },
	Hand = { "DEF_Hand.%s", "Hand.%s" },
	UpperLeg = { "DEF_UpperLeg.%s", "Leg.%s.001" },
	LowerLeg = { "DEF_LowerLeg.%s", "Leg.%s.002" },
	Foot = { "DEF_Foot.%s", "Leg.%s.003" },
}

local function unitOr(v, fallback)
	local m = v.Magnitude
	if m < EPS then
		return fallback
	end
	return v / m
end

local function poseCF(v)
	if typeof(v) == "CFrame" then
		return v
	elseif type(v) == "table" then
		return v.cf or v.CFrame or CFrame.identity
	end
	return CFrame.identity
end
RigKit.poseCF = poseCF

-- Rotation whose columns are (a, b orthogonalised against a, a x b).
local function frame(a, b)
	a = unitOr(a, RIGHT)
	local bp = b - a * b:Dot(a)
	if bp.Magnitude < EPS then
		bp = math.abs(a.Y) < 0.9 and UP - a * a.Y or RIGHT - a * a.X
	end
	bp = bp.Unit
	return CFrame.fromMatrix(Vector3.zero, a, bp, a:Cross(bp))
end

-- Rotation R with R*la = wa and R*lb (orthogonalised) = wb (orthogonalised).
local function basisMap(la, lb, wa, wb)
	return frame(wa, wb) * frame(la, lb):Inverse()
end
RigKit.basisMap = basisMap

-- Minimal rotation taking unit vector a onto unit vector b.
local function swingBetween(a, b)
	a, b = unitOr(a, UP), unitOr(b, UP)
	local c = a:Cross(b)
	local d = math.clamp(a:Dot(b), -1, 1)
	if c.Magnitude < EPS then
		if d > 0 then
			return CFrame.identity
		end
		local perp = math.abs(a.X) < 0.9 and a:Cross(RIGHT) or a:Cross(UP)
		return CFrame.fromAxisAngle(perp.Unit, math.pi)
	end
	return CFrame.fromAxisAngle(c.Unit, math.atan2(c.Magnitude, d))
end
RigKit.swingBetween = swingBetween

local function findRootPart(model)
	local best, bestCount = nil, -1
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local n = 0
			for _, c in part:GetChildren() do
				if c:IsA("Bone") then
					n += 1
				end
			end
			if n > bestCount then
				best, bestCount = part, n
			end
		end
	end
	if bestCount <= 0 then
		return model.PrimaryPart
	end
	return best
end

-- getRest(model) -> rest
-- rest.bones[name] = {
--   name, instance, parent (bone name or nil), part (BasePart for top-level bones),
--   cframe (Bone.CFrame, rest local), partChar (char CFrame of the parent part, top-level only),
--   char (rest CFrame in character space), children {names}, child (principal child name or nil),
--   childDir (unit, local), length (to principal child, 0 for leaves), depth }
-- rest.order = depth-first names (parents before children), rest.roots = top-level bone names,
-- rest.rootPart, rest.rootName, rest.pivot (world pivot at capture), rest.roles, rest.limbs,
-- rest.height, rest.minY/maxY (char-space bone extents), rest.meshes (char-space mesh boxes).
function RigKit.getRest(model)
	local pivot = model:GetPivot()
	local rootPart = model.PrimaryPart or findRootPart(model)
	local rest = setmetatable({
		model = model,
		pivot = pivot,
		rootPart = rootPart,
		rootName = rootPart and rootPart.Name or "RootPart",
		bones = {},
		order = {},
		roots = {},
		meshes = {},
	}, RigKit)

	local function visit(bone, parentName, partChar, parentChar, depth)
		local data = {
			name = bone.Name,
			instance = bone,
			parent = parentName,
			part = parentName == nil and bone.Parent or nil,
			partChar = partChar,
			cframe = bone.CFrame,
			children = {},
			depth = depth,
		}
		data.char = parentChar * bone.CFrame
		rest.bones[bone.Name] = data
		table.insert(rest.order, bone.Name)
		if parentName == nil then
			table.insert(rest.roots, bone.Name)
		else
			table.insert(rest.bones[parentName].children, bone.Name)
		end
		for _, c in bone:GetChildren() do
			if c:IsA("Bone") then
				visit(c, bone.Name, nil, data.char, depth + 1)
			end
		end
	end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local partChar = pivot:ToObjectSpace(part.CFrame)
			for _, c in part:GetChildren() do
				if c:IsA("Bone") then
					visit(c, nil, partChar, partChar, 0)
				end
			end
			if part:IsA("MeshPart") then
				local rel = pivot:ToObjectSpace(part.CFrame)
				rest.meshes[part.Name] = {
					min = rel.Position - part.Size / 2,
					max = rel.Position + part.Size / 2,
					transparency = part.Transparency,
				}
			end
		end
	end

	local minY, maxY = math.huge, -math.huge
	for _, name in rest.order do
		local b = rest.bones[name]
		local bestDot, best = -math.huge, nil
		for _, cn in b.children do
			local p = rest.bones[cn].cframe.Position
			if p.Magnitude > EPS then
				local d = p.Unit:Dot(UP)
				if d > bestDot then
					bestDot, best = d, cn
				end
			end
		end
		b.child = best
		if best then
			local p = rest.bones[best].cframe.Position
			b.length = p.Magnitude
			b.childDir = p.Unit
		else
			b.length = 0
			b.childDir = UP
		end
		local y = b.char.Position.Y
		minY, maxY = math.min(minY, y), math.max(maxY, y)
	end
	rest.minY, rest.maxY = minY, maxY
	local lo, hi = math.huge, -math.huge
	for _, m in rest.meshes do
		if m.transparency < 1 then
			lo, hi = math.min(lo, m.min.Y), math.max(hi, m.max.Y)
		end
	end
	rest.visibleMinY, rest.visibleMaxY = lo, hi

	-- roles
	rest.roles = {}
	local function resolve(role, side)
		for _, cand in ROLE_NAMES[role] do
			if type(cand) == "table" then
				local list = {}
				for _, n in cand do
					if rest.bones[n] then
						table.insert(list, n)
					end
				end
				if #list > 0 then
					return list
				end
			else
				local n = side and string.format(cand, side) or cand
				if rest.bones[n] then
					return n
				end
			end
		end
		return nil
	end
	for role, cands in ROLE_NAMES do
		local sided = false
		for _, cand in cands do
			if type(cand) == "string" and string.find(cand, "%%s") then
				sided = true
			end
		end
		if sided then
			rest.roles[role .. "L"] = resolve(role, "L")
			rest.roles[role .. "R"] = resolve(role, "R")
		else
			rest.roles[role] = resolve(role)
		end
	end

	-- limbs (two-bone chains) with a natural hinge axis in each bone's local frame
	rest.limbs = {}
	for _, side in { "L", "R" } do
		for kind, spec in { Arm = { "UpperArm", "LowerArm", "Hand", FORWARD }, Leg = { "UpperLeg", "LowerLeg", "Foot", -FORWARD } } do
			local u, l, t = rest.roles[spec[1] .. side], rest.roles[spec[2] .. side], rest.roles[spec[3] .. side]
			if u and l and t then
				local ub, lb = rest.bones[u], rest.bones[l]
				local upperDir = (lb.char.Position - ub.char.Position).Unit
				local flexDir = spec[4] - upperDir * spec[4]:Dot(upperDir)
				local hinge = upperDir:Cross(unitOr(flexDir, UP)).Unit
				rest.limbs[kind .. side] = {
					upper = u,
					lower = l,
					tip = t,
					kind = kind,
					side = side,
					hingeChar = hinge,
					hingeUpper = ub.char:VectorToObjectSpace(hinge),
					hingeLower = lb.char:VectorToObjectSpace(hinge),
					upperLength = lb.cframe.Position.Magnitude,
					lowerLength = rest.bones[t].cframe.Position.Magnitude,
				}
			end
		end
	end

	-- fingers per hand: chains below the hand; thumb = chain whose base is closest to the wrist
	rest.fingers = {}
	for _, side in { "L", "R" } do
		local hand = rest.roles["Hand" .. side]
		if hand then
			local chains = {}
			for _, base in rest.bones[hand].children do
				local chain = { base }
				local cur = base
				while rest.bones[cur].child do
					cur = rest.bones[cur].child
					table.insert(chain, cur)
				end
				table.insert(chains, chain)
			end
			table.sort(chains, function(a, b)
				return rest.bones[a[1]].cframe.Position.Magnitude < rest.bones[b[1]].cframe.Position.Magnitude
			end)
			local thumb = table.remove(chains, 1)
			-- palm normal from index->pinky spread and the finger direction
			local handChar = rest.bones[hand].char
			local fingerDir = rest.bones[hand].char:VectorToWorldSpace(rest.bones[hand].childDir)
			local spreadA, spreadB
			local far, near = -math.huge, math.huge
			for _, ch in chains do
				local z = rest.bones[ch[1]].char.Position.Z
				if z < near then
					near, spreadA = z, ch[1]
				end
				if z > far then
					far, spreadB = z, ch[1]
				end
			end
			local palm = UP
			if spreadA and spreadB and spreadA ~= spreadB then
				local spread = rest.bones[spreadA].char.Position - rest.bones[spreadB].char.Position
				palm = unitOr(spread:Cross(fingerDir) * (side == "R" and 1 or -1), UP)
			end
			rest.fingers[side] = { thumb = thumb, fingers = chains, palm = palm, hand = hand, handChar = handChar }
		end
	end

	local top = rest.visibleMaxY
	rest.height = (top > -math.huge and top or maxY) - (rest.visibleMinY < math.huge and rest.visibleMinY or minY)
	return rest
end

-- fk(rest, pose) -> { [name] = CFrame in character space, posed }
function RigKit.fk(rest, pose)
	local res = {}
	for _, name in rest.order do
		local b = rest.bones[name]
		local base = b.parent and res[b.parent] or b.partChar
		local t = pose and pose[name]
		res[name] = base * b.cframe * (t and poseCF(t) or CFrame.identity)
	end
	return res
end

-- World CFrame of every bone for a pose, using the model's current pivot (or the given one).
function RigKit.worldCFrames(rest, pose, pivot)
	pivot = pivot or rest.model:GetPivot()
	local res = {}
	for name, cf in RigKit.fk(rest, pose) do
		res[name] = pivot * cf
	end
	return res
end

-- rotateLocal(rest, boneName, characterAxis, degrees) -> Transform CFrame
-- Rotation about a character-space axis (right-hand rule, measured at rest) converted into the
-- bone's local frame. Compose with an existing Transform as existing * rotateLocal(...).
function RigKit.rotateLocal(rest, boneName, axis, degrees)
	local b = rest.bones[boneName]
	assert(b, "RigKit: no bone " .. tostring(boneName))
	local localAxis = b.char:VectorToObjectSpace(unitOr(axis, UP))
	return CFrame.fromAxisAngle(localAxis, math.rad(degrees))
end

-- moveLocal(rest, boneName, charOffset) -> translation-only Transform that moves the bone (and its children) by
-- a character-space offset measured at rest. Use for COG/Root drops (squats, rising) and mouth-corner bones.
function RigKit.moveLocal(rest, boneName, offset)
	local b = rest.bones[boneName]
	assert(b, "RigKit: no bone " .. tostring(boneName))
	return CFrame.new(b.char:VectorToObjectSpace(offset))
end

-- talk(rest, open) -> pose fragment for a mouth shape, open in [0, 1].
-- Rig A has no jaw: "jaw.L"/"jaw.R" are leaf mouth-corner bones and rotating them does nothing visible, so
-- they are translated (corners in 0.1 and down 0.2 studs at open = 1, which flattens her painted smile).
-- Rig B's "mouth bot" is rotated open by 20 deg at open = 1 (her head mesh is transparent, so it is invisible).
function RigKit.talk(rest, open)
	local out = {}
	if rest.bones["jaw.L"] and rest.bones["jaw.R"] then
		out["jaw.L"] = RigKit.moveLocal(rest, "jaw.L", Vector3.new(0.1 * open, -0.2 * open, 0))
		out["jaw.R"] = RigKit.moveLocal(rest, "jaw.R", Vector3.new(-0.1 * open, -0.2 * open, 0))
	elseif rest.bones["mouth bot"] then
		out["mouth bot"] = RigKit.rotateLocal(rest, "mouth bot", -RIGHT, 20 * open)
	end
	return out
end

-- rotateWorld(rest, pose, boneName, characterAxis, degrees) -> new Transform
-- Like rotateLocal but the axis is taken in the bone's CURRENT posed frame (parents included), and the
-- result already includes the bone's existing Transform from `pose`.
function RigKit.rotateWorld(rest, pose, boneName, axis, degrees)
	local posed = RigKit.fk(rest, pose)[boneName]
	local cur = pose and pose[boneName] and poseCF(pose[boneName]) or CFrame.identity
	return cur * CFrame.fromAxisAngle(posed:VectorToObjectSpace(unitOr(axis, UP)), math.rad(degrees))
end

-- aim(rest, pose, boneName, charDir, twistDeg?) -> Transform that points the bone's principal child
-- along charDir (character space, current posed parents) with the minimal swing, plus optional twist.
function RigKit.aim(rest, pose, boneName, charDir, twistDeg)
	local b = rest.bones[boneName]
	local posedFk = RigKit.fk(rest, pose)
	local base = (b.parent and posedFk[b.parent] or b.partChar) * b.cframe
	local localTarget = base:VectorToObjectSpace(unitOr(charDir, UP))
	local t = swingBetween(b.childDir, localTarget)
	if twistDeg and twistDeg ~= 0 then
		t = t * CFrame.fromAxisAngle(b.childDir, math.rad(twistDeg))
	end
	return t
end

-- Natural motions. All return a pose fragment { [bone] = Transform } using rest-relative axes.
-- side: "L" / "R" where relevant. Positive degrees:
--   SpineBend  forward            SpineSide  lean to character's right   SpineTwist  chest turns to her left
--   HeadYaw    look to her left   HeadPitch  look up                     HeadRoll    ear toward right shoulder
--   JawOpen    open mouth         EyeYaw     look left                   EyePitch    look up
--   ArmUp      arm rises in the frontal plane (from hanging: out then overhead; from T-pose: up)
--   ArmForward arm swings toward the front      ArmTwist  twist about the upper-arm axis
--   ElbowFlex  forearm bends forward (natural)  WristFlex  hand bends toward the palm
--   FingerCurl each finger segment curls toward the palm by `degrees`   ThumbCurl  thumb folds toward the palm
--   LegForward hip flexion (leg forward)        LegOut  leg abducts outward
--   KneeFlex   shin bends backward (natural)    FootPitch  toes up
-- Head/spine motions are split across the available bones (neck 40% / head 60%; spine bones evenly).
RigKit.NATURAL = {
	"SpineBend", "SpineSide", "SpineTwist", "HeadYaw", "HeadPitch", "HeadRoll", "JawOpen", "EyeYaw", "EyePitch",
	"ArmUp", "ArmForward", "ArmTwist", "ElbowFlex", "WristFlex", "FingerCurl", "ThumbCurl",
	"LegForward", "LegOut", "KneeFlex", "FootPitch",
}

local function sideSign(side)
	return side == "L" and -1 or 1
end

local function asList(v)
	if v == nil then
		return {}
	end
	if type(v) == "table" then
		return v
	end
	return { v }
end

function RigKit.natural(rest, motion, side, degrees)
	local out = {}
	local roles = rest.roles
	local function add(bone, axis, deg)
		if bone and rest.bones[bone] then
			local cf = RigKit.rotateLocal(rest, bone, axis, deg)
			out[bone] = out[bone] and out[bone] * cf or cf
		end
	end
	local function spread(list, axis, deg)
		list = asList(list)
		for _, n in list do
			add(n, axis, deg / #list)
		end
	end
	local function headSplit(axis, deg)
		add(roles.Neck, axis, deg * 0.4)
		add(roles.Head, axis, deg * (roles.Neck and 0.6 or 1))
	end
	local function dirOf(bone)
		local b = rest.bones[bone]
		return b.char:VectorToWorldSpace(b.childDir)
	end
	if motion == "SpineBend" then
		spread(roles.Spine, -RIGHT, degrees)
	elseif motion == "SpineSide" then
		spread(roles.Spine, FORWARD, degrees)
	elseif motion == "SpineTwist" then
		spread(roles.Spine, UP, degrees)
	elseif motion == "HeadYaw" then
		headSplit(UP, degrees)
	elseif motion == "HeadPitch" then
		headSplit(RIGHT, degrees)
	elseif motion == "HeadRoll" then
		headSplit(FORWARD, degrees)
	elseif motion == "JawOpen" then
		for _, j in asList(roles.Jaw) do
			add(j, -RIGHT, degrees)
		end
	elseif motion == "EyeYaw" or motion == "EyePitch" then
		local axis = motion == "EyeYaw" and UP or RIGHT
		for _, s in side and { side } or { "L", "R" } do
			add(roles["Eye" .. s], axis, degrees)
		end
	elseif motion == "ArmUp" then
		add(roles["UpperArm" .. side], -FORWARD * sideSign(side), degrees)
	elseif motion == "ArmForward" then
		local bone = roles["UpperArm" .. side]
		add(bone, unitOr(dirOf(bone):Cross(FORWARD), RIGHT), degrees)
	elseif motion == "ArmTwist" then
		local bone = roles["UpperArm" .. side]
		add(bone, dirOf(bone), degrees)
	elseif motion == "ElbowFlex" or motion == "KneeFlex" then
		local limb = rest.limbs[(motion == "ElbowFlex" and "Arm" or "Leg") .. side]
		if limb then
			add(limb.lower, limb.hingeChar, degrees)
		end
	elseif motion == "WristFlex" then
		local f = rest.fingers[side]
		if f then
			add(f.hand, unitOr(dirOf(f.hand):Cross(f.palm), RIGHT), degrees)
		end
	elseif motion == "FingerCurl" or motion == "ThumbCurl" then
		local f = rest.fingers[side]
		if f then
			local chains = motion == "ThumbCurl" and { f.thumb } or f.fingers
			for _, chain in chains do
				local lastDir = dirOf(f.hand)
				for _, seg in chain do
					local b = rest.bones[seg]
					local dir = b.child and dirOf(seg) or lastDir
					lastDir = dir
					local axis
					if motion == "ThumbCurl" then
						axis = -unitOr(dirOf(f.hand), RIGHT) * sideSign(side)
					else
						axis = unitOr(dir:Cross(f.palm), RIGHT)
					end
					add(seg, axis, degrees)
				end
			end
		end
	elseif motion == "LegForward" then
		add(roles["UpperLeg" .. side], RIGHT, degrees)
	elseif motion == "LegOut" then
		add(roles["UpperLeg" .. side], -FORWARD * sideSign(side), degrees)
	elseif motion == "FootPitch" then
		add(roles["Foot" .. side], RIGHT, degrees)
	else
		error("RigKit.natural: unknown motion " .. tostring(motion))
	end
	return out
end

-- compose(a, b, ...) -> new pose where shared bones are multiplied in order (a * b), others copied.
function RigKit.compose(...)
	local out = {}
	for i = 1, select("#", ...) do
		local p = select(i, ...)
		if p then
			for name, v in p do
				local cf = poseCF(v)
				out[name] = out[name] and out[name] * cf or cf
			end
		end
	end
	return out
end

-- lerpPose(a, b, alpha) -> per-bone CFrame:Lerp (missing = identity)
function RigKit.lerpPose(a, b, alpha)
	local out = {}
	for name, v in a do
		out[name] = poseCF(v):Lerp(b[name] and poseCF(b[name]) or CFrame.identity, alpha)
	end
	for name, v in b do
		if out[name] == nil then
			out[name] = CFrame.identity:Lerp(poseCF(v), alpha)
		end
	end
	return out
end

local LIMB_ALIASES = {
	R = "ArmR", L = "ArmL", ArmR = "ArmR", ArmL = "ArmL", LegR = "LegR", LegL = "LegL",
	RightArm = "ArmR", LeftArm = "ArmL", RightLeg = "LegR", LeftLeg = "LegL",
}

-- twoBoneIK(rest, side, targetWorldPos, poleWorldPos, pose?, pivot?) -> transforms, info
-- side: "R"/"L" (arms) or "LegR"/"LegL". target = where the wrist (hand bone origin) / ankle should go.
-- pole = world point the elbow/knee should point toward (arms: behind/below the elbow; legs: in front of
-- the knee). pose supplies the parents' current Transforms (spine, clavicle, ...). pivot defaults to the
-- model's current pivot. Returns { [upper] = CF, [lower] = CF } plus info
-- { elbow = worldPos, wrist = worldPos, reach = maxDist, distance = requested, clamped = bool }.
-- The hand/foot keeps whatever Transform `pose` has for it (identity = follows the forearm).
function RigKit.twoBoneIK(rest, side, target, pole, pose, pivot)
	local key = LIMB_ALIASES[side] or side
	local limb = rest.limbs[key]
	assert(limb, "RigKit.twoBoneIK: no limb " .. tostring(side))
	pivot = pivot or rest.model:GetPivot()
	local posedFk = RigKit.fk(rest, pose)
	local ub, lb = rest.bones[limb.upper], rest.bones[limb.lower]
	local upperBase = (ub.parent and posedFk[ub.parent] or ub.partChar) * ub.cframe
	local S = upperBase.Position
	local tChar = pivot:PointToObjectSpace(target)
	local pChar = pivot:PointToObjectSpace(pole)
	local a, b = limb.upperLength, limb.lowerLength
	local toT = tChar - S
	local wanted = toT.Magnitude
	local d = math.clamp(wanted, math.abs(a - b) + 1e-3, (a + b) * 0.9995)
	local u = unitOr(toT, upperBase:VectorToWorldSpace(ub.childDir))
	local pv = pChar - S
	local v = pv - u * pv:Dot(u)
	if v.Magnitude < EPS then
		local restHinge = upperBase:VectorToWorldSpace(limb.hingeUpper)
		v = u:Cross(restHinge)
	end
	v = v.Unit
	local cosA = math.clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local E = S + u * (a * cosA) + v * (a * sinA)
	local H = S + u * d
	local dirU = (E - S).Unit
	local dirL = (H - E).Unit
	local hinge = dirU:Cross(dirL)
	if hinge.Magnitude < EPS then
		hinge = v:Cross(u)
	end
	hinge = hinge.Unit
	local Wu = basisMap(ub.childDir, limb.hingeUpper, dirU, hinge)
	local Tu = upperBase.Rotation:Inverse() * Wu
	local upperPosed = upperBase * Tu
	local lowerBase = upperPosed * lb.cframe
	local Wl = basisMap(lb.childDir, limb.hingeLower, dirL, hinge)
	local Tl = lowerBase.Rotation:Inverse() * Wl
	return { [limb.upper] = Tu, [limb.lower] = Tl }, {
		elbow = pivot * E,
		wrist = pivot * H,
		reach = a + b,
		distance = wanted,
		clamped = wanted ~= d,
	}
end

local function boneMap(model)
	local map = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") then
			map[d.Name] = d
		end
	end
	return map
end

-- applyPose(model, pose, resetOthers?) -> number of bones written
function RigKit.applyPose(model, pose, resetOthers)
	local n = 0
	for name, bone in boneMap(model) do
		local v = pose[name]
		if v ~= nil then
			bone.Transform = poseCF(v)
			n += 1
		elseif resetOthers then
			bone.Transform = CFrame.identity
			n += 1
		end
	end
	return n
end

-- resetPose(model) -> number of bones reset to identity
function RigKit.resetPose(model)
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") then
			d.Transform = CFrame.identity
			n += 1
		end
	end
	return n
end

-- readPose(model) -> { [boneName] = Transform } for every bone whose Transform is not identity
function RigKit.readPose(model)
	local out = {}
	for name, bone in boneMap(model) do
		if bone.Transform ~= CFrame.identity then
			out[name] = bone.Transform
		end
	end
	return out
end

-- snapshot(model) / restore(model, snap): bit-exact pivot, every BasePart CFrame and every Bone/Motor6D
-- Transform. restore uses workspace:BulkMoveTo with the recorded part CFrames, so the parts come back
-- bit-identical. (PivotTo there and back drifts the rotation by ~2e-7, and assigning part.CFrame one part at
-- a time drags the Motor6D-joined parts along and drifts further.)
function RigKit.snapshot(model)
	local snap = { pivot = model:GetPivot(), transforms = {}, parts = {} }
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") or d:IsA("Motor6D") then
			snap.transforms[d] = d.Transform
		elseif d:IsA("BasePart") then
			snap.parts[d] = d.CFrame
		end
	end
	return snap
end

function RigKit.restore(model, snap)
	local parts, cfs = {}, {}
	for part, cf in snap.parts or {} do
		table.insert(parts, part)
		table.insert(cfs, cf)
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	else
		model:PivotTo(snap.pivot)
	end
	for inst, t in snap.transforms do
		inst.Transform = t
	end
end

-- sameSnapshot(a, b) -> true when pivot, every part CFrame and every Transform are bit-identical.
function RigKit.sameSnapshot(a, b)
	if a.pivot ~= b.pivot then
		return false
	end
	for inst, t in a.transforms do
		if b.transforms[inst] ~= t then
			return false
		end
	end
	for part, cf in a.parts or {} do
		if not b.parts or b.parts[part] ~= cf then
			return false
		end
	end
	return true
end

-- Maximum |difference| between two snapshots (studs or radians); 0 = identical within float precision.
function RigKit.diffSnapshot(a, b)
	local worst = 0
	local function cfDiff(x, y)
		local dp = (x.Position - y.Position).Magnitude
		local _, ang = (x.Rotation:Inverse() * y.Rotation):ToAxisAngle()
		return math.max(dp, math.abs(ang))
	end
	worst = math.max(worst, cfDiff(a.pivot, b.pivot))
	for inst, t in a.transforms do
		worst = math.max(worst, cfDiff(t, b.transforms[inst] or CFrame.identity))
	end
	for part, cf in a.parts or {} do
		worst = math.max(worst, cfDiff(cf, b.parts and b.parts[part] or cf))
	end
	return worst
end

-- stepPreview(model, ks, t) -> pose read back from the engine after playing `ks` to time t in EDIT mode.
-- Registers the KeyframeSequence (temporary rbxtemp id), plays it through the rig's Animator with
-- Animator:StepAnimations, reads every Bone.Transform, then stops/destroys the track, resets the Transforms
-- it touched and removes any Animator it had to create (imported AnimationControllers often have none).
-- WRITES to the rig while it runs: hold the shared Studio lease if agents share Studio.
function RigKit.stepPreview(model, ks, t)
	local host = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildOfClass("AnimationController")
	assert(host, "RigKit.stepPreview: no Humanoid/AnimationController")
	local animator = host:FindFirstChildOfClass("Animator")
	local created = nil
	if not animator then
		created = Instance.new("Animator")
		created.Parent = host
		animator = created
	end
	local before = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") then
			before[d] = d.Transform
		end
	end
	local id = game:GetService("KeyframeSequenceProvider"):RegisterKeyframeSequence(ks)
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local track = animator:LoadAnimation(anim)
	track:Play(0)
	track:AdjustSpeed(0)
	local result = {}
	local ok, err = pcall(function()
		local deadline = os.clock() + 2
		repeat
			-- StepAnimations(0) does not apply a freshly loaded track until a frame has passed; a non-zero step
			-- with speed 0 applies immediately and keeps TimePosition at t.
			track.TimePosition = t
			animator:StepAnimations(1 / 60)
			local moved = false
			for bone in before do
				if bone.Transform ~= before[bone] then
					moved = true
					break
				end
			end
			if moved then
				break
			end
			task.wait()
		until os.clock() > deadline
		for bone in before do
			if bone.Transform ~= CFrame.identity then
				result[bone.Name] = bone.Transform
			end
		end
	end)
	track:Stop(0)
	-- a stopped track keeps fading inside the Animator for ~18 steps; flush it so nothing is left playing
	pcall(function()
		for _ = 1, 60 do
			local still = false
			for _, other in animator:GetPlayingAnimationTracks() do
				if other == track then
					still = true
				end
			end
			if not still then
				break
			end
			animator:StepAnimations(1 / 60)
		end
	end)
	track:Destroy()
	anim:Destroy()
	for bone, tr in before do
		bone.Transform = tr
	end
	if created then
		created:Destroy()
	end
	assert(ok, err)
	return result
end

local STYLE = {
	Linear = Enum.PoseEasingStyle.Linear,
	Constant = Enum.PoseEasingStyle.Constant,
	Cubic = Enum.PoseEasingStyle.Cubic,
	CubicV2 = Enum.PoseEasingStyle.CubicV2,
	Elastic = Enum.PoseEasingStyle.Elastic,
	Bounce = Enum.PoseEasingStyle.Bounce,
}
local DIRECTION = {
	In = Enum.PoseEasingDirection.In,
	Out = Enum.PoseEasingDirection.Out,
	InOut = Enum.PoseEasingDirection.InOut,
}

local function toStyle(v, default)
	if typeof(v) == "EnumItem" then
		return v
	end
	return STYLE[v or ""] or default
end
local function toDirection(v, default)
	if typeof(v) == "EnumItem" then
		return v
	end
	return DIRECTION[v or ""] or default
end

-- buildKeyframeSequence(rest, keys, opts) -> KeyframeSequence (unparented)
-- keys: array of { time = seconds, pose = { [bone] = CFrame | { cf = CFrame, style = "Cubic", dir = "InOut",
--        weight = 1 } }, style = default style for this key, dir = default direction for this key, name = "kfName" }
-- opts: { name = "Clip", loop = false, priority = Enum.AnimationPriority.Action, rootName = rest.rootName,
--         style = "Linear", dir = "In", full = false }
-- Layout (matches clips uploaded from these rigs): Keyframe > Pose[rootName] (Weight 0, identity) > top-level bone
-- poses > child bone poses nested exactly like the Bone hierarchy. Keyed bones get Weight 1; ancestors that
-- are only there to hold the nesting get Weight 0 (Roblox Animation Editor convention). full = true writes
-- every bone in every keyframe with Weight 1 (Blender-bake convention; unkeyed bones = identity).
-- Easing on a Pose applies from that key to the next key of the same bone.
-- Verified with Animator:StepAnimations on both rigs: the root pose NAME is ignored for bones (RootPart,
-- HumanoidRootPart and "Banana" all play), but the NESTING is required: a bone pose placed directly under the
-- root pose, directly under the Keyframe, or under the wrong parent bone is silently ignored.
function RigKit.buildKeyframeSequence(rest, keys, opts)
	opts = opts or {}
	local ks = Instance.new("KeyframeSequence")
	ks.Name = opts.name or "Clip"
	ks.Loop = opts.loop == true
	ks.Priority = opts.priority or Enum.AnimationPriority.Action
	local defaultStyle = toStyle(opts.style, Enum.PoseEasingStyle.Linear)
	local defaultDir = toDirection(opts.dir, Enum.PoseEasingDirection.In)
	local sorted = table.clone(keys)
	table.sort(sorted, function(x, y)
		return x.time < y.time
	end)
	for _, key in sorted do
		local kf = Instance.new("Keyframe")
		kf.Name = key.name or "Keyframe"
		kf.Time = key.time
		local root = Instance.new("Pose")
		root.Name = opts.rootName or rest.rootName
		root.Weight = 0
		root.CFrame = CFrame.identity
		root.Parent = kf
		local needed = {}
		if opts.full then
			for _, name in rest.order do
				needed[name] = true
			end
		else
			for name in key.pose do
				local cur = rest.bones[name] and name
				assert(cur, "RigKit.buildKeyframeSequence: no bone " .. tostring(name))
				while cur do
					needed[cur] = true
					cur = rest.bones[cur].parent
				end
			end
		end
		local poses = {}
		for _, name in rest.order do
			if needed[name] then
				local b = rest.bones[name]
				local v = key.pose[name]
				local p = Instance.new("Pose")
				p.Name = name
				if v ~= nil or opts.full then
					p.Weight = (type(v) == "table" and v.weight) or 1
					p.CFrame = v ~= nil and poseCF(v) or CFrame.identity
					p.EasingStyle = toStyle(type(v) == "table" and v.style or nil, toStyle(key.style, defaultStyle))
					p.EasingDirection = toDirection(type(v) == "table" and v.dir or nil, toDirection(key.dir, defaultDir))
				else
					p.Weight = 0
					p.CFrame = CFrame.identity
				end
				p.Parent = b.parent and poses[b.parent] or root
				poses[name] = p
			end
		end
		kf.Parent = ks
	end
	return ks
end

-- samplePose(ks, t) -> pose table at time t (per-bone interpolation between that bone's keys, Weight-0 poses
-- ignored). Reference sampler that mirrors what the engine Animator was measured to do in edit mode
-- (Animator:StepAnimations against both rigs):
--   * the easing of the EARLIER key's Pose drives the segment to the next key.
--   * Linear segments blend rotation by NLERP (normalised linear quaternion blend); every other style blends by
--     SLERP (what CFrame:Lerp does) with the eased fraction, extrapolating for Elastic overshoot. Position is
--     linear. nlerp and slerp agree at 0, 0.5 and 1 but differ by ~0.6 deg mid-way on an 80 deg swing.
--   * Constant: In = jump to the next value at once, Out = hold the current value until the next key,
--     InOut = switch at the midpoint.
--   * legacy Cubic has In/Out swapped (Cubic In = 1-(1-a)^3); CubicV2 is the TweenService cubic.
--   * Bounce In/Out = TweenService; Bounce InOut is an engine quirk: both halves use the In curve.
--   * Elastic In/Out = Penner with period 0.3; Elastic InOut = Penner with period 0.45.
-- Every style/direction matched the engine within 0.05 deg. The runtime Timeline.Sampler should do the same.
local function bounceOut(a)
	if a < 1 / 2.75 then
		return 7.5625 * a * a
	elseif a < 2 / 2.75 then
		a -= 1.5 / 2.75
		return 7.5625 * a * a + 0.75
	elseif a < 2.5 / 2.75 then
		a -= 2.25 / 2.75
		return 7.5625 * a * a + 0.9375
	end
	a -= 2.625 / 2.75
	return 7.5625 * a * a + 0.984375
end

local function bounceIn(a)
	return 1 - bounceOut(1 - a)
end

-- ease(style, direction, a) -> blend fraction the engine uses for a Pose segment (see notes above).
local function ease(style, dir, a)
	local In, Out = Enum.PoseEasingDirection.In, Enum.PoseEasingDirection.Out
	if style == Enum.PoseEasingStyle.Linear then
		return a
	elseif style == Enum.PoseEasingStyle.Constant then
		if dir == In then
			return 1
		elseif dir == Out then
			return 0
		end
		return a < 0.5 and 0 or 1
	elseif style == Enum.PoseEasingStyle.Cubic or style == Enum.PoseEasingStyle.CubicV2 then
		if style == Enum.PoseEasingStyle.Cubic then
			dir = (dir == In and Out) or (dir == Out and In) or dir
		end
		if dir == In then
			return a * a * a
		elseif dir == Out then
			return 1 - (1 - a) ^ 3
		end
		return a < 0.5 and 4 * a * a * a or 1 - (-2 * a + 2) ^ 3 / 2
	elseif style == Enum.PoseEasingStyle.Bounce then
		if dir == In then
			return bounceIn(a)
		elseif dir == Out then
			return bounceOut(a)
		end
		return a < 0.5 and bounceIn(2 * a) / 2 or 0.5 + bounceIn(2 * a - 1) / 2
	elseif style == Enum.PoseEasingStyle.Elastic then
		if dir == In then
			return -2 ^ (10 * (a - 1)) * math.sin((a - 1.075) * 2 * math.pi / 0.3)
		elseif dir == Out then
			return 2 ^ (-10 * a) * math.sin((a - 0.075) * 2 * math.pi / 0.3) + 1
		end
		local b = 2 * a - 1
		if b < 0 then
			return -0.5 * 2 ^ (10 * b) * math.sin((b - 0.1125) * 2 * math.pi / 0.45)
		end
		return 0.5 * 2 ^ (-10 * b) * math.sin((b - 0.1125) * 2 * math.pi / 0.45) + 1
	end
	return a
end
RigKit.ease = ease

-- slerp(a, b, alpha): rotation slerp that also extrapolates (alpha < 0 or > 1), position linear.
local function slerp(a, b, alpha)
	local axis, angle = (a.Rotation:Inverse() * b.Rotation):ToAxisAngle()
	local p = a.Position + (b.Position - a.Position) * alpha
	return CFrame.new(p) * a.Rotation * CFrame.fromAxisAngle(axis, angle * alpha)
end
RigKit.slerp = slerp

-- nlerp(a, b, alpha): quaternion nlerp + linear position (what the engine does on Linear segments).
local function toQuat(cf)
	local axis, angle = cf:ToAxisAngle()
	local s = math.sin(angle / 2)
	return axis.X * s, axis.Y * s, axis.Z * s, math.cos(angle / 2)
end

local function nlerp(a, b, alpha)
	local ax, ay, az, aw = toQuat(a)
	local bx, by, bz, bw = toQuat(b)
	if ax * bx + ay * by + az * bz + aw * bw < 0 then
		bx, by, bz, bw = -bx, -by, -bz, -bw
	end
	local x, y, z, w = ax + (bx - ax) * alpha, ay + (by - ay) * alpha, az + (bz - az) * alpha, aw + (bw - aw) * alpha
	local len = math.sqrt(x * x + y * y + z * z + w * w)
	local p = a.Position:Lerp(b.Position, alpha)
	return CFrame.new(p.X, p.Y, p.Z, x / len, y / len, z / len, w / len)
end
RigKit.nlerp = nlerp

-- blendKeys(cf0, cf1, style, direction, a) -> the engine's value between two keys of one bone at fraction a.
local function blendKeys(cf0, cf1, style, dir, a)
	local f = ease(style, dir, a)
	if style == Enum.PoseEasingStyle.Linear then
		return nlerp(cf0, cf1, f)
	end
	return slerp(cf0, cf1, f)
end
RigKit.blendKeys = blendKeys

function RigKit.samplePose(ks, t)
	local tracks = {}
	for _, kf in ks:GetKeyframes() do
		for _, p in kf:GetDescendants() do
			if p:IsA("Pose") and p.Weight > 0 then
				tracks[p.Name] = tracks[p.Name] or {}
				table.insert(tracks[p.Name], { time = kf.Time, pose = p })
			end
		end
	end
	local out = {}
	for name, list in tracks do
		table.sort(list, function(x, y)
			return x.time < y.time
		end)
		if t <= list[1].time then
			out[name] = list[1].pose.CFrame
		elseif t >= list[#list].time then
			out[name] = list[#list].pose.CFrame
		else
			for i = 1, #list - 1 do
				local k0, k1 = list[i], list[i + 1]
				if t >= k0.time and t <= k1.time then
					local a = (t - k0.time) / math.max(k1.time - k0.time, 1e-9)
					out[name] = blendKeys(k0.pose.CFrame, k1.pose.CFrame, k0.pose.EasingStyle, k0.pose.EasingDirection, a)
					break
				end
			end
		end
	end
	return out
end

return RigKit
