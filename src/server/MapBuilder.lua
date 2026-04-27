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
--   IsTutorialCoin / IsTutorialLedge / IsTutorialLanding

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local MapBuilder = {}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function newPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = true
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
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

local function buildGroundAndSpawn(parent: Instance)
	local islandFolder = Instance.new("Folder")
	islandFolder.Name = "Island"
	islandFolder.Parent = parent

	local islandThickness = 12

	-- Top grass disc — flat round island surface, top flush with Y=0.
	local grass = newPart({
		Name = "IslandGrass",
		Size = Vector3.new(islandThickness, ISLAND_RADIUS * 2, ISLAND_RADIUS * 2),
		CFrame = CFrame.new(0, -islandThickness / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Grass,
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
		Material = Enum.Material.Rock,
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
		Material = Enum.Material.Rock,
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
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(95, 160, 80),
			CanCollide = false,
		})
		tuft.Parent = islandFolder
	end

	-- A paved pad at the tree entrance.
	local spawnPad = newPart({
		Name = "SpawnPad",
		Size = Vector3.new(36, 1, 24),
		Position = Vector3.new(0, 2, Config.Map.TreeTrunkRadius + 18),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(120, 120, 110),
	})
	spawnPad.Parent = parent

	local spawnLoc = Instance.new("SpawnLocation")
	spawnLoc.Name = "StartSpawn"
	spawnLoc.Size = Vector3.new(8, 1, 8)
	spawnLoc.Position = Vector3.new(0, 3, Config.Map.TreeTrunkRadius + 18)
	spawnLoc.Anchored = true
	spawnLoc.TopSurface = Enum.SurfaceType.Smooth
	spawnLoc.Material = Enum.Material.Neon
	spawnLoc.BrickColor = BrickColor.new("Bright green")
	spawnLoc.Duration = 0
	spawnLoc.Parent = parent
end

------------------------------------------------------------
-- Practice Cliff (tutorial area)
-- A real elevated cliff to the east, plateau at Y=45, facing the tree.
-- Flow: spawn on plateau -> grab coin -> walk to west edge -> step off ->
--       auto-glide over grass -> land near the tree base.
------------------------------------------------------------
local function buildPracticeCliff(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "PracticeCliff"
	folder.Parent = parent

	local plateauY = Config.Map.PracticeCliff.Height -- 45
	local cliffCenter = Config.Map.PracticeCliff.Position -- (160, 0, 0)

	-- Small floating rock base so the cliff reads as its own crag floating
	-- in the void rather than a hovering box. Wider than the pillar; flush
	-- top with where the (now-removed) ground used to be.
	local cliffBase = newPart({
		Name = "CliffBase",
		Size = Vector3.new(14, 70, 56),
		CFrame = CFrame.new(cliffCenter.X + 20, -7, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Rock,
		Color = Color3.fromRGB(95, 80, 65),
	})
	cliffBase.Parent = folder

	local cliffBaseUnder = newPart({
		Name = "CliffBaseUnder",
		Size = Vector3.new(20, 36, 30),
		CFrame = CFrame.new(cliffCenter.X + 20, -24, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Rock,
		Color = Color3.fromRGB(72, 58, 44),
	})
	cliffBaseUnder.Parent = folder

	-- BIG rocky cliff face. Solid stone pillar rising from the floating base.
	local pillar = newPart({
		Name = "CliffPillar",
		Size = Vector3.new(60, plateauY, 46),
		Position = Vector3.new(cliffCenter.X + 20, plateauY / 2, 0),
		Material = Enum.Material.Rock,
		Color = Color3.fromRGB(110, 100, 90),
	})
	pillar.Parent = folder

	-- Plateau top — the walkable surface.
	local plateau = newPart({
		Name = "Plateau",
		Size = Vector3.new(50, 2, 30),
		Position = Vector3.new(cliffCenter.X + 15, plateauY + 1, 0),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(140, 130, 115),
	})
	plateau.Parent = folder

	-- A grassy cap on the plateau to make it feel natural.
	local grassCap = newPart({
		Name = "PlateauGrass",
		Size = Vector3.new(48, 0.2, 28),
		Position = Vector3.new(cliffCenter.X + 15, plateauY + 2.1, 0),
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(85, 150, 75),
		CanCollide = false,
	})
	grassCap.Parent = folder

	-- Stone pedestal for the tutorial coin, in the middle of the plateau.
	local pedestal = newPart({
		Name = "TutorialPedestal",
		Size = Vector3.new(5, 2, 5),
		Position = Vector3.new(cliffCenter.X + 10, plateauY + 3, 0),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(100, 90, 80),
	})
	pedestal.Parent = folder

	-- Floating spinning coin above the pedestal.
	local coin = newPart({
		Name = "TutorialCoin",
		Size = Vector3.new(3, 3, 0.5),
		CFrame = CFrame.new(pedestal.Position + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 220, 70),
		CanCollide = false,
	})
	coin:SetAttribute("IsTutorialCoin", true)
	coin:SetAttribute("Value", 10)
	coin.Parent = folder

	-- A coin glow light for visual pop.
	local coinLight = Instance.new("PointLight")
	coinLight.Brightness = 3
	coinLight.Range = 15
	coinLight.Color = Color3.fromRGB(255, 230, 120)
	coinLight.Parent = coin

	-- Wooden walkway stretching from the pedestal area toward the west edge.
	-- This visually nudges the player toward the cliff edge.
	local walkway = newPart({
		Name = "Walkway",
		Size = Vector3.new(18, 0.6, 6),
		Position = Vector3.new(cliffCenter.X - 4, plateauY + 2.3, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(150, 110, 75),
	})
	walkway.Parent = folder

	-- Two wooden railing posts at the edge — gives the "cliff lip" some shape.
	for _, sign in ipairs({ -1, 1 }) do
		local post = newPart({
			Name = "EdgePost",
			Size = Vector3.new(0.6, 4, 0.6),
			Position = Vector3.new(cliffCenter.X - 15, plateauY + 4, sign * 4),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(130, 90, 55),
		})
		post.Parent = folder
	end

	-- Sign post with a BillboardGui "JUMP!" marker above the cliff edge so the
	-- player has a visual target without relying on the tutorial arrow alone.
	local signPost = newPart({
		Name = "SignPost",
		Size = Vector3.new(0.8, 8, 0.8),
		Position = Vector3.new(cliffCenter.X - 13, plateauY + 6, -8),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(130, 90, 55),
	})
	signPost.Parent = folder

	local signGui = Instance.new("BillboardGui")
	signGui.Size = UDim2.new(0, 120, 0, 50)
	signGui.StudsOffset = Vector3.new(0, 4, 0)
	signGui.AlwaysOnTop = false
	signGui.MaxDistance = 400
	signGui.Adornee = signPost
	signGui.Parent = signPost

	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.new(1, 0, 1, 0)
	signLabel.BackgroundTransparency = 0.2
	signLabel.BackgroundColor3 = Color3.fromRGB(80, 40, 20)
	signLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
	signLabel.Font = Enum.Font.GothamBlack
	signLabel.TextSize = 28
	signLabel.Text = "JUMP!"
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = signLabel
	signLabel.Parent = signGui

	-- Invisible trigger right at the west edge — fires when the player walks off.
	local edgeTrigger = newPart({
		Name = "TutorialLedgeEdge",
		Size = Vector3.new(2, 10, 28),
		Position = Vector3.new(cliffCenter.X - 14, plateauY + 5, 0),
		Transparency = 1,
		CanCollide = false,
	})
	edgeTrigger:SetAttribute("IsTutorialLedge", true)
	edgeTrigger.Parent = folder

	-- Also keep a visible ledge part for the arrow to point at.
	local ledge = newPart({
		Name = "TutorialLedge",
		Size = Vector3.new(2, 0.5, 10),
		Position = Vector3.new(cliffCenter.X - 13, plateauY + 2.6, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(190, 140, 80),
	})
	ledge.Parent = folder

	-- Landing trigger: an invisible volume floating just above the tree
	-- island so any auto-glide that reaches the island fires the "landed"
	-- event. The visible landing surface is the island grass below.
	local landing = newPart({
		Name = "TutorialLandingPad",
		Size = Vector3.new(160, 12, 80),
		Position = Vector3.new(50, 6, 0),
		Transparency = 1,
		CanCollide = false,
	})
	landing:SetAttribute("IsTutorialLanding", true)
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
local function buildTrunk(parent: Instance)
	local trunkFolder = Instance.new("Folder")
	trunkFolder.Name = "Trunk"
	trunkFolder.Parent = parent

	local center = Config.Map.TreeCenter
	local r = Config.Map.TreeTrunkRadius
	local treeH = Config.Map.TreeHeight
	local wallThickness = 3

	-- Knot band Y ranges. Band A contains the Phase 3 entry knot at angle π/2;
	-- Band C contains the Phase 3 exit knot at angle 3π/2. The middle band is
	-- a sealed ring around the interior so the player can't walk back out the
	-- wrong side of the trunk after entering.
	local bandABottom = Config.Map.Phase3.YStart - 1   -- 159
	local bandATop    = Config.Map.Phase3.YStart + 9   -- 169
	local bandCBottom = Config.Map.Phase3.YEnd - 7     -- 233
	local bandCTop    = Config.Map.Phase3.YEnd + 3     -- 243

	------------------------------------------------------------
	-- Lower solid cylinder (Y=0 to entry band).
	------------------------------------------------------------
	local lowerH = bandABottom
	local lower = newPart({
		Name = "TrunkLower",
		Size = Vector3.new(lowerH, r * 2, r * 2),
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(92, 60, 36),
		CFrame = CFrame.new(center + Vector3.new(0, lowerH / 2, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		CanCollide = true,
	})
	lower.Parent = trunkFolder
	addBark(lower)

	------------------------------------------------------------
	-- Upper solid cylinder (exit band top → tree top).
	------------------------------------------------------------
	local upperH = treeH - bandCTop
	local upper = newPart({
		Name = "TrunkUpper",
		Size = Vector3.new(upperH, r * 2, r * 2),
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(95, 63, 38),
		CFrame = CFrame.new(center + Vector3.new(0, bandCTop + upperH / 2, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		CanCollide = true,
	})
	upper.Parent = trunkFolder
	addBark(upper)

	------------------------------------------------------------
	-- Ring-band helper: 16 arc-tangent wall panels; optional angular gap.
	------------------------------------------------------------
	local PANEL_COUNT = 16
	local panelAngSize = (2 * math.pi) / PANEL_COUNT
	-- ~56° opening. Arc chord at r=22 ≈ 20 studs — plenty to walk through.
	local GAP_HALF_ANGLE = math.rad(28)

	local function ringBand(yLow: number, yHigh: number, gapAngle: number?, nameSuffix: string)
		local h = yHigh - yLow
		local yMid = (yLow + yHigh) / 2
		-- Panel outer face should sit at r; panel thickness is radial, so the
		-- panel center is at r - wallThickness/2.
		local centerR = r - wallThickness / 2
		-- Tangential width: the chord across the arc segment plus a small overlap
		-- (1.08x) so adjacent panels seal without visible seams.
		local panelW = panelAngSize * r * 1.08

		for i = 0, PANEL_COUNT - 1 do
			local ang = i * panelAngSize
			if gapAngle then
				-- Angular distance from this panel to the gap center, wrapped to [-π, π].
				local d = ((ang - gapAngle) + math.pi) % (2 * math.pi) - math.pi
				if math.abs(d) < GAP_HALF_ANGLE then
					continue
				end
			end
			local pos = center + Vector3.new(math.cos(ang) * centerR, yMid, math.sin(ang) * centerR)
			local panel = newPart({
				Name = "TrunkPanel_" .. nameSuffix .. "_" .. i,
				Size = Vector3.new(panelW, h, wallThickness),
				-- Rotate so the panel's outer face (+Z local) points radially outward.
				CFrame = CFrame.new(pos) * CFrame.Angles(0, math.pi / 2 - ang, 0),
				Material = Enum.Material.Wood,
				-- Subtle per-panel color variation for a more organic look.
				Color = Color3.fromRGB(88 + (i % 3) * 4, 58 + (i % 2) * 4, 34 + (i % 4) * 3),
				CanCollide = true,
			})

			-- Bark texture on the outward face only (saves 3 textures per panel).
			local tex = Instance.new("Texture")
			tex.Texture = "rbxassetid://6372755229"
			tex.Face = Enum.NormalId.Front
			tex.StudsPerTileU = 12
			tex.StudsPerTileV = 12
			tex.Transparency = 0.1
			tex.Parent = panel

			panel.Parent = trunkFolder
		end
	end

	-- Band A (entry knot band, hole at +Z).
	ringBand(bandABottom, bandATop, math.pi / 2, "EntryBand")
	-- Band B (sealed middle — wraps the Phase 3 interior).
	ringBand(bandATop, bandCBottom, nil, "MidBand")
	-- Band C (exit knot band, hole at -Z).
	ringBand(bandCBottom, bandCTop, 3 * math.pi / 2, "ExitBand")
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
-- 16 platforms over 1.5 turns at r=26 → chord ≈ 16.1 studs (~1.5x wider than
-- the previous 24-platform pass). Vertical rise ≈ 4.8 studs per platform.
-- Every 6th platform is a FadingLeaf, every 8th is a checkpoint.
-- Coins float directly above every other platform so they're scooped up as
-- the player lands on each jump.
------------------------------------------------------------
local function buildPhase1(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Phase1_RootAscendance"
	folder.Parent = parent

	local coinsFolder = parent:FindFirstChild("Coins") :: Folder?
	local center = Config.Map.TreeCenter
	local yStart = Config.Map.Phase1.YStart
	local yEnd = Config.Map.Phase1.YEnd

	-- Decorative swamp water ring around the trunk.
	local swamp = newPart({
		Name = "SwampWater",
		Size = Vector3.new(100, 0.4, 100),
		Position = center + Vector3.new(0, 0.3, 0),
		Material = Enum.Material.Water,
		Color = Color3.fromRGB(60, 80, 60),
		Transparency = 0.2,
		CanCollide = false,
	})
	swamp.Parent = folder

	-- Hidden kill brick under murky water, just off the main path.
	local trap = newPart({
		Name = "HiddenTrap",
		Size = Vector3.new(5, 0.4, 5),
		Position = center + Vector3.new(-Config.Map.TreeTrunkRadius - 18, 0.2, -26),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(35, 50, 40),
		Transparency = 0.4,
	})
	trap:SetAttribute("IsKillBrick", true)
	trap.Parent = folder

	local platformCount = 16
	local turns = 1.5
	local yRise = yEnd - yStart - 4
	local r = Config.Map.TreeTrunkRadius + 4
	-- Start the spiral on the +Z side so it connects directly to the TreeEntry.
	local startAngle = math.pi / 2
	for i = 0, platformCount - 1 do
		local t = i / (platformCount - 1)
		local angle = startAngle + t * turns * math.pi * 2
		local y = yStart + 3 + t * yRise
		local pos = ringPos(center, r, angle, y)

		-- Shape variant cycles every platform so the spiral looks like hand-crafted
		-- carpentry rather than 16 identical planks. All variants share a ~1-stud
		-- vertical thickness so the top surface stays at pos.Y + 0.5 and jump
		-- physics remain predictable.
		local shapeVariant = i % 3
		local step
		if shapeVariant == 0 then
			-- Rectangular wooden plank tangent to the spiral path.
			step = newPart({
				Name = "SpiralStep_P1_" .. i,
				Size = Vector3.new(9, 1, 7),
				CFrame = CFrame.new(pos) * CFrame.Angles(0, angle + math.rad(90), 0),
				Material = Enum.Material.WoodPlanks,
				Color = Color3.fromRGB(120, 80, 50),
			})
		elseif shapeVariant == 1 then
			-- Round cross-cut tree-ring disc (looks like a sliced log).
			step = newPart({
				Name = "SpiralStep_P1_" .. i,
				Size = Vector3.new(1, 8.5, 8.5),
				Shape = Enum.PartType.Cylinder,
				CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Wood,
				Color = Color3.fromRGB(108, 76, 48),
			})
		else
			-- Hexagonal-feel wide slab, rotated ~25° off the spiral tangent so
			-- its corners jut forward/backward like a natural stump.
			step = newPart({
				Name = "SpiralStep_P1_" .. i,
				Size = Vector3.new(8, 1, 8),
				CFrame = CFrame.new(pos)
					* CFrame.Angles(0, angle + math.rad(90) + math.rad(25), 0),
				Material = Enum.Material.Wood,
				Color = Color3.fromRGB(115, 82, 52),
			})
		end
		step:SetAttribute("Phase", 1)

		-- Every 6th platform is a fading-leaf hazard (same position, different look).
		if i > 0 and i % 6 == 0 then
			step.Name = "SpiralLeaf_P1_" .. i
			step.Material = Enum.Material.Grass
			step.Color = Color3.fromRGB(70, 150, 55)
			step:SetAttribute("FadingLeaf", true)
		end
		-- Every 8th platform is a glowing checkpoint.
		if i > 0 and i % 8 == 0 then
			step.Material = Enum.Material.Neon
			step.Color = Color3.fromRGB(80, 200, 220)
			step:SetAttribute("IsCheckpoint", true)
		end

		step.Parent = folder

		-- Decorate only the "normal" planks so hazards (green leaves) and
		-- checkpoints (glowing neon) keep their distinct read-at-a-glance look.
		if not step:GetAttribute("FadingLeaf") and not step:GetAttribute("IsCheckpoint") then
			decorPhase1Plank(step, i, angle, folder)
		end

		-- Aligned coin on every other platform (odd indices avoid coins on hazards/checkpoints).
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
			coin:SetAttribute("Phase", 1)
			coin.Parent = coinsFolder
		end
	end
end

------------------------------------------------------------
-- Phase 2 — Canopy Perils
-- Spiral continuation from Phase 1's end angle. 16 platforms over 1.5 turns
-- at r=26 → chord ≈ 16.1 studs. Three pendulum logs sweep across the jump
-- arc at t = 0.25 / 0.5 / 0.75; four radial detour branches carry bonus
-- coins at t = 0.2 / 0.4 / 0.6 / 0.8. Main-path coins float above every
-- other spiral platform. Ends at a vine truss climbing to the Phase 3
-- knot entry.
------------------------------------------------------------
local function buildPhase2(parent: Instance)
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
			plat.Material = Enum.Material.Neon
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

		-- Aligned glowing coin above odd-indexed mushrooms.
		if coinsFolderMushroom and i % 2 == 1 then
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
			coin:SetAttribute("Phase", 3)
			coin.Parent = coinsFolderMushroom
		end
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
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(140, 220, 90),
			Transparency = 0.3,
			CanCollide = false,
		})
		beam:SetAttribute("SporeBeam", true)
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

		-- Aligned coin above every other ice step (skip first/last to avoid
		-- clipping through the speed pad / exit landing).
		if coinsFolder and i > 0 and i < count - 1 and i % 2 == 1 then
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
			coin:SetAttribute("Phase", 4)
			coin.Parent = coinsFolder
		end
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
-- Canopy foliage (decorative)
------------------------------------------------------------
local function buildCanopy(parent: Instance)
	for i = 1, 6 do
		local angle = (i / 6) * math.pi * 2
		local radius = 80
		local leaf = newPart({
			Name = "CanopyLeaf_" .. i,
			Size = Vector3.new(110, 80, 110),
			Position = Config.Map.TreeCenter + Vector3.new(
				math.cos(angle) * radius,
				Config.Map.TreeHeight + 40,
				math.sin(angle) * radius
			),
			Shape = Enum.PartType.Ball,
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(55, 115, 50),
			CanCollide = false,
		})
		leaf.Parent = parent
	end
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
	buildPracticeCliff(map)
	buildTrunk(map)
	buildTreeEntry(map)
	buildPhase1(map)
	buildPhase2(map)
	buildPhase3(map)
	buildPhase4(map)
	buildCanopy(map)
	buildAtmosphere(map)

	print("[MapBuilder] World built. Jump branch @ Y =", Config.Map.JumpBranchHeight)
	return map
end

return MapBuilder
