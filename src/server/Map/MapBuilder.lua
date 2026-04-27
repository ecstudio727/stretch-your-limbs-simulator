--!strict
-- MapBuilder.lua
-- Builds the whole world: grass plain with the giant tree, an elevated tutorial
-- cliff off to the east that leads back to the tree via a glide, and all four
-- climbing phases wrapping the trunk up to the jump branch.
--
-- JUMP PHYSICS TARGETS (base stats: Gravity=150, JumpPower=65, WalkSpeed=22)
--   * airtime       = 2 * 65 / 150     ≈ 0.867 s
--   * max horiz     = 22 * 0.867       ≈ 19.1 studs
--   * max vertical  = 65^2 / (2*150)   ≈ 14.1 studs
-- Design rule-of-thumb: keep horizontal gaps ≤ 17 studs, vertical steps ≤ 10
-- studs at base stats. Larger gaps are only used where a BouncePad or SpeedPad
-- gives the player a boost. Gaps were widened ~1.5x from the previous pass.
--
-- Tagged attributes (HazardService + Tutorial/Coin services key off these):
--   FadingLeaf / Pendulum / SapConveyor / SporeBeam / BouncePad / SpeedPad
--   IsKillBrick
--   IsCheckpoint / IsJumpBranch / IsJumpTip
--   IsCoin / Value / Phase
--   IsLaunchEdge / IsMainIslandLanding (tutorial floating island)

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local MapBuilder = {}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
-- Cartoon-stylized world: every part gets a tiled stud-pattern Texture
-- on all 6 faces. We tried legacy SurfaceType.Studs first but those don't
-- render visibly in modern Roblox — only the texture overlay actually
-- shows up on screen. Asset is the same stud-pattern image the FlipUI
-- button uses (rbxassetid://137014639625779), at 2 studs per tile, 0.15
-- transparency so the studs read clearly without obliterating the
-- underlying material color.
local STUD_ASSET = "rbxassetid://137014639625779"
local STUD_FACES = {
	Enum.NormalId.Top,    Enum.NormalId.Bottom,
	Enum.NormalId.Left,   Enum.NormalId.Right,
	Enum.NormalId.Front,  Enum.NormalId.Back,
}
local function applyStudTexture(part: Part)
	for _, face in ipairs(STUD_FACES) do
		local t = Instance.new("Texture")
		t.Texture = STUD_ASSET
		t.Face = face
		t.StudsPerTileU = 2
		t.StudsPerTileV = 2
		t.Transparency = 0.15
		t.Parent = part
	end
end

-- Saturation/brightness pump for cartoon-pop colors. Every part's color
-- runs through this so the legacy muddy browns / dull greens get pushed
-- into the bright Pet-Simulator palette without rewriting every call.
-- Tunable: SAT_MUL/ADD lift saturation toward 1.0; VAL_MUL/ADD lift the
-- value (brightness). Hue is preserved so the artistic intent of every
-- existing color is kept.
local SAT_MUL, SAT_ADD = 1.6, 0.2
local VAL_MUL, VAL_ADD = 1.2, 0.15
local function popColor(c: Color3): Color3
	local h, s, v = Color3.toHSV(c)
	s = math.clamp(s * SAT_MUL + SAT_ADD, 0, 1)
	v = math.clamp(v * VAL_MUL + VAL_ADD, 0, 1)
	return Color3.fromHSV(h, s, v)
end

-- Every part in the map runs through newPart, so this is the one-stop
-- guarantee that EVERYTHING in the world has (a) visible stud texture,
-- (b) Plastic material, and (c) a saturated cartoon-pop color. All
-- three overrides apply AFTER the props loop so they win over per-call
-- settings in legacy build code — keeps the cartoon-stylized world
-- consistent without hunting down every callsite.
local function newPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = true
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Material = Enum.Material.Plastic
	p.Color = popColor(p.Color)
	applyStudTexture(p)
	return p
end

local function addBark(part: Part)
	local faces = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }
	for _, face in ipairs(faces) do
		local t = Instance.new("Texture")
		t.Texture = "rbxassetid://6372755229"
		t.Face = face
		t.StudsPerTileU = 16
		t.StudsPerTileV = 16
		t.Transparency = 0.1
		t.Parent = part
	end
end

local function ringPos(center: Vector3, radius: number, angle: number, y: number): Vector3
	return Vector3.new(center.X + math.cos(angle) * radius, y, center.Z + math.sin(angle) * radius)
end

-- Returns (cframe, length) for a Cylinder Shape whose long axis (+X) points
-- from startPos to endPos. The cylinder lies along the segment, midpoint at
-- the average of the two world points. Used by every "branch" and "root"
-- builder so the cylinder orientation logic exists in one place.
local function cylinderAlongCFrame(startPos: Vector3, endPos: Vector3): (CFrame, number)
	local mid = (startPos + endPos) / 2
	local diff = endPos - startPos
	local len = diff.Magnitude
	local dir = diff.Unit
	local refUp = Vector3.new(0, 1, 0)
	if math.abs(dir:Dot(refUp)) > 0.99 then refUp = Vector3.new(1, 0, 0) end
	local sideways = dir:Cross(refUp).Unit
	local up = sideways:Cross(dir).Unit
	return CFrame.fromMatrix(mid, dir, up), len
end

------------------------------------------------------------
-- Decoration helpers. All decoration is CanCollide=false / CanQuery=false
-- / CanTouch=false / CastShadow=false so it purely adds visual flair without
-- perturbing gameplay physics, hazard detection, or performance hotspots.
-- Every decoration part sets CastShadow=false because the spiral already
-- casts its own shadows and per-leaf shadows would tank mobile framerates.
------------------------------------------------------------
local function decorPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	-- Same Plastic + stud-texture + saturation-pop pipeline as newPart so
	-- decoration matches gameplay parts in the cartoon palette.
	p.Material = Enum.Material.Plastic
	p.Color = popColor(p.Color)
	applyStudTexture(p)
	return p
end

-- A tiny HSV shift so sibling platforms don't look identical.
local function tintShift(base: Color3, hOffset: number, sOffset: number, vOffset: number): Color3
	local h, s, v = Color3.toHSV(base)
	h = (h + hOffset) % 1
	s = math.clamp(s + sOffset, 0, 1)
	v = math.clamp(v + vOffset, 0, 1)
	return Color3.fromHSV(h, s, v)
end

------------------------------------------------------------
-- Island template helpers.
--
-- Owen places an "Island" Model in ReplicatedStorage (manually, in
-- Studio — Rojo doesn't manage that root). Every island in the world
-- (main spawn island, tutorial floating island, future floaters) is a
-- CLONE of that template with slight variations applied so they read
-- as siblings rather than duplicates.
--
-- Variations applied per island: HSV color shift on every part, Y-axis
-- rotation, uniform scale. If the template isn't found, builders fall
-- back to procedural geometry so the world still loads.
------------------------------------------------------------
local function findIslandTemplate(): Model?
	local rs = game:GetService("ReplicatedStorage")
	-- Direct names first, in priority order.
	for _, name in ipairs({ "Island", "IslandTemplate", "FloatingIsland", "TemplateIsland" }) do
		local found = rs:FindFirstChild(name)
		if found and found:IsA("Model") then return found end
	end
	-- Fuzzy: any top-level Model with "island" in its name.
	for _, child in ipairs(rs:GetChildren()) do
		if child:IsA("Model") and string.find(string.lower(child.Name), "island") then
			return child
		end
	end
	-- Deep search: any Model anywhere in ReplicatedStorage with "island"
	-- in its name. Catches cases where the template was nested inside a
	-- folder by accident.
	for _, descendant in ipairs(rs:GetDescendants()) do
		if descendant:IsA("Model") and string.find(string.lower(descendant.Name), "island") then
			return descendant
		end
	end
	return nil
end

-- A Model needs a PrimaryPart for PivotTo / ScaleTo to work cleanly.
-- If Owen didn't set one in Studio, pick the largest BasePart by volume
-- so the pivot at least makes geometric sense.
local function ensurePrimaryPart(model: Model)
	if model.PrimaryPart and model.PrimaryPart:IsDescendantOf(model) then return end
	local biggest, bestVol = nil, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > bestVol then biggest, bestVol = d, v end
		end
	end
	if biggest then model.PrimaryPart = biggest end
end

-- Clone the template and apply the requested variations. Returns the
-- cloned Model parented to opts.parent, positioned + rotated + scaled +
-- color-shifted as requested.
--
-- Sizing modes (in priority order):
--   1. opts.targetDiameter — auto-scale so max(width, length) hits this
--      value in world units. This is what you usually want; it's robust
--      to the template's natural size changing.
--   2. opts.scale — fall back to explicit multiplier if targetDiameter
--      not provided. Default 1.
local function cloneIslandWith(template: Model, opts: {
	parent: Instance,
	name: string,
	position: Vector3,
	yRotation: number?,
	scale: number?,
	targetDiameter: number?,
	hueShift: number?,
	satShift: number?,
	valShift: number?,
}): Model
	local clone = template:Clone()
	clone.Name = opts.name
	ensurePrimaryPart(clone)

	-- Walk the clone once. Anchored is non-negotiable (else the parts
	-- fall through the world). HSV variation makes two clones look
	-- like siblings. Stud texture overlay is added so cloned islands
	-- match the rest of the cartoon-stud world; if your template also
	-- has its own stud styling baked in (raised geometry / Texture
	-- instances) and you see "double studs", remove that from the
	-- template — this layer alone keeps the islands consistent.
	local hShift = opts.hueShift or 0
	local sShift = opts.satShift or 0
	local vShift = opts.valShift or 0
	local partCount = 0
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			partCount += 1
			d.Anchored = true
			if hShift ~= 0 or sShift ~= 0 or vShift ~= 0 then
				d.Color = tintShift(d.Color, hShift, sShift, vShift)
			end
			applyStudTexture(d)
		end
	end
	print(("[MapBuilder] Clone '%s': %d parts, target diameter=%s"):format(
		opts.name, partCount, tostring(opts.targetDiameter or "n/a")))

	-- Pick the scale. targetDiameter wins over explicit scale.
	local scale = opts.scale or 1
	if opts.targetDiameter then
		local _, naturalSize = clone:GetBoundingBox()
		local naturalDiameter = math.max(naturalSize.X, naturalSize.Z)
		if naturalDiameter > 0.01 then
			scale = opts.targetDiameter / naturalDiameter
		end
	end
	if scale ~= 1.0 then
		clone:ScaleTo(scale)
	end

	-- Position + rotate via PivotTo.
	clone:PivotTo(CFrame.new(opts.position) * CFrame.Angles(0, opts.yRotation or 0, 0))

	clone.Parent = opts.parent
	return clone
end

-- Phase 1 plank decoration: gnarled roots dangling off the underside, moss
-- strip on one edge, and the occasional little forest mushroom tuft on top.
-- Variation cycles by index so adjacent platforms don't look cloned.
local function decorPhase1Plank(plank: Part, index: number, angle: number, parent: Instance)
	local pos = plank.Position
	local variant = index % 4

	-- Under-plank dangling roots (1–3 thin cylinders).
	local rootCount = 1 + (index % 3)
	for i = 1, rootCount do
		local t = (i - 0.5) / rootCount
		local offsetX = (t - 0.5) * 5
		local offsetZ = ((index + i) % 2 == 0 and 1.2 or -1.2)
		local len = 2.6 + (((index * 7 + i * 3) % 5) * 0.5)
		local root = decorPart({
			Name = "Phase1Root",
			Size = Vector3.new(0.5, len, 0.5),
			Position = pos + Vector3.new(offsetX, -0.5 - len / 2, offsetZ),
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(70, 45, 26),
		})
		-- Orient the cylinder vertically.
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, 0, math.rad(90))
		root.Parent = parent
	end

	-- Moss edge strip (alternates side).
	local mossSide = (index % 2 == 0) and 1 or -1
	local moss = decorPart({
		Name = "Phase1Moss",
		Size = Vector3.new(plank.Size.X * 0.6, 0.3, 1.2),
		Position = pos + Vector3.new(0, 0.55, mossSide * (plank.Size.Z / 2 - 0.6)),
		Material = Enum.Material.Grass,
		Color = tintShift(Color3.fromRGB(70, 130, 60), ((index * 13) % 10) / 100, 0, 0),
	})
	moss.CFrame = CFrame.new(moss.Position) * CFrame.Angles(0, angle + math.rad(90), 0)
	moss.Parent = parent

	-- Variant-specific detail.
	if variant == 0 then
		-- Small red mushroom cap + stem.
		local stemPos = pos + Vector3.new(1.2, 1.0, -0.5)
		local stem = decorPart({
			Name = "Phase1Mushroom",
			Size = Vector3.new(0.3, 0.9, 0.3),
			Position = stemPos,
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(235, 225, 205),
		})
		stem.CFrame = CFrame.new(stem.Position) * CFrame.Angles(0, 0, math.rad(90))
		stem.Shape = Enum.PartType.Cylinder
		stem.Parent = parent

		local cap = decorPart({
			Name = "Phase1MushroomCap",
			Size = Vector3.new(1.3, 0.5, 1.3),
			Position = stemPos + Vector3.new(0, 0.7, 0),
			Shape = Enum.PartType.Ball,
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(200, 55, 45),
		})
		cap.Parent = parent
	elseif variant == 1 then
		-- Fern tuft (3 short grass blades).
		for i = -1, 1 do
			local blade = decorPart({
				Name = "Phase1Fern",
				Size = Vector3.new(0.25, 1.6, 0.25),
				Position = pos + Vector3.new(-1.4 + i * 0.4, 1.1, 0.8),
				Material = Enum.Material.Grass,
				Color = Color3.fromRGB(90, 150, 70),
			})
			blade.CFrame = CFrame.new(blade.Position) * CFrame.Angles(math.rad(i * 8), 0, math.rad(i * 6))
			blade.Parent = parent
		end
	elseif variant == 2 then
		-- Small pile of acorns (3 brown spheres).
		for i = 1, 3 do
			local acorn = decorPart({
				Name = "Phase1Acorn",
				Size = Vector3.new(0.7, 0.7, 0.7),
				Position = pos + Vector3.new(0.5 + (i - 2) * 0.6, 0.9, -1.3 + ((i % 2) * 0.3)),
				Shape = Enum.PartType.Ball,
				Material = Enum.Material.Wood,
				Color = Color3.fromRGB(120, 75, 40),
			})
			acorn.Parent = parent
		end
	else
		-- Twisted side-branch sticking radially outward.
		local outDir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local branch = decorPart({
			Name = "Phase1Twig",
			Size = Vector3.new(3, 0.35, 0.35),
			Position = pos + outDir * (plank.Size.X * 0.4) + Vector3.new(0, 0.6, 0),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(80, 50, 30),
		})
		branch.CFrame = CFrame.new(branch.Position) * CFrame.Angles(0, angle, math.rad(6))
		branch.Parent = parent
	end
end

-- Phase 2 branch decoration: leafy canopy clusters, perpendicular crossbars,
-- hanging vines, and occasional bird nests.
local function decorPhase2Branch(plank: Part, index: number, angle: number, parent: Instance)
	local pos = plank.Position
	local variant = index % 4

	-- Always: one leaf cluster hugging the outward end of the branch.
	local outDir = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local clusterColor = tintShift(
		Color3.fromRGB(70, 140, 60),
		((index * 17) % 12 - 6) / 100,
		0,
		((index * 11) % 10 - 5) / 100
	)
	local cluster = decorPart({
		Name = "Phase2Leaves",
		Size = Vector3.new(4, 3.2, 4),
		Position = pos + outDir * (plank.Size.X * 0.35) + Vector3.new(0, 1.4, 0),
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Grass,
		Color = clusterColor,
	})
	cluster.Parent = parent

	-- Secondary smaller cluster offset toward the inward side.
	local cluster2 = decorPart({
		Name = "Phase2LeavesSmall",
		Size = Vector3.new(2.6, 2.2, 2.6),
		Position = pos + outDir * (plank.Size.X * 0.1) + Vector3.new(0, 1.8, 0),
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.LeafyGrass,
		Color = tintShift(clusterColor, 0.02, 0, -0.04),
	})
	cluster2.Parent = parent

	if variant == 0 then
		-- Perpendicular wooden crossbar.
		local cross = decorPart({
			Name = "Phase2Cross",
			Size = Vector3.new(1, 0.8, 6),
			Position = pos + Vector3.new(0, 0.9, 0),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(98, 66, 42),
		})
		cross.CFrame = CFrame.new(cross.Position) * CFrame.Angles(0, angle + math.rad(90), 0)
		cross.Parent = parent
	elseif variant == 1 then
		-- Hanging vine dangling below.
		local vine = decorPart({
			Name = "Phase2Vine",
			Size = Vector3.new(0.35, 7, 0.35),
			Position = pos + Vector3.new(-1.5, -3.2, 0.8),
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(95, 120, 55),
		})
		vine.CFrame = CFrame.new(vine.Position) * CFrame.Angles(0, 0, math.rad(90))
		vine.Shape = Enum.PartType.Cylinder
		vine.Parent = parent

		-- Leaf tip on the vine.
		local leaf = decorPart({
			Name = "Phase2VineLeaf",
			Size = Vector3.new(1.2, 0.4, 1.2),
			Position = vine.Position + Vector3.new(0, -3.7, 0),
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(85, 150, 65),
		})
		leaf.Parent = parent
	elseif variant == 2 then
		-- Bird nest: woven-looking wood ring + 2 eggs.
		local nest = decorPart({
			Name = "Phase2Nest",
			Size = Vector3.new(2.2, 1.1, 2.2),
			Position = pos + Vector3.new(1.4, 1.1, -0.2),
			Material = Enum.Material.Fabric,
			Color = Color3.fromRGB(110, 80, 50),
		})
		nest.Parent = parent
		for i = -1, 0 do
			local egg = decorPart({
				Name = "Phase2Egg",
				Size = Vector3.new(0.55, 0.7, 0.55),
				Position = nest.Position + Vector3.new(i * 0.3 + 0.2, 0.75, 0.1),
				Shape = Enum.PartType.Ball,
				Material = Enum.Material.SmoothPlastic,
				Color = Color3.fromRGB(220, 210, 180),
			})
			egg.Parent = parent
		end
	else
		-- Simple moss overlay + a lone red berry.
		local moss = decorPart({
			Name = "Phase2Moss",
			Size = Vector3.new(plank.Size.X * 0.7, 0.25, plank.Size.Z * 0.7),
			Position = pos + Vector3.new(0, plank.Size.Y / 2 + 0.15, 0),
			Material = Enum.Material.LeafyGrass,
			Color = Color3.fromRGB(70, 120, 55),
		})
		moss.CFrame = CFrame.new(moss.Position) * CFrame.Angles(0, angle + math.rad(90), 0)
		moss.Parent = parent
		local berry = decorPart({
			Name = "Phase2Berry",
			Size = Vector3.new(0.6, 0.6, 0.6),
			Position = pos + Vector3.new(-1.8, 0.9, 0.6),
			Shape = Enum.PartType.Ball,
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(220, 60, 80),
		})
		berry.Parent = parent
	end
end

-- Phase 3 mushroom decoration: adds a stem dropping toward the rotten floor,
-- a ring of "gill" slats under the cap, scattered spore flecks floating
-- above, and per-cap hue variation so the cavern reads as a fungal ecosystem
-- and not a line of identical purple discs.
local function decorPhase3Mushroom(cap: Part, index: number, angle: number, parent: Instance)
	local pos = cap.Position
	local capSize = cap.Size

	-- Cap is Shape=Cylinder with Size.X=8 as its axis, then rotated by Z=90°,
	-- so the axis points along world Y: the cap's top surface is pos.y + 4 and
	-- the bottom is pos.y - 4. Stem hangs below that bottom.
	local capHalfH = capSize.X / 2

	-- Stem below the cap (pale cream cylinder).
	local stemLen = 3.5 + ((index * 11) % 6) * 0.5
	local stem = decorPart({
		Name = "Phase3Stem",
		Size = Vector3.new(stemLen, 1.4, 1.4),
		Position = pos + Vector3.new(0, -capHalfH - stemLen / 2, 0),
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(235, 220, 200),
	})
	-- Rotate cylinder so its axis (local X) is along world Y.
	stem.CFrame = CFrame.new(stem.Position) * CFrame.Angles(0, 0, math.rad(90))
	stem.Parent = parent

	-- Radial gill slats just beneath the cap bottom. Each slat starts at the
	-- cap's vertical axis and extends outward along its angular direction.
	local gillCount = 8
	local gillLen = 2.8
	for i = 0, gillCount - 1 do
		local gillAng = (i / gillCount) * 2 * math.pi
		local gillCenter = pos + Vector3.new(
			math.cos(gillAng) * (gillLen / 2),
			-capHalfH - 0.2,
			math.sin(gillAng) * (gillLen / 2)
		)
		local gill = decorPart({
			Name = "Phase3Gill",
			Size = Vector3.new(gillLen, 0.25, 0.2),
			Position = gillCenter,
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(170, 140, 200),
		})
		gill.CFrame = CFrame.new(gill.Position) * CFrame.Angles(0, gillAng, 0)
		gill.Parent = parent
	end

	-- 3 glowing spots sprinkled on top of the cap (flat discs on the upper
	-- surface). Cylinder axis is rotated to point up along world Y so the
	-- disc face is parallel to the cap's top.
	for i = 1, 3 do
		local spotAng = (index * 0.3 + i) * 2.1
		local spotR = 1.4 + ((i * 7 + index) % 3) * 0.4
		local spotX = math.cos(spotAng) * spotR
		local spotZ = math.sin(spotAng) * spotR
		local spot = decorPart({
			Name = "Phase3Spot",
			-- X = axis length (thickness of disc when rotated); Y/Z = diameter.
			Size = Vector3.new(0.15, 1.1, 1.1),
			Position = pos + Vector3.new(spotX, capHalfH + 0.08, spotZ),
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 240, 200),
		})
		spot.CFrame = CFrame.new(spot.Position) * CFrame.Angles(0, 0, math.rad(90))
		spot.Parent = parent
	end

	-- Floating spore flecks above the cap (2 tiny neon balls).
	for i = 1, 2 do
		local sporeAng = index + i * 2.7
		local spore = decorPart({
			Name = "Phase3Spore",
			Size = Vector3.new(0.35, 0.35, 0.35),
			Position = pos + Vector3.new(math.cos(sporeAng) * 1.1, 2 + i * 0.9, math.sin(sporeAng) * 1.1),
			Shape = Enum.PartType.Ball,
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(180, 250, 180),
		})
		spore.Transparency = 0.2
		spore.Parent = parent
	end

	-- Per-cap hue shift so the spiral reads as a varied fungal bloom.
	-- Leave BouncePad (orange) caps alone so hazard players read them correctly.
	if not cap:GetAttribute("BouncePad") then
		local shift = ((index * 29) % 7 - 3) / 30 -- ±~0.1 hue
		cap.Color = tintShift(cap.Color, shift, 0, ((index * 19) % 5 - 2) / 30)
	end
end

-- Phase 4 ice decoration: upward crystal spikes of varying heights around
-- the platform edge, with a soft blue glow on about half the steps.
local function decorPhase4Ice(ice: Part, index: number, angle: number, parent: Instance)
	local pos = ice.Position

	-- 3–5 crystal spikes around the platform, pointing upward with slight tilt.
	local spikeCount = 3 + (index % 3)
	for i = 1, spikeCount do
		local spikeAng = (i / spikeCount) * 2 * math.pi + index * 0.4
		local dist = 2.8 + ((i * 5 + index) % 3) * 0.6
		local spikeH = 2.2 + ((i * 11 + index) % 5) * 0.5
		local spike = decorPart({
			Name = "Phase4Crystal",
			Size = Vector3.new(0.6, spikeH, 0.6),
			Position = pos + Vector3.new(math.cos(spikeAng) * dist, 0.5 + spikeH / 2, math.sin(spikeAng) * dist),
			Material = Enum.Material.Ice,
			Color = Color3.fromRGB(200 + ((i * 7 + index) % 20), 230, 255),
		})
		spike.Transparency = 0.2
		spike.CFrame = CFrame.new(spike.Position) * CFrame.Angles(
			math.rad(((index + i) % 5) * 3 - 6),
			spikeAng,
			math.rad(((index * 3 + i) % 5) * 3 - 6)
		)
		spike.Parent = parent
	end

	-- Every other step gets a soft inner glow to break up the monotone ice band.
	if index % 2 == 0 then
		local glow = Instance.new("PointLight")
		glow.Brightness = 1.2
		glow.Range = 9
		glow.Color = Color3.fromRGB(180, 220, 255)
		glow.Parent = ice
	end

	-- Subtle per-step hue variation.
	local base = ice.Color
	ice.Color = tintShift(base, ((index * 23) % 11 - 5) / 120, 0, ((index * 17) % 7 - 3) / 60)
end

------------------------------------------------------------
-- Island + main spawn (post-tutorial spawn, at the tree base)
-- The world has NO flat ground. Instead a single floating grass island
-- sits under the tree, with the spawn pad on top. Falling off drops the
-- player into the void to respawn at their last checkpoint.
------------------------------------------------------------
local ISLAND_RADIUS = 130

-- Forward declaration so buildGroundAndSpawn (defined now) can call the
-- fallback (defined further down the file). Lua only resolves locals
-- that are declared before the closure is created, hence this dance.
local buildProceduralFallbackIsland

local function buildGroundAndSpawn(parent: Instance)
	local islandFolder = Instance.new("Folder")
	islandFolder.Name = "Island"
	islandFolder.Parent = parent

	-- New flow: clone the island Model that Owen placed in
	-- ReplicatedStorage, scaled up so the tree + obby fit on top.
	-- Slightly desaturated relative to the floating tutorial island
	-- so the two feel like siblings rather than identical twins.
	local template = findIslandTemplate()
	if template then
		print(("[MapBuilder] Found island template: '%s' (path: %s)"):format(template.Name, template:GetFullName()))
		local model = cloneIslandWith(template, {
			parent = islandFolder,
			name = "MainIsland",
			position = Vector3.new(0, 0, 0),
			yRotation = math.rad(15),
			targetDiameter = 220,    -- world-size big enough for tree + Phase 1 branches
			hueShift = -0.02,
			satShift = -0.02,
		})
		-- Auto-snap so the island's TOP edge sits at Y=0 (where the tree
		-- expects to start). Saves Owen from caring about template pivot.
		local cf, size = model:GetBoundingBox()
		local topYBefore = cf.Position.Y + size.Y / 2
		model:PivotTo(model:GetPivot() + Vector3.new(0, -topYBefore, 0))
		local _, finalSize = model:GetBoundingBox()
		print(("[MapBuilder] Main island built. Bounding box: %.0f×%.0f×%.0f (W×H×L)"):format(finalSize.X, finalSize.Y, finalSize.Z))
	else
		warn("[MapBuilder] No island Model found in ReplicatedStorage — falling back to procedural island. Place a Model named 'Island' (or anything containing 'island') anywhere under ReplicatedStorage to use a custom one.")
		buildProceduralFallbackIsland(islandFolder)
	end

	-- Spawn pad + SpawnLocation always added on top, regardless of
	-- whether geometry came from template or fallback.
	local spawnPad = newPart({
		Name = "SpawnPad",
		Size = Vector3.new(36, 1, 24),
		Position = Vector3.new(0, 2, Config.Map.TreeTrunkRadius + 18),
		Color = Color3.fromRGB(120, 120, 110),
	})
	spawnPad.Parent = parent

	local spawnLoc = Instance.new("SpawnLocation")
	spawnLoc.Name = "StartSpawn"
	spawnLoc.Size = Vector3.new(8, 1, 8)
	spawnLoc.Position = Vector3.new(0, 3, Config.Map.TreeTrunkRadius + 18)
	spawnLoc.Anchored = true
	spawnLoc.TopSurface = Enum.SurfaceType.Smooth
	spawnLoc.Material = Enum.Material.Plastic
	spawnLoc.BrickColor = BrickColor.new("Bright green")
	spawnLoc.Duration = 0
	spawnLoc.Parent = parent
end

-- Procedural island fallback used when no template Model exists in
-- ReplicatedStorage. Same code that lived inline before, just hoisted
-- so buildGroundAndSpawn can branch on template availability. NOTE: the
-- spawn pad + SpawnLocation are NOT created here — buildGroundAndSpawn
-- adds those after either branch returns, so they exist exactly once.
buildProceduralFallbackIsland = function(islandFolder: Instance)
	local islandThickness = 12

	-- Top grass disc — flat round island surface, top flush with Y=0.
	local grass = newPart({
		Name = "IslandGrass",
		Size = Vector3.new(islandThickness, ISLAND_RADIUS * 2, ISLAND_RADIUS * 2),
		CFrame = CFrame.new(0, -islandThickness / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Shape = Enum.PartType.Cylinder,
		Color = Color3.fromRGB(80, 130, 70),
	})
	grass.Parent = islandFolder

	-- Rocky underside, flared inward as it goes down so the island reads
	-- like a chunk of earth torn out of the ground. Two stacked cylinders
	-- keep the silhouette readable without per-vertex meshing.
	local underTopRadius = ISLAND_RADIUS - 8
	local underTopThickness = 18
	local underTop = newPart({
		Name = "IslandUnderTop",
		Size = Vector3.new(underTopThickness, underTopRadius * 2, underTopRadius * 2),
		CFrame = CFrame.new(0, -islandThickness - underTopThickness / 2, 0)
			* CFrame.Angles(0, 0, math.rad(90)),
		Shape = Enum.PartType.Cylinder,
		Color = Color3.fromRGB(95, 78, 60),
	})
	underTop.Parent = islandFolder

	local underBottomRadius = ISLAND_RADIUS - 36
	local underBottomThickness = 24
	local underBottom = newPart({
		Name = "IslandUnderBottom",
		Size = Vector3.new(underBottomThickness, underBottomRadius * 2, underBottomRadius * 2),
		CFrame = CFrame.new(
			0,
			-islandThickness - underTopThickness - underBottomThickness / 2,
			0
		) * CFrame.Angles(0, 0, math.rad(90)),
		Shape = Enum.PartType.Cylinder,
		Color = Color3.fromRGB(72, 58, 44),
	})
	underBottom.Parent = islandFolder

	-- Decorative boulders around the rim for an organic, irregular edge.
	for i = 1, 14 do
		local angle = (i / 14) * math.pi * 2 + 0.27
		local r = ISLAND_RADIUS - 2 - math.random() * 5
		local px = math.cos(angle) * r
		local pz = math.sin(angle) * r
		local s = 3.5 + math.random() * 4
		local rock = newPart({
			Name = "IslandRock_" .. i,
			Size = Vector3.new(s, s * 0.7, s),
			CFrame = CFrame.new(px, s * 0.35 - 1, pz)
				* CFrame.Angles(
					(math.random() - 0.5) * 0.5,
					math.random() * math.pi * 2,
					(math.random() - 0.5) * 0.5
				),
			Material = Enum.Material.Rock,
			Color = Color3.fromRGB(95, 88, 75),
		})
		rock.Parent = islandFolder
	end

	-- A few grass tufts on top for a lived-in look.
	for i = 1, 8 do
		local angle = math.random() * math.pi * 2
		local r = math.random() * (ISLAND_RADIUS - 30)
		local tuft = newPart({
			Name = "IslandTuft_" .. i,
			Size = Vector3.new(2.5, 1, 2.5),
			Position = Vector3.new(math.cos(angle) * r, 0.5, math.sin(angle) * r),
			Color = Color3.fromRGB(95, 160, 80),
			CanCollide = false,
		})
		tuft.Parent = islandFolder
	end
end

------------------------------------------------------------
-- Tutorial Floating Island
--
-- Sky island offset 60 studs east of the tree at Y=80. Players spawn
-- here on first join. The ONLY way to reach the main world (where the
-- tree obby starts) is to step off the western edge and glide.
--
-- Glide math at level-0 wingspan: forward=20, fall=24, distance from
-- height 80 ≈ 20 × (80/24) ≈ 67 studs. The horizontal gap is 60 studs,
-- so a basic glide just clears it with margin. A non-glider falls
-- short (lateral ≈ 22 studs in walk-speed × airtime) and the ForceField
-- + fall-recovery teleport bounces them back to the island to retry.
--
-- Named parts (TutorialService.lua keys off these names):
--   * IslandTop          — the walkable grass surface
--   * LaunchEdge         — invisible touch trigger at the western drop edge
--   * MainIslandLanding  — wide invisible touch trigger over the main island
--                          ground; touching it counts as a successful glide
------------------------------------------------------------
local function buildTutorialIsland(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "TutorialIsland"
	folder.Parent = parent

	local pos = Config.Map.TutorialIsland.Position   -- (60, 80, 0)

	-- Geometry comes from the same ReplicatedStorage island template the
	-- main island uses — slightly different variation so the two read
	-- as siblings (same family, different mood).
	local template = findIslandTemplate()
	local centerCF: CFrame
	local size: Vector3

	if template then
		local model = cloneIslandWith(template, {
			parent = folder,
			name = "IslandModel",
			position = pos,
			yRotation = math.rad(-30),
			targetDiameter = 60,            -- small floating platform (player walks ~30 studs to step off)
			hueShift = 0.04,
			satShift = 0.06,
			valShift = 0.04,
		})
		centerCF, size = model:GetBoundingBox()
	else
		warn("[MapBuilder] No island template — falling back to procedural tutorial island.")
		-- Fallback procedural island matches the previous design so the
		-- world still loads if Owen hasn't placed the template yet.
		local topY = pos.Y
		local top = newPart({
			Name = "ProcTop",
			Size = Vector3.new(3, 30, 30),
			Shape = Enum.PartType.Cylinder,
			CFrame = CFrame.new(pos.X, topY - 1.5, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(85, 175, 65),
			CanCollide = true,
		})
		top.Parent = folder

		local underYs = { topY - 4, topY - 8, topY - 12 }
		local underDiams = { 26, 18, 10 }
		for i, y in ipairs(underYs) do
			local under = newPart({
				Name = "ProcUnder_" .. i,
				Size = Vector3.new(3, underDiams[i], underDiams[i]),
				Shape = Enum.PartType.Cylinder,
				CFrame = CFrame.new(pos.X, y, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(125, 80, 50),
				CanCollide = false,
				CastShadow = i == 1,
			})
			under.Parent = folder
		end
		centerCF = CFrame.new(pos)
		size = Vector3.new(30, 3, 30)
	end

	-- IslandTop: a tiny invisible anchor part placed at the top-center of
	-- whatever geometry was built. TutorialService.lua finds this part by
	-- name and uses its position for the player-spawn teleport. Decoupling
	-- "where to spawn" from "what part to render" means we can swap
	-- island geometry freely without touching server code.
	local topY = centerCF.Position.Y + size.Y / 2 - 1
	local islandTop = newPart({
		Name = "IslandTop",
		Size = Vector3.new(2, 1, 2),
		Position = Vector3.new(centerCF.Position.X, topY, centerCF.Position.Z),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	islandTop.Parent = folder

	-- LaunchEdge: invisible touch trigger covering the western edge of
	-- the island in world space. Players walking off the west side
	-- pass through it. (Position derived from the cloned-island bounding
	-- box, so it works for any template size or rotation.)
	local westEdgeX = centerCF.Position.X - size.X / 2
	local launchEdge = newPart({
		Name = "LaunchEdge",
		Size = Vector3.new(2, 4, math.max(size.Z * 0.9, 8)),
		Position = Vector3.new(westEdgeX + 1, topY + 2, centerCF.Position.Z),
		Transparency = 1,
		CanCollide = false,
	})
	launchEdge:SetAttribute("IsLaunchEdge", true)
	launchEdge.Parent = folder

	-- MainIslandLanding: huge invisible touch sensor floating just above
	-- the main-island ground. Touching it = tutorial success. Sized big
	-- so any plausible glide trajectory triggers it.
	local landing = newPart({
		Name = "MainIslandLanding",
		Size = Vector3.new(140, 4, 140),
		Position = Vector3.new(0, 4, 0),
		Transparency = 1,
		CanCollide = false,
	})
	landing:SetAttribute("IsMainIslandLanding", true)
	landing.Parent = folder
end

------------------------------------------------------------
-- Trunk
-- The trunk is SOLID everywhere except at two specific knot heights where the
-- Phase 3 interior path threads through. Structure:
--
--   * Lower solid cylinder  Y=0 → entry-band-bottom (player stays outside,
--                           climbing the Phase 1/2 spirals)
--   * Entry ring band       A ring of 16 wall panels with a ~56° gap at
--                           angle π/2 (+Z side) — the entry knot hole
--   * Middle hollow tube    Full ring of 16 panels around a 62-stud tall
--                           section — this is the Phase 3 interior; the
--                           mushroom spiral lives inside r = innerR
--   * Exit ring band        Ring of 16 panels with ~56° gap at angle 3π/2
--                           (-Z side) — the exit knot hole
--   * Upper solid cylinder  Exit-band-top → TreeHeight (Phase 4 climbs the
--                           outside)
--
-- All segments CanCollide=true. Wall panels are ~9.3 studs wide (slight
-- overlap with neighbours so the ring seals without gaps) and 3 studs thick.
------------------------------------------------------------
------------------------------------------------------------
-- Tower-of-Hell phase palette. Each phase has its own neon-saturated
-- color so players can read the floor at a glance from any distance.
-- Used by buildTrunk for the central pillar, and by placeBranch as the
-- default branch color when a section doesn't override it.
------------------------------------------------------------
local PHASE_COLORS = {
	[1] = Color3.fromRGB(235, 55, 55),    -- punchy red base
	[2] = Color3.fromRGB(255, 175, 30),   -- bright yellow-orange mid (was muddy)
	[3] = Color3.fromRGB(60, 215, 90),    -- vivid green interior chamber
	[4] = Color3.fromRGB(155, 90, 245),   -- saturated purple top
}

------------------------------------------------------------
-- Tower-of-Hell tower (replaces the old wooden trunk).
--
-- Four stacked color zones, one per phase:
--   * Phase 1 (Y=0..Phase1.YEnd)        red cylinder
--   * Phase 2 (Phase1.YEnd..bandABottom) orange cylinder
--   * Phase 3 panels (bandABottom..bandCTop) green wall panels with
--                                       knot-hole gaps for the interior
--   * Phase 4 (bandCTop..TreeHeight)    purple cylinder
--
-- The wall panels keep the Phase 3 interior obby intact (sealed middle
-- band + knot-hole entry/exit at angles π/2 and 3π/2). Only the colors
-- and material change vs. the old tree trunk; the structural geometry
-- is unchanged so phase 3 still works.
------------------------------------------------------------
local function buildTrunk(parent: Instance)
	local trunkFolder = Instance.new("Folder")
	trunkFolder.Name = "Tower"
	trunkFolder.Parent = parent

	local center = Config.Map.TreeCenter
	local r = Config.Map.TreeTrunkRadius
	local treeH = Config.Map.TreeHeight
	local wallThickness = 3

	-- Knot band Y ranges (unchanged from the tree trunk — Phase 3 obby
	-- still threads through these knot holes).
	local bandABottom = Config.Map.Phase3.YStart - 1   -- 159
	local bandATop    = Config.Map.Phase3.YStart + 9   -- 169
	local bandCBottom = Config.Map.Phase3.YEnd - 7     -- 233
	local bandCTop    = Config.Map.Phase3.YEnd + 3     -- 243

	-- Phase 1 cylinder (red base, Y=0..Phase1.YEnd).
	local p1H = Config.Map.Phase1.YEnd
	local p1 = newPart({
		Name = "TowerPhase1",
		Size = Vector3.new(p1H, r * 2, r * 2),
		Shape = Enum.PartType.Cylinder,
		Color = PHASE_COLORS[1],
		CFrame = CFrame.new(center + Vector3.new(0, p1H / 2, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		CanCollide = true,
	})
	p1.Parent = trunkFolder

	-- Phase 2 cylinder (orange mid, Phase1.YEnd..bandABottom).
	local p2Bottom = Config.Map.Phase1.YEnd
	local p2H = bandABottom - p2Bottom
	local p2 = newPart({
		Name = "TowerPhase2",
		Size = Vector3.new(p2H, r * 2, r * 2),
		Shape = Enum.PartType.Cylinder,
		Color = PHASE_COLORS[2],
		CFrame = CFrame.new(center + Vector3.new(0, p2Bottom + p2H / 2, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		CanCollide = true,
	})
	p2.Parent = trunkFolder

	-- Phase 4 cylinder (purple top, bandCTop..treeH).
	local p4H = treeH - bandCTop
	local p4 = newPart({
		Name = "TowerPhase4",
		Size = Vector3.new(p4H, r * 2, r * 2),
		Shape = Enum.PartType.Cylinder,
		Color = PHASE_COLORS[4],
		CFrame = CFrame.new(center + Vector3.new(0, bandCTop + p4H / 2, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		CanCollide = true,
	})
	p4.Parent = trunkFolder

	------------------------------------------------------------
	-- Phase 3 wall panels (green ring with knot-hole gaps).
	------------------------------------------------------------
	local PANEL_COUNT = 16
	local panelAngSize = (2 * math.pi) / PANEL_COUNT
	local GAP_HALF_ANGLE = math.rad(28)

	local function ringBand(yLow: number, yHigh: number, gapAngle: number?, nameSuffix: string)
		local h = yHigh - yLow
		local yMid = (yLow + yHigh) / 2
		local centerR = r - wallThickness / 2
		local panelW = panelAngSize * r * 1.08

		for i = 0, PANEL_COUNT - 1 do
			local ang = i * panelAngSize
			if gapAngle then
				local d = ((ang - gapAngle) + math.pi) % (2 * math.pi) - math.pi
				if math.abs(d) < GAP_HALF_ANGLE then
					continue
				end
			end
			local pos = center + Vector3.new(math.cos(ang) * centerR, yMid, math.sin(ang) * centerR)
			local panel = newPart({
				Name = "TowerPanel_" .. nameSuffix .. "_" .. i,
				Size = Vector3.new(panelW, h, wallThickness),
				CFrame = CFrame.new(pos) * CFrame.Angles(0, math.pi / 2 - ang, 0),
				-- Slight per-panel hue variation around green for visual depth.
				Color = tintShift(PHASE_COLORS[3], ((i * 13) % 7 - 3) / 100, 0, ((i * 7) % 5 - 2) / 50),
				CanCollide = true,
			})
			panel.Parent = trunkFolder
		end
	end

	ringBand(bandABottom, bandATop, math.pi / 2, "EntryBand")
	ringBand(bandATop, bandCBottom, nil, "MidBand")
	ringBand(bandCBottom, bandCTop, 3 * math.pi / 2, "ExitBand")

	------------------------------------------------------------
	-- Glowing seam rings between phases. White Neon discs slightly
	-- wider than the tower so they ring around each phase boundary —
	-- gives the silhouette visual rhythm and reads as "you've crossed
	-- into a new floor" cleanly. Three seams: P1↔P2, P2↔P3, P3↔P4.
	------------------------------------------------------------
	local seamY = { Config.Map.Phase1.YEnd, bandABottom, bandCTop }
	local seamR = r + 1.5
	for i, y in ipairs(seamY) do
		local seam = newPart({
			Name = "PhaseSeam_" .. i,
			Size = Vector3.new(2.2, seamR * 2, seamR * 2),
			Shape = Enum.PartType.Cylinder,
			CFrame = CFrame.new(center + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(245, 250, 255),
			CanCollide = false,
		})
		seam.Parent = trunkFolder
	end
end

------------------------------------------------------------
-- Tree entry: root stairs leading from the spawn pad up to the first
-- Phase 1 platform. All gaps ≤ 8 horizontal / ≤ 3 vertical.
-- SpawnPad sits at (0, 2, 40) facing the tree along -Z.
-- Phase 1 spiral starts at angle=pi/2 i.e. position (0, ~7, 26).
------------------------------------------------------------
local function buildTreeEntry(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "TreeEntry"
	folder.Parent = parent

	local steps = {
		{ pos = Vector3.new(0, 3, 33), size = Vector3.new(12, 1, 8) },
		{ pos = Vector3.new(0, 5, 28), size = Vector3.new(10, 1, 6) },
	}
	for i, s in ipairs(steps) do
		local p = newPart({
			Name = "EntryStep_" .. i,
			Size = s.size,
			Position = s.pos,
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(100, 70, 45),
		})
		p.Parent = folder
	end
end

------------------------------------------------------------
-- Phase 1 — Root Ascendance
--
-- Section-based obby modeled on MutatorMayhem's modular section
-- registry. Each section is a self-contained chunk of climb (~15-22
-- studs vertical) demonstrating one mechanic:
--
--   1. JumpBranches      — Pillars. Stepping branches you hop between.
--   2. CrumbleLeaves     — CrumbleTiles. Leaf branches that fade + drop
--                          0.4s after you touch them. Must keep moving.
--   3. PendulumGauntlet  — Pendulums. Branches between two swinging
--                          wrecking-vines that knock you off-balance.
--
-- All sections wrap around the OUTSIDE of the trunk in a continuous
-- spiral. Phase 3 will use the inside-the-trunk hollow zone for an
-- "interior climb" set of sections; Phase 2 + Phase 4 still use legacy
-- platforms until I rebuild them in subsequent passes.
--
-- Every branch is a 6-stud-thick cylinder cFramed radially out of the
-- trunk surface, walkable on top. Stud texture + Plastic material +
-- saturated colors come for free via the newPart helper at the top of
-- the file.
------------------------------------------------------------

-- Shared helper: place a flat glowing platform sticking radially out of
-- the tower at (angle, y). Returns the platform Part. Replaced the old
-- cylinder-branch helper — branches were tree-themed and didn't fit the
-- Tower-of-Hell look. Now the player walks on a flat slab whose top
-- surface is well-defined, no curved-cylinder balancing.
--
-- Geometry:
--   * Reach (radial extent) — derived from `outerR` legacy arg
--   * Width (tangential)    — from legacy `diameter` arg, default 9
--   * Thickness             — fixed 1.5; flat ledge
--
-- Material is forced to Neon so the platform glows in its phase color —
-- the headline "stepping pad of pure light" ToH visual.
local function placeBranch(opts: {
	parent: Instance,
	center: Vector3,
	angle: number,
	y: number,
	name: string,
	color: Color3?,        -- optional; defaults to PHASE_COLORS[opts.phase]
	hazardAttr: string?,   -- "FadingLeaf" / "Pendulum" / etc.
	isCheckpoint: boolean?,
	coinsFolder: Folder?,  -- legacy, no-op
	withCoin: boolean?,    -- legacy, no-op
	diameter: number?,     -- tangential width (default 9, pass 5 for narrow)
	outerR: number?,       -- outer radius of slab tip (default 30)
	phase: number?,        -- attribute for telemetry / drives default color (default 1)
}): Part
	local trunkR = Config.Map.TreeTrunkRadius        -- 22
	local outerR = opts.outerR or 30
	local reach = math.max(outerR - trunkR, 4)        -- radial extent
	local width = opts.diameter or 9                  -- tangential width
	local thickness = 1.5

	-- Slab center at midpoint of (trunkR, outerR), Y offset so the TOP
	-- face sits at opts.y + 0.5 (preserves old plank-top jump heights).
	local centerR = (trunkR + outerR) / 2
	local pos = ringPos(opts.center, centerR, opts.angle, opts.y - thickness / 2 + 0.5)

	local phaseNum = opts.phase or 1
	local color = opts.color or PHASE_COLORS[phaseNum] or Color3.fromRGB(140, 95, 60)
	if opts.isCheckpoint then color = Color3.fromRGB(80, 230, 255) end

	local platform = newPart({
		Name = opts.name,
		Size = Vector3.new(reach, thickness, width),
		-- Rotate so local +X axis points radially outward at this angle.
		CFrame = CFrame.new(pos) * CFrame.Angles(0, -opts.angle, 0),
		Color = color,
		CanCollide = true,
	})
	platform:SetAttribute("Phase", phaseNum)
	if opts.hazardAttr then platform:SetAttribute(opts.hazardAttr, true) end
	if opts.isCheckpoint then platform:SetAttribute("IsCheckpoint", true) end
	-- Material stays Plastic (newPart's default). Per Owen's rule:
	-- nothing in the world is Neon except parts that kill the player.
	platform.Parent = opts.parent

	return platform
end

-- Pendulum hazard helper: a swinging log on a vertical pivot. Uses the
-- existing HazardService Pendulum binding (CFrame-driven on Heartbeat,
-- kills on touch). Pivot Y is `pivotY` above the section midline; arm
-- length controls how far down the swing reaches.
local function placePendulum(opts: {
	parent: Instance,
	pivot: Vector3,
	arm: number,
	period: number,
	phaseOffset: number,
	logSize: Vector3?,
	name: string,
})
	local size = opts.logSize or Vector3.new(2.6, 2.6, 8)
	local hangPos = opts.pivot + Vector3.new(0, -opts.arm, 0)
	local log = newPart({
		Name = opts.name,
		Size = size,
		Position = hangPos,
		Color = Color3.fromRGB(245, 250, 255),
		CanCollide = false,
	})
	log:SetAttribute("Pendulum", true)
	log:SetAttribute("PivotX", opts.pivot.X)
	log:SetAttribute("PivotY", opts.pivot.Y)
	log:SetAttribute("PivotZ", opts.pivot.Z)
	log:SetAttribute("ArmLength", opts.arm)
	log:SetAttribute("Period", opts.period)
	log:SetAttribute("PhaseOffset", opts.phaseOffset)
	-- Pendulums kill on touch — neon white per Owen's "kill = neon white" rule.
	log.Material = Enum.Material.Neon
	log.Color = Color3.fromRGB(245, 250, 255)
	log.Parent = opts.parent
end

------------------------------------------------------------
-- Section: Ladder
-- A vertical TrussPart at angleStart that the player climbs straight up.
-- The truss spans (yStart, yEnd) AND yEnd is the same Y the next
-- section's first platform sits at — so the truss top transitions
-- directly onto the next section's landing. No separate top platform
-- (the previous version had it overlapping both the truss and the next
-- section's first slab, which read as a ladder going to nothing).
-- Returns angleStart unchanged: ladders go vertical only.
-- MutatorMayhem reference: ColumnHop / WallJumps.
------------------------------------------------------------
local function section_Ladder(parent, center, coinsFolder, yStart, yEnd, angleStart, phase): number
	local trunkR = Config.Map.TreeTrunkRadius
	-- Truss center sits 1.5 studs out from the trunk surface so the
	-- player has room to grip without clipping into the tower wall.
	local trussR = trunkR + 1.5
	local trussCenter = ringPos(center, trussR, angleStart, (yStart + yEnd) / 2)
	local trussHeight = yEnd - yStart

	local truss = Instance.new("TrussPart")
	truss.Name = "S_Ladder_P" .. (phase or 1)
	truss.Anchored = true
	truss.Style = Enum.Style.AlternatingSupports
	truss.Size = Vector3.new(2, trussHeight, 2)
	truss.Position = trussCenter
	truss.Color = PHASE_COLORS[phase or 1] or Color3.fromRGB(150, 150, 150)
	truss.Parent = parent

	return angleStart
end

------------------------------------------------------------
-- Section: WallJump
-- Two columns of small platforms at slightly offset angles around
-- angleStart. Player alternates left → right → left as they climb.
-- Forces a different movement pattern than the spiral — you're going
-- straight up, not around the tower.
-- MutatorMayhem reference: WallJumps.
------------------------------------------------------------
local function section_WallJump(parent, center, coinsFolder, yStart, yEnd, angleStart, phase): number
	local count = 6
	local columnDelta = 0.16     -- ~9° angular offset for each column
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local angle = angleStart + ((i % 2 == 0) and -columnDelta or columnDelta)
		local y = yStart + t * (yEnd - yStart)
		placeBranch({
			parent = parent, center = center, coinsFolder = coinsFolder,
			angle = angle, y = y,
			name = "S_Wall_P" .. (phase or 1) .. "_" .. i,
			phase = phase,
			diameter = 5,        -- narrow precision platform
			outerR = 28,         -- closer to trunk than the default 30
			isCheckpoint = (i == count - 1),
		})
	end
	return angleStart           -- WallJump goes vertical, no angular progress
end

------------------------------------------------------------
-- Section: FloatingDiscs
-- 4 free-floating disc platforms at angles around the tower, NOT touching
-- the tower's surface. Player has to jump between them across open air.
-- Discs are small and high-contrast so they read as standalone targets.
-- MutatorMayhem reference: SteppingStones.
------------------------------------------------------------
local function section_FloatingDiscs(parent, center, coinsFolder, yStart, yEnd, angleStart, phase): number
	local count = 4
	local angleSpan = math.pi * 0.45
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local angle = angleStart + t * angleSpan
		local y = yStart + t * (yEnd - yStart)
		-- Floating disc: cylinder shape, far from the trunk surface,
		-- standalone island of platform.
		local discPos = ringPos(center, 38, angle, y)  -- well outside trunk r=22
		local disc = newPart({
			Name = "S_Disc_P" .. (phase or 1) .. "_" .. i,
			Size = Vector3.new(1.5, 7, 7),
			Shape = Enum.PartType.Cylinder,
			CFrame = CFrame.new(discPos) * CFrame.Angles(0, 0, math.rad(90)),
			Color = PHASE_COLORS[phase or 1],
			CanCollide = true,
		})
		disc:SetAttribute("Phase", phase or 1)
		if i == count - 1 then
			disc:SetAttribute("IsCheckpoint", true)
			disc.Color = Color3.fromRGB(80, 230, 255)
		end
		disc.Parent = parent
	end
	return angleStart + angleSpan
end

------------------------------------------------------------
-- Section 1: JumpBranches
-- 5 simple stepping branches in a quarter-spiral, gradually climbing.
-- Warms the player into the obby — no hazards, just timing jumps.
-- MutatorMayhem reference: Pillars, DoubleGap.
------------------------------------------------------------
local function section_JumpBranches(parent, center, coinsFolder, yStart, yEnd, angleStart): number
	local count = 5
	local angleSpan = math.pi * 0.6
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local angle = angleStart + t * angleSpan
		local y = yStart + t * (yEnd - yStart)
		placeBranch({
			parent = parent, center = center, coinsFolder = coinsFolder,
			angle = angle, y = y,
			name = "S1_Jump_" .. i,
			withCoin = (i % 2 == 1),
			isCheckpoint = (i == count - 1),  -- last branch in section is checkpoint
		})
	end
	return angleStart + angleSpan
end

------------------------------------------------------------
-- Section 2: CrumbleLeaves
-- 5 mossy-green branches that fade and drop 0.4s after you touch them
-- (FadingLeaf attribute → HazardService respawns after 6s). Keep moving
-- or fall.
-- MutatorMayhem reference: CrumbleTiles.
------------------------------------------------------------
local function section_CrumbleLeaves(parent, center, coinsFolder, yStart, yEnd, angleStart): number
	local count = 5
	local angleSpan = math.pi * 0.55
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local angle = angleStart + t * angleSpan
		local y = yStart + t * (yEnd - yStart)
		placeBranch({
			parent = parent, center = center, coinsFolder = coinsFolder,
			angle = angle, y = y,
			name = "S2_Crumble_" .. i,
			color = Color3.fromRGB(85, 165, 60),
			hazardAttr = "FadingLeaf",
			withCoin = (i == 1 or i == 3),  -- bonus coins for risk-takers
		})
	end
	return angleStart + angleSpan
end

------------------------------------------------------------
-- Section 3: PendulumGauntlet
-- 4 stepping branches with 2 wrecking-vine pendulums swinging across
-- the path between them. Pendulums knock the player off-balance (handled
-- by HazardService — TakeDamage(MaxHealth) on touch). The trick is
-- timing the swing.
-- MutatorMayhem reference: Pendulums.
------------------------------------------------------------
local function section_PendulumGauntlet(parent, center, coinsFolder, yStart, yEnd, angleStart): number
	local count = 4
	local angleSpan = math.pi * 0.5
	-- Place the 4 walking branches first.
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local angle = angleStart + t * angleSpan
		local y = yStart + t * (yEnd - yStart)
		placeBranch({
			parent = parent, center = center, coinsFolder = coinsFolder,
			angle = angle, y = y,
			name = "S3_Walk_" .. i,
			withCoin = (i == 1 or i == 3),
			isCheckpoint = (i == count - 1),  -- end of phase = checkpoint
		})
	end

	-- 2 pendulums at t=0.33 and t=0.66 — between branches, not on top.
	-- HazardService picks these up via the Pendulum attribute and swings
	-- them on Heartbeat.
	for j = 1, 2 do
		local t = j / 3
		local pivotAngle = angleStart + t * angleSpan
		local pivotY = yStart + t * (yEnd - yStart) + 18  -- pivot 18 studs above the branch
		local pivot = ringPos(center, 30, pivotAngle, pivotY)
		local arm = 14
		-- Initial position: hangs directly below the pivot.
		local hangPos = pivot + Vector3.new(0, -arm, 0)
		local log = newPart({
			Name = "S3_Vine_" .. j,
			Size = Vector3.new(2.6, 2.6, 8),  -- chunky log shape
			Position = hangPos,
			Color = Color3.fromRGB(45, 30, 18),  -- dark vine wood
			CanCollide = false,                  -- HazardService kills on touch instead
		})
		log:SetAttribute("Pendulum", true)
		log:SetAttribute("PivotX", pivot.X)
		log:SetAttribute("PivotY", pivot.Y)
		log:SetAttribute("PivotZ", pivot.Z)
		log:SetAttribute("ArmLength", arm)
		log:SetAttribute("Period", 2.4)
		log:SetAttribute("PhaseOffset", j * math.pi)  -- two pendulums swing opposite each other
		log.Parent = parent
	end

	return angleStart + angleSpan
end

------------------------------------------------------------
-- Phase 1 orchestrator. Stacks the three sections vertically along the
-- trunk in a continuous outward spiral, with their angle ranges chained
-- so the player wraps around the trunk as they climb.
------------------------------------------------------------
local function buildPhase1(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Phase1_RootAscendance"
	folder.Parent = parent

	local coinsFolder = parent:FindFirstChild("Coins") :: Folder?
	local center = Config.Map.TreeCenter
	local yStart = Config.Map.Phase1.YStart
	local yEnd = Config.Map.Phase1.YEnd

	-- Ground-level swamp + hidden trap kept from the legacy phase. They
	-- live BELOW the first section, so they're decoration the player
	-- never directly walks on.
	local swamp = newPart({
		Name = "SwampWater",
		Size = Vector3.new(100, 0.4, 100),
		Position = center + Vector3.new(0, 0.3, 0),
		Color = Color3.fromRGB(60, 80, 60),
		Transparency = 0.2,
		CanCollide = false,
	})
	swamp.Parent = folder

	local trap = newPart({
		Name = "HiddenTrap",
		Size = Vector3.new(5, 0.4, 5),
		Position = center + Vector3.new(-Config.Map.TreeTrunkRadius - 18, 0.2, -26),
		Color = Color3.fromRGB(245, 250, 255),
		Transparency = 0.4,
	})
	trap:SetAttribute("IsKillBrick", true)
	-- Kill brick → neon white (Owen's "kill = neon white" rule).
	trap.Material = Enum.Material.Neon
	trap.Color = Color3.fromRGB(245, 250, 255)
	trap.Parent = folder

	-- Heavy ladder cadence — a ladder between (almost) every main
	-- section so the climb breaks up between vertical and angular
	-- progress every ~10 studs. 5 ladder segments in Phase 1 alone.
	local angle = math.pi / 2  -- start on +Z side, lined up with TreeEntry
	angle = section_Ladder         (folder, center, coinsFolder, yStart + 3,  yStart + 11, angle, 1)
	angle = section_JumpBranches   (folder, center, coinsFolder, yStart + 11, yStart + 22, angle)
	angle = section_Ladder         (folder, center, coinsFolder, yStart + 22, yStart + 30, angle, 1)
	angle = section_CrumbleLeaves  (folder, center, coinsFolder, yStart + 30, yStart + 42, angle)
	angle = section_Ladder         (folder, center, coinsFolder, yStart + 42, yStart + 50, angle, 1)
	angle = section_FloatingDiscs  (folder, center, coinsFolder, yStart + 50, yStart + 58, angle, 1)
	angle = section_Ladder         (folder, center, coinsFolder, yStart + 58, yStart + 66, angle, 1)
	angle = section_PendulumGauntlet(folder, center, coinsFolder, yStart + 66, yEnd - 4, angle)
end

------------------------------------------------------------
-- Section 4: NarrowJumps (Phase 2 opener)
-- 5 thin (4-stud diameter) branches in a partial spiral. Same length as
-- Phase 1's JumpBranches but the curved walking surface is much
-- narrower — the comfort zone shrinks from ~5 studs to ~3. Step-up in
-- difficulty without adding a hazard yet.
-- MutatorMayhem reference: NarrowBeam, TightRope.
------------------------------------------------------------
local function section_NarrowJumps(parent, center, coinsFolder, yStart, yEnd, angleStart): number
	local count = 5
	local angleSpan = math.pi * 0.5
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local angle = angleStart + t * angleSpan
		local y = yStart + t * (yEnd - yStart)
		placeBranch({
			parent = parent, center = center, coinsFolder = coinsFolder,
			angle = angle, y = y,
			name = "S4_Narrow_" .. i,
			diameter = 4,         -- ← tighter walking surface
			withCoin = (i == 1 or i == 3),
			phase = 2,
		})
	end
	return angleStart + angleSpan
end

------------------------------------------------------------
-- Section 5: CrumblePendulum (Phase 2 mid)
-- 5 fading-leaf branches with one swinging pendulum sweeping through
-- the middle of the run. Combines two hazard families — the Crumble
-- forces forward momentum, the Pendulum demands timing. Twice as
-- punishing as either alone.
-- MutatorMayhem reference: CrumbleTiles + Pendulums combo.
------------------------------------------------------------
local function section_CrumblePendulum(parent, center, coinsFolder, yStart, yEnd, angleStart): number
	local count = 5
	local angleSpan = math.pi * 0.55
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local angle = angleStart + t * angleSpan
		local y = yStart + t * (yEnd - yStart)
		placeBranch({
			parent = parent, center = center, coinsFolder = coinsFolder,
			angle = angle, y = y,
			name = "S5_Crumble_" .. i,
			color = Color3.fromRGB(78, 158, 55),
			hazardAttr = "FadingLeaf",
			withCoin = (i == 2),
			phase = 2,
		})
	end
	-- One pendulum sweeping at the section midpoint, slow + wide so it
	-- catches a rushing player.
	local pivotAngle = angleStart + angleSpan * 0.5
	local pivotY = (yStart + yEnd) * 0.5 + 18
	placePendulum({
		parent = parent,
		pivot = ringPos(center, 30, pivotAngle, pivotY),
		arm = 14,
		period = 2.6,
		phaseOffset = 0,
		name = "S5_Vine",
	})
	return angleStart + angleSpan
end

------------------------------------------------------------
-- Section 6: TripleSwing (Phase 2 hard)
-- 4 walking branches surrounded by 3 pendulums all at different phase
-- offsets so the swing pattern is chaotic — there's never a "safe"
-- moment, only timing windows. The hardest section of Phase 2.
-- MutatorMayhem reference: pendulum stacking from the late-game pool.
------------------------------------------------------------
local function section_TripleSwing(parent, center, coinsFolder, yStart, yEnd, angleStart): number
	local count = 4
	local angleSpan = math.pi * 0.5
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local angle = angleStart + t * angleSpan
		local y = yStart + t * (yEnd - yStart)
		placeBranch({
			parent = parent, center = center, coinsFolder = coinsFolder,
			angle = angle, y = y,
			name = "S6_Walk_" .. i,
			withCoin = (i == 1 or i == 2),
			phase = 2,
		})
	end
	-- 3 pendulums at t=0.25 / 0.5 / 0.75, all with different periods +
	-- phase offsets so they never sync up — chaos ladder.
	local periods = { 2.2, 2.6, 3.0 }
	local offsets = { 0, math.pi * 0.66, math.pi * 1.33 }
	for j = 1, 3 do
		local t = j / 4
		local pivotAngle = angleStart + t * angleSpan
		local pivotY = yStart + t * (yEnd - yStart) + 18
		placePendulum({
			parent = parent,
			pivot = ringPos(center, 30, pivotAngle, pivotY),
			arm = 14,
			period = periods[j],
			phaseOffset = offsets[j],
			name = "S6_Vine_" .. j,
		})
	end
	return angleStart + angleSpan
end

------------------------------------------------------------
-- Section 7: KnotApproach (Phase 2 closer)
-- 3 branches steering the player toward the Phase 3 knot-hole entry on
-- the +Z side of the trunk. Final branch is a checkpoint and sits
-- right next to the trunk panel gap at angle π/2. From there a short
-- vine truss climbs to the actual knot-hole entry at Y=164.
------------------------------------------------------------
local function section_KnotApproach(parent, center, coinsFolder, yStart, yEnd, angleEnd): number
	-- Approach angle is the END angle (knot entry), so we compute backwards.
	-- 3 branches stepping into the knot-hole approach.
	local count = 3
	local angleSpan = math.pi * 0.35
	local angleStart = angleEnd - angleSpan
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local angle = angleStart + t * angleSpan
		local y = yStart + t * (yEnd - yStart)
		placeBranch({
			parent = parent, center = center, coinsFolder = coinsFolder,
			angle = angle, y = y,
			name = "S7_Approach_" .. i,
			withCoin = (i == 1),
			isCheckpoint = (i == count - 1),  -- last branch = checkpoint right by knot entry
			phase = 2,
		})
	end
	return angleEnd
end

------------------------------------------------------------
-- Phase 2 — Canopy Perils
--
-- Section-based hard tier. Each section is harder than its Phase 1
-- counterpart: NarrowJumps (thinner branches than Phase 1's chunky
-- ones) → CrumblePendulum (Phase 1's two hazards combined) →
-- TripleSwing (3 chaotic pendulums on simultaneous offset phases) →
-- KnotApproach (steers the player to the Phase 3 knot-hole entry).
--
-- All sections still wrap around the OUTSIDE of the trunk (Owen's
-- "branch obby outside, harder higher" rule). Phase 3's interior obby
-- starts at the knot hole at Y=164, angle π/2.
------------------------------------------------------------
local function buildPhase2_LEGACY_DEAD(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Phase2_Canopy"
	folder.Parent = parent

	local coinsFolder = parent:FindFirstChild("Coins") :: Folder?
	local center = Config.Map.TreeCenter
	local yStart = Config.Map.Phase2.YStart
	local yEnd = Config.Map.Phase2.YEnd

	local platformCount = 16
	local turns = 1.5
	local r = Config.Map.TreeTrunkRadius + 4
	local yRise = yEnd - yStart - 4
	local startAngle = math.pi / 2 + 1.5 * 2 * math.pi -- continues where Phase 1 left off
	local lastPos
	for i = 0, platformCount - 1 do
		local t = i / (platformCount - 1)
		local angle = startAngle + t * turns * math.pi * 2
		local y = yStart + 2 + t * yRise
		local pos = ringPos(center, r, angle, y)

		-- Canopy shape variants: long branch, round leaf pad, and a wider
		-- square "crown" intersection. Rotates every platform so the spiral
		-- reads as a canopy of different tree species, not cloned boxes.
		local shapeVariant = i % 3
		local plat
		if shapeVariant == 0 then
			-- Long rectangular branch, tangent to the spiral.
			plat = newPart({
				Name = "SpiralStep_P2_" .. i,
				Size = Vector3.new(11, 1, 7),
				CFrame = CFrame.new(pos) * CFrame.Angles(0, angle + math.rad(90), 0),
				Material = Enum.Material.Wood,
				Color = Color3.fromRGB(92, 60, 36),
			})
		elseif shapeVariant == 1 then
			-- Wide round leaf pad — a flat circular platform.
			plat = newPart({
				Name = "SpiralStep_P2_" .. i,
				Size = Vector3.new(1, 10.5, 10.5),
				Shape = Enum.PartType.Cylinder,
				CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Wood,
				Color = Color3.fromRGB(95, 64, 40),
			})
		else
			-- Square crown intersection — where two branches meet.
			plat = newPart({
				Name = "SpiralStep_P2_" .. i,
				Size = Vector3.new(9, 1, 9),
				CFrame = CFrame.new(pos) * CFrame.Angles(0, angle + math.rad(90), 0),
				Material = Enum.Material.Wood,
				Color = Color3.fromRGB(88, 58, 34),
			})
		end
		plat:SetAttribute("Phase", 2)

		-- Every 6th platform is a checkpoint.
		if i > 0 and i % 6 == 0 then
			plat.Material = Enum.Material.Plastic
			plat.Color = Color3.fromRGB(80, 200, 220)
			plat:SetAttribute("IsCheckpoint", true)
		end

		plat.Parent = folder
		lastPos = pos

		-- Canopy decoration on normal branches only (keep checkpoints reading cleanly).
		if not plat:GetAttribute("IsCheckpoint") then
			decorPhase2Branch(plat, i, angle, folder)
		end

		-- Main-path coin on every odd platform, floating directly above the landing.
		if coinsFolder and i % 2 == 1 then
			local coin = newPart({
				Name = "Coin",
				Size = Vector3.new(2, 2, 0.4),
				CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
					* CFrame.Angles(0, angle, math.rad(90)),
				Shape = Enum.PartType.Cylinder,
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 210, 60),
				CanCollide = false,
			})
			coin:SetAttribute("Value", Config.Map.CoinValue)
			coin:SetAttribute("Phase", 2)
			coin.Parent = coinsFolder
		end
	end

	-- Pendulum timing hazards at t = 0.25 / 0.5 / 0.75. Swing tangentially so
	-- they sweep across the jump arc between consecutive spiral platforms.
	for i = 1, 3 do
		local t = i / 4
		local angle = startAngle + t * turns * math.pi * 2
		local y = yStart + 2 + t * yRise
		local pivotPos = ringPos(center, r, angle, y + 16)
		local pend = newPart({
			Name = "PendulumLog_" .. i,
			Size = Vector3.new(2, 14, 2),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(60, 40, 30),
		})
		pend:SetAttribute("Pendulum", true)
		pend:SetAttribute("PivotX", pivotPos.X)
		pend:SetAttribute("PivotY", pivotPos.Y)
		pend:SetAttribute("PivotZ", pivotPos.Z)
		pend:SetAttribute("ArmLength", 12)
		pend:SetAttribute("Period", 2.4 + i * 0.3)
		pend:SetAttribute("PhaseOffset", i * 0.8)
		pend.CFrame = CFrame.new(pivotPos.X, pivotPos.Y - 7, pivotPos.Z)
		pend.Parent = folder
	end

	-- Optional radial detour branches with bonus coins (t = 0.2 / 0.4 / 0.6 / 0.8).
	for i = 1, 4 do
		local t = i / 5
		local angle = startAngle + t * turns * math.pi * 2
		local y = yStart + 2 + t * yRise
		local basePos = ringPos(center, r, angle, y)
		local outDir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local branchPos = basePos + outDir * 10
		local branch = newPart({
			Name = "DetourBranch_" .. i,
			Size = Vector3.new(12, 1, 4),
			CFrame = CFrame.new(branchPos) * CFrame.Angles(0, angle + math.rad(90), 0),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(92, 60, 36),
		})
		branch.Parent = folder

		local tip = newPart({
			Name = "DetourTip_" .. i,
			Size = Vector3.new(4, 0.4, 4),
			Position = branchPos + outDir * 7 + Vector3.new(0, 0.2, 0),
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(60, 140, 55),
			CanCollide = false,
		})
		tip.Parent = folder

		-- Bonus coin above the detour tip, routed through the shared Coins folder.
		if coinsFolder then
			local coin = newPart({
				Name = "Coin",
				Size = Vector3.new(2, 2, 0.4),
				CFrame = CFrame.new(tip.Position + Vector3.new(0, 3, 0))
					* CFrame.Angles(0, angle, math.rad(90)),
				Shape = Enum.PartType.Cylinder,
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 210, 60),
				CanCollide = false,
			})
			coin:SetAttribute("Value", Config.Map.CoinValue)
			coin:SetAttribute("Phase", 2)
			coin.Parent = coinsFolder
		end
	end

	-- Vine truss at the top of Phase 2 climbs up alongside the trunk wall to
	-- the Phase 3 knot entry height. The VineTop ledge sits right outside the
	-- knot at y=yEnd+4 so the player can step onto the Phase 3 InteriorEntry.
	local vineBase = lastPos
	local vineTopY = yEnd + 4
	local vine = Instance.new("TrussPart")
	vine.Name = "Phase2To3Vine"
	vine.Anchored = true
	vine.Size = Vector3.new(2, vineTopY - vineBase.Y, 2)
	vine.Position = Vector3.new(vineBase.X, (vineBase.Y + vineTopY) / 2, vineBase.Z)
	vine.Style = Enum.Style.NoSupports
	vine.Color = Color3.fromRGB(95, 115, 60)
	vine.Parent = folder

	local vineTop = newPart({
		Name = "Phase2Top",
		Size = Vector3.new(10, 1, 8),
		Position = Vector3.new(vineBase.X, vineTopY, vineBase.Z - 2),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(120, 80, 50),
	})
	vineTop:SetAttribute("IsCheckpoint", true)
	vineTop.Parent = folder
end

-- New section-based Phase 2. Replaces the legacy 16-platform spiral
-- above. Stacks four progressively-harder sections vertically, ending
-- at a checkpoint right next to the Phase 3 knot-hole entry.
local function buildPhase2(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Phase2_Canopy"
	folder.Parent = parent

	local coinsFolder = parent:FindFirstChild("Coins") :: Folder?
	local center = Config.Map.TreeCenter
	local yStart = Config.Map.Phase2.YStart
	local yEnd = Config.Map.Phase2.YEnd

	-- Heavy ladder cadence — 4 ladder segments interleaved with
	-- horizontal sections. KnotApproach at the end pivots to
	-- math.pi/2 (lined up with the Phase 3 knot-hole entry on +Z).
	local angle = math.pi / 2 + 1.65 * math.pi
	angle = section_NarrowJumps     (folder, center, coinsFolder, yStart,      yStart + 12, angle)
	angle = section_Ladder          (folder, center, coinsFolder, yStart + 12, yStart + 20, angle, 2)
	angle = section_WallJump        (folder, center, coinsFolder, yStart + 20, yStart + 34, angle, 2)
	angle = section_Ladder          (folder, center, coinsFolder, yStart + 34, yStart + 42, angle, 2)
	angle = section_CrumblePendulum (folder, center, coinsFolder, yStart + 42, yStart + 56, angle)
	angle = section_Ladder          (folder, center, coinsFolder, yStart + 56, yStart + 64, angle, 2)
	angle = section_TripleSwing     (folder, center, coinsFolder, yStart + 64, yStart + 74, angle)
	angle = section_Ladder          (folder, center, coinsFolder, yStart + 74, yStart + 78, angle, 2)

	-- KnotApproach takes its end angle as the destination (math.pi/2 +
	-- 2π for a full extra turn so the spiral keeps wrapping rather than
	-- snapping back).
	local knotApproachEndAngle = math.pi / 2 + 2 * math.pi
	section_KnotApproach(folder, center, coinsFolder, yStart + 78, yEnd - 4, knotApproachEndAngle)

	-- Vine truss carrying the player from the final approach branch up
	-- to the Phase 3 knot-hole entry at Y=164. Same connector the legacy
	-- phase used; preserves the inside-the-trunk transition.
	local approachEndPos = ringPos(center, 30, knotApproachEndAngle, yEnd - 4)
	local vineTopY = yEnd + 4
	local vine = Instance.new("TrussPart")
	vine.Name = "Phase2To3Vine"
	vine.Anchored = true
	vine.Size = Vector3.new(2, vineTopY - approachEndPos.Y, 2)
	vine.Position = Vector3.new(approachEndPos.X, (approachEndPos.Y + vineTopY) / 2, approachEndPos.Z)
	vine.Style = Enum.Style.NoSupports
	vine.Color = Color3.fromRGB(95, 115, 60)
	vine.Parent = folder

	local vineTop = newPart({
		Name = "Phase2Top",
		Size = Vector3.new(10, 1, 8),
		Position = Vector3.new(approachEndPos.X, vineTopY, approachEndPos.Z - 2),
		Color = Color3.fromRGB(120, 80, 50),
	})
	vineTop:SetAttribute("IsCheckpoint", true)
	vineTop.Parent = folder
end

------------------------------------------------------------
-- Phase 3 — Rotting Core (interior)
-- Enter the trunk via a knot. Interior spiral of glowing mushrooms, with a
-- sap conveyor and spore beams as hazards. Every 4th mushroom is a
-- BouncePad to let the player skip a full turn of the spiral.
------------------------------------------------------------
local function buildPhase3(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Phase3_RottingCore"
	folder.Parent = parent

	local center = Config.Map.TreeCenter
	local yStart = Config.Map.Phase3.YStart
	local yEnd = Config.Map.Phase3.YEnd

	-- ENTRY KNOT — dark hole in the trunk wall lined up with Phase 2's exit at +Z.
	local entryAngle = math.pi / 2
	local entryOuter = ringPos(center, Config.Map.TreeTrunkRadius + 3, entryAngle, yStart + 4)
	local entryInner = ringPos(center, Config.Map.TreeTrunkRadius - 8, entryAngle, yStart + 4)

	local knot = newPart({
		Name = "KnotEntry",
		Size = Vector3.new(2, 10, 10),
		CFrame = CFrame.new(entryOuter) * CFrame.Angles(0, entryAngle + math.rad(90), 0),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(30, 25, 22),
		CanCollide = false, -- Visual only — it's the dark hole in the trunk wall.
	})
	knot.Parent = folder

	-- Interior landing after the knot — this is the Phase 3 starting platform.
	local interiorPad = newPart({
		Name = "InteriorEntry",
		Size = Vector3.new(8, 1, 8),
		Position = entryInner,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(100, 200, 220),
	})
	interiorPad:SetAttribute("IsCheckpoint", true)
	interiorPad.Parent = folder

	-- Mushroom spiral inside the hollow. 12 caps over 1.5 turns at inner radius
	-- keeps chord ≈ 11.6 studs. The spiral exits on the opposite side of the
	-- trunk at angle entryAngle + 3π (= 3π/2), lining up with Phase 4's start.
	-- Every 3rd mushroom is a BouncePad. Coins float above every other cap.
	local mushroomCount = 12
	local turns = 1.5
	local rise = yEnd - yStart - 8
	local innerR = Config.Map.TreeTrunkRadius - 8
	local coinsFolderMushroom = parent:FindFirstChild("Coins") :: Folder?
	for i = 0, mushroomCount - 1 do
		local t = i / (mushroomCount - 1)
		-- First mushroom sits right next to the interior entry pad.
		local angle = entryAngle + t * turns * math.pi * 2
		local y = yStart + 6 + t * rise
		local pos = ringPos(center, innerR, angle, y)

		-- Cap shape variants. Axis length (Size.X, which rotates into world Y)
		-- is kept at 8 for every variant so the cap's top Y stays at pos.Y + 4
		-- and the landing height is consistent. Only the cross-section
		-- proportions change, giving thicker / wider / narrower fungal caps.
		local capVariant = i % 3
		local capSize
		if capVariant == 0 then
			capSize = Vector3.new(8, 1, 8)    -- baseline
		elseif capVariant == 1 then
			capSize = Vector3.new(8, 2, 10)   -- thicker and wider
		else
			capSize = Vector3.new(8, 1, 6)    -- slim
		end

		local cap = newPart({
			Name = "Mushroom_" .. i,
			Size = capSize,
			Position = pos,
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(130, 80, 220),
		})
		cap.CFrame = CFrame.new(cap.Position) * CFrame.Angles(0, 0, math.rad(90))
		cap.Parent = folder

		local light = Instance.new("PointLight")
		light.Brightness = 2
		light.Range = 20
		light.Color = Color3.fromRGB(170, 110, 255)
		light.Parent = cap

		-- Every 3rd mushroom is a bounce pad — lets the player skip a full step.
		if i > 0 and i % 3 == 0 then
			cap:SetAttribute("BouncePad", true)
			cap.Color = Color3.fromRGB(255, 180, 60)
		end

		-- Rotting-core dressing: stem, gills, spots, spore flecks, hue variation.
		decorPhase3Mushroom(cap, i, angle, folder)

		-- Physical coin pickups removed — coins come from glide distance only.
	end

	-- Sap conveyor: a short frictionless slide tucked to one side. Optional
	-- speed-run shortcut. Players slide down, jump off at escape ledge.
	local slideTop = ringPos(center, innerR, entryAngle + math.rad(90), yStart + rise * 0.7)
	local slide = newPart({
		Name = "SapConveyor",
		Size = Vector3.new(4, 28, 2),
		CFrame = CFrame.new(slideTop + Vector3.new(0, -8, 0)),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(240, 180, 40),
		Transparency = 0.2,
	})
	slide:SetAttribute("SapConveyor", true)
	slide.Parent = folder

	local escape = newPart({
		Name = "SapEscape",
		Size = Vector3.new(6, 1, 4),
		Position = slide.Position + Vector3.new(4, 2, 0),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(85, 55, 35),
	})
	escape:SetAttribute("IsCheckpoint", true)
	escape.Parent = folder

	-- Three rotating spore beams near the top of the interior, each with a
	-- "safe pad" the player can stand on while the beam sweeps past.
	for i = 1, 3 do
		local beam = newPart({
			Name = "SporeBeam_" .. i,
			Size = Vector3.new(Config.Map.TreeTrunkRadius * 1.6, 1, 1),
			Position = center + Vector3.new(0, yEnd - 12 - i * 5, 0),
			Color = Color3.fromRGB(245, 250, 255),
			Transparency = 0.3,
			CanCollide = false,
		})
		beam:SetAttribute("SporeBeam", true)
		-- Spore beams kill on touch → neon white.
		beam.Material = Enum.Material.Neon
		beam.Color = Color3.fromRGB(245, 250, 255)
		beam:SetAttribute("SpinSpeed", 0.8 + i * 0.4)
		beam.Parent = folder

		local safe = newPart({
			Name = "BeamSafePad_" .. i,
			Size = Vector3.new(5, 1, 5),
			Position = beam.Position + Vector3.new(0, 2, Config.Map.TreeTrunkRadius - 6),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(70, 80, 70),
		})
		safe.Parent = folder
	end

	-- Exit knot — an opening in the trunk wall back to the outside at Phase 4 start.
	-- Lines up with the last mushroom's angle so the player can step right onto the exit pad.
	local exitAngle = entryAngle + turns * math.pi * 2
	local exitOuter = ringPos(center, Config.Map.TreeTrunkRadius + 3, exitAngle, yEnd - 2)
	local exitInner = ringPos(center, Config.Map.TreeTrunkRadius - 6, exitAngle, yEnd - 2)

	local exitPad = newPart({
		Name = "InteriorExit",
		Size = Vector3.new(8, 1, 8),
		Position = exitInner,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(100, 200, 220),
	})
	exitPad:SetAttribute("IsCheckpoint", true)
	exitPad.Parent = folder

	local exitKnot = newPart({
		Name = "KnotExit",
		Size = Vector3.new(2, 10, 10),
		CFrame = CFrame.new(exitOuter) * CFrame.Angles(0, exitAngle + math.rad(90), 0),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(30, 25, 22),
		CanCollide = false,
	})
	exitKnot.Parent = folder

	-- A stepping platform just outside the exit knot so the player steps onto
	-- it, then onto the first Phase 4 ice step (which sits one trunk-ring over).
	local exitLanding = newPart({
		Name = "Phase3ExitLanding",
		Size = Vector3.new(8, 1, 8),
		Position = ringPos(center, Config.Map.TreeTrunkRadius + 4, exitAngle, yEnd - 1),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(120, 80, 50),
	})
	exitLanding.Parent = folder
end

------------------------------------------------------------
-- Phase 4 — Apex Crown
-- Frozen branches spiraling up to the jump branch. Speed pad at the end.
-- 13 ice steps over 1 full turn at r=32 → chord ≈ 16.6 studs (~1.4x the old
-- pass). Vertical rise ≈ 7.7 studs per step. Ice friction still makes this
-- feel like the hardest section of the climb. Coins on every other step.
------------------------------------------------------------
local function buildPhase4(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Phase4_ApexCrown"
	folder.Parent = parent

	local coinsFolder = parent:FindFirstChild("Coins") :: Folder?
	local center = Config.Map.TreeCenter
	local yStart = Config.Map.Phase4.YStart
	local yEnd = Config.Map.JumpBranchHeight - 6

	local iceProps = PhysicalProperties.new(0.3, 0.0, 0.5)
	local count = 13
	local turns = 1
	local r = Config.Map.TreeTrunkRadius + 10
	-- Start at Phase 3's exit angle (3π/2, -Z) so the player can step directly
	-- from the exit landing onto the first ice step. Ends at the same angle.
	local startAngle = 3 * math.pi / 2
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local angle = startAngle + t * turns * math.pi * 2
		local y = yStart + 2 + t * (yEnd - yStart - 2)
		local pos = ringPos(center, r, angle, y)

		-- Apex shape variants: square slab, 45° diamond, round crystal disc.
		-- All keep ~1 stud thickness so the top surface is at pos.Y + 0.5 for
		-- consistent landings on the slippery ice physics.
		local iceVariant = i % 3
		local ice
		if iceVariant == 0 then
			-- Square ice slab.
			ice = newPart({
				Name = "IceStep_" .. i,
				Size = Vector3.new(10, 1, 10),
				CFrame = CFrame.new(pos) * CFrame.Angles(0, angle + math.rad(90), 0),
				Material = Enum.Material.Ice,
				Color = Color3.fromRGB(190, 225, 245),
			})
		elseif iceVariant == 1 then
			-- Diamond — square rotated 45°, so corners point toward/away from the trunk.
			ice = newPart({
				Name = "IceStep_" .. i,
				Size = Vector3.new(9, 1, 9),
				CFrame = CFrame.new(pos)
					* CFrame.Angles(0, angle + math.rad(90) + math.rad(45), 0),
				Material = Enum.Material.Ice,
				Color = Color3.fromRGB(195, 230, 248),
			})
		else
			-- Round crystal disc.
			ice = newPart({
				Name = "IceStep_" .. i,
				Size = Vector3.new(1, 10, 10),
				Shape = Enum.PartType.Cylinder,
				CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Ice,
				Color = Color3.fromRGB(200, 232, 250),
			})
		end
		ice.CustomPhysicalProperties = iceProps
		ice:SetAttribute("IceSurface", true)
		ice:SetAttribute("Phase", 4)
		ice.Parent = folder

		-- Apex-crown dressing: upward crystal spikes + soft blue glow.
		decorPhase4Ice(ice, i, angle, folder)

		-- Physical coin pickups removed — coins come from glide distance only.
	end

	-- Speed pad sits just above the spiral's final step (angle 3π/2, -Z side).
	local speedPadPos = center + Vector3.new(0, yEnd + 2, -(Config.Map.TreeTrunkRadius + 6))
	local speedPad = newPart({
		Name = "SpeedPad",
		Size = Vector3.new(6, 0.5, 6),
		Position = speedPadPos,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 100, 100),
	})
	speedPad:SetAttribute("SpeedPad", true)
	speedPad.Parent = folder

	-- Final jump branch extending out in -Z direction (away from the tutorial
	-- cliff). Player runs along it and glides over the open landscape.
	local branchLen = Config.Map.JumpBranchLength
	local trunkR = Config.Map.TreeTrunkRadius
	local branchPos = center + Vector3.new(0, Config.Map.JumpBranchHeight, -(trunkR + branchLen / 2))
	local branch = newPart({
		Name = "JumpBranch",
		Size = Vector3.new(8, 3, branchLen),
		Position = branchPos,
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(92, 60, 36),
	})
	branch:SetAttribute("IsJumpBranch", true)
	branch.Parent = folder
	addBark(branch)

	local tip = newPart({
		Name = "JumpTip",
		Size = Vector3.new(8, 1, 6),
		Position = branchPos + Vector3.new(0, 2, -branchLen / 2),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 220, 90),
		Transparency = 0.3,
	})
	tip:SetAttribute("IsJumpTip", true)
	tip.Parent = folder
end

------------------------------------------------------------
-- Base ring (replaces the old root flares for the ToH tower). A single
-- thicker disc sitting flush at Y=0, color-matched to Phase 1 so the
-- bottom reads as the tower's foundation. No root cylinders — neon
-- towers don't have organic bark roots, that was tree-specific.
------------------------------------------------------------
local function buildRoots(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "BaseRing"
	folder.Parent = parent

	local center = Config.Map.TreeCenter
	local r = Config.Map.TreeTrunkRadius

	-- A flat disc 5 studs wider than the trunk, 2 studs tall, sitting
	-- centered on Y=1 so the top is at Y=2 (just above the spawn pad).
	-- Same red as Phase 1 so it reads as the tower's plinth.
	local ring = newPart({
		Name = "BaseDisc",
		Size = Vector3.new(2, (r + 5) * 2, (r + 5) * 2),
		Shape = Enum.PartType.Cylinder,
		CFrame = CFrame.new(center + Vector3.new(0, 1, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = PHASE_COLORS[1],
		CanCollide = true,
	})
	ring.Parent = folder
end

------------------------------------------------------------
-- Summit podium. Replaces the leafy canopy. A small white-glowing
-- platform with a neon rainbow ring around its rim — the player's
-- reward for reaching the top, and the launch point for the glide.
-- Just three parts: a white disc, a neon torus-style ring (six color
-- segments), and a glowing core dome on top.
------------------------------------------------------------
local function buildCanopy(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Summit"
	folder.Parent = parent

	local center = Config.Map.TreeCenter
	local treeTop = Config.Map.TreeHeight   -- 340

	-- Main podium disc — bright white, sits directly on top of Phase 4.
	-- 60 studs wide (tripled from 32) so it reads clearly as the
	-- "trophy summit" from the spawn point and from the floating
	-- tutorial island.
	local podium = newPart({
		Name = "SummitPodium",
		Size = Vector3.new(3, 60, 60),
		Shape = Enum.PartType.Cylinder,
		CFrame = CFrame.new(center + Vector3.new(0, treeTop + 1.5, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(245, 248, 255),
		CanCollide = true,
	})
	podium.Parent = folder

	-- Rainbow rim — 6 small cylinders arranged around the podium's
	-- circumference, each a different neon color. Rolls all the floor
	-- colors back into one place at the top: a "you climbed all of
	-- this" trophy ring.
	local rimColors = {
		Color3.fromRGB(230, 60, 60),
		Color3.fromRGB(255, 140, 40),
		Color3.fromRGB(255, 215, 60),
		Color3.fromRGB(60, 210, 90),
		Color3.fromRGB(80, 140, 255),
		Color3.fromRGB(150, 95, 240),
	}
	local rimSegmentCount = 30
	local rimR = 30   -- tripled from 16 to ring the bigger podium
	for i = 0, rimSegmentCount - 1 do
		local ang = (i / rimSegmentCount) * math.pi * 2
		local seg = newPart({
			Name = "SummitRim_" .. i,
			Size = Vector3.new(2.4, 2.4, 2.4),
			Shape = Enum.PartType.Cylinder,
			CFrame = CFrame.new(center + Vector3.new(math.cos(ang) * rimR, treeTop + 3.6, math.sin(ang) * rimR))
				* CFrame.Angles(0, math.pi / 2 - ang, 0),
			Color = rimColors[(i % #rimColors) + 1],
			CanCollide = false,
			CastShadow = false,
		})
		seg.Parent = folder
	end

	-- Central glow dome — half-sphere on top of the podium, emissive
	-- via Neon material override (ignored by the helper's Plastic
	-- override; we set it explicitly here so the summit pops).
	local core = newPart({
		Name = "SummitCore",
		Size = Vector3.new(10, 10, 10),
		Shape = Enum.PartType.Ball,
		Position = center + Vector3.new(0, treeTop + 6, 0),
		Color = Color3.fromRGB(255, 255, 255),
		CanCollide = false,
	})
	core.Parent = folder
end

------------------------------------------------------------
-- Create the shared Coins folder early so per-phase builders can drop
-- pickupable coins into it and CoinService will bind them all.
------------------------------------------------------------
local function ensureCoinsFolder(parent: Instance): Folder
	local existing = parent:FindFirstChild("Coins") :: Folder?
	if existing then return existing end
	local f = Instance.new("Folder")
	f.Name = "Coins"
	f.Parent = parent
	return f
end

------------------------------------------------------------
-- Atmospheric particles — falling leaves outside
------------------------------------------------------------
local function buildAtmosphere(parent: Instance)
	local emitter = newPart({
		Name = "AtmosphereEmitter",
		Size = Vector3.new(400, 1, 400),
		Position = Config.Map.TreeCenter + Vector3.new(0, Config.Map.TreeHeight + 60, 0),
		Transparency = 1,
		CanCollide = false,
	})
	emitter.Parent = parent

	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxassetid://241650934"
	pe.Rate = 30
	pe.Lifetime = NumberRange.new(6, 10)
	pe.Speed = NumberRange.new(2, 4)
	pe.Drag = 1.5
	pe.Acceleration = Vector3.new(1, -6, 0)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-60, 60)
	pe.Color = ColorSequence.new(Color3.fromRGB(200, 140, 60))
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Size = NumberSequence.new(0.6)
	pe.Parent = emitter
end

------------------------------------------------------------
-- Public
------------------------------------------------------------
function MapBuilder.build(): Folder
	local existing = Workspace:FindFirstChild("Map")
	if existing then existing:Destroy() end

	-- Strip any default Studio Baseplate / SpawnLocation so the world is
	-- a void with only our floating island below the tree.
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("BasePart") and (child.Name == "Baseplate" or child.Name == "Ground") then
			child:Destroy()
		elseif child:IsA("SpawnLocation") and child.Name ~= "StartSpawn" then
			child:Destroy()
		end
	end

	-- Falling off the island should kill the player promptly. The island's
	-- lowest geometry sits around Y = -54, so anywhere below ~-100 is safe.
	pcall(function()
		Workspace.FallenPartsDestroyHeight = -120
	end)

	local map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = Workspace

	-- Create the Coins folder up front so phase builders can drop their
	-- pickupable coins directly into it.
	ensureCoinsFolder(map)

	buildGroundAndSpawn(map)
	buildTutorialIsland(map)
	buildTrunk(map)
	buildRoots(map)               -- flared roots at base — anchors silhouette
	buildTreeEntry(map)
	buildPhase1(map)              -- climbable branches sticking radially from trunk
	buildPhase2(map)
	buildPhase3(map)
	buildPhase4(map)
	buildCanopy(map)              -- chunky 17-sphere foliage crown
	buildAtmosphere(map)

	print("[MapBuilder] World built. Jump branch @ Y =", Config.Map.JumpBranchHeight)
	return map
end

return MapBuilder
