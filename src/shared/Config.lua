--!strict
-- Config.lua
-- Central tuning values for Stretch Your Limbs Simulator.
-- Tweak freely — no other module should hardcode these numbers.

local Config = {}

------------------------------------------------------------
-- MOVEMENT (base character)
------------------------------------------------------------
Config.Movement = {
	BaseWalkSpeed = 22,     -- was 16; snappier base movement
	BaseJumpPower = 65,     -- was 50; raised so the ~1.5x-wider platform gaps stay reachable at base stats
}

------------------------------------------------------------
-- GLIDE
-- Distance model: distance ≈ forwardSpeed * (startHeight / fallSpeed).
-- Slope = forwardSpeed / fallSpeed. ≥ 1 reads as a glide; < ~0.7 reads as a fall.
-- At level 0 slope is 20/24 ≈ 0.83 (shallow glide). At level 2 the Wingspan
-- multiplier pushes slope past 1.0 so each upgrade visibly matters.
-- Each Wingspan level multiplies forward speed by WingspanMultiplier,
-- AND subtracts FallSpeedReductionPerLevel (clamped to MinFallSpeed).
------------------------------------------------------------
Config.Glide = {
	BaseForwardSpeed = 20,              -- was 14 — level-0 glide now actually glides
	BaseFallSpeed = 24,                 -- was 32 — lighter descent so wings feel like wings
	WingspanMultiplier = 1.13,          -- exponential forward-speed growth per level
	FallSpeedReductionPerLevel = 0.3,   -- small linear reduction on top
	MinFallSpeed = 4,                   -- floor so late levels don't literally hover
	CoinsPerStud = 0.5,
	MinDistanceToReward = 10,
}

--- Returns (forwardSpeed, fallSpeed) for a given wingspan level.
function Config.getGlideParams(wingspanLevel: number): (number, number)
	local forward = Config.Glide.BaseForwardSpeed * (Config.Glide.WingspanMultiplier ^ wingspanLevel)
	local fall = math.max(
		Config.Glide.BaseFallSpeed - wingspanLevel * Config.Glide.FallSpeedReductionPerLevel,
		Config.Glide.MinFallSpeed
	)
	return forward, fall
end

------------------------------------------------------------
-- MAP / TREE
-- Phased heights. Each phase is a contiguous section of the tree.
------------------------------------------------------------
Config.Map = {
	TreeCenter = Vector3.new(0, 0, 0),
	TreeTrunkRadius = 22,
	TreeHeight = 340,

	-- Practice cliff (tutorial area). Placed off to the side of the tree.
	PracticeCliff = {
		Position = Vector3.new(160, 0, 0), -- 160 studs east of spawn
		Height = 45,
	},

	-- Phase height bands (Y coordinates).
	Phase1 = { YStart = 4,   YEnd = 80 },   -- Root Ascendance
	Phase2 = { YStart = 80,  YEnd = 160 },  -- Canopy Perils
	Phase3 = { YStart = 160, YEnd = 240 },  -- Rotting Core (interior)
	Phase4 = { YStart = 240, YEnd = 340 },  -- Apex Crown
	JumpBranchHeight = 340,
	JumpBranchLength = 90,

	-- Coin spawns per phase.
	CoinValue = 5,
}

------------------------------------------------------------
-- SHOP (wingspan upgrade is the core progression stat)
------------------------------------------------------------
Config.Shop = {
	Wingspan = {
		MaxLevel = 60,         -- more headroom since the curve is exponential
		BaseCost = 25,
		Growth = 1.35,
	},
	JumpPower = {
		MaxLevel = 20,
		BaseCost = 15,
		Growth = 1.4,
		PerLevel = 2,   -- gentler scaling; max lvl 20 gives +40 (90 total) under gravity 150
		Base = Config.Movement.BaseJumpPower,
	},
	WalkSpeed = {
		MaxLevel = 20,
		BaseCost = 15,
		Growth = 1.4,
		PerLevel = 1.5,
		Base = Config.Movement.BaseWalkSpeed,
	},
}

------------------------------------------------------------
-- REBIRTH
------------------------------------------------------------
Config.Rebirth = {
	BaseRequirement = 1000,
	Growth = 2.5,
	CoinMultiplierPerRebirth = 0.25,
	WipeOnRebirth = { "Coins", "Upgrades" },
}

------------------------------------------------------------
-- PETS
------------------------------------------------------------
Config.Pets = {
	StarterPet = { Id = "Leaf", Name = "Leaf Sprite", CoinMultiplier = 0.1 },
	Catalog = {
		Leaf     = { Id = "Leaf",     Name = "Leaf Sprite",  CoinMultiplier = 0.1 },
		Acorn    = { Id = "Acorn",    Name = "Acorn Buddy",  CoinMultiplier = 0.25 },
		Bluebird = { Id = "Bluebird", Name = "Bluebird",     CoinMultiplier = 0.5 },
	},
}

------------------------------------------------------------
-- LEADERBOARD
------------------------------------------------------------
Config.Leaderboard = {
	DataStoreName = "GlideDistance_v1",
	TopN = 20,
	RefreshSeconds = 30,
}

------------------------------------------------------------
-- TUTORIAL
-- Short, spatial, forgiving. States are enforced server-side via FSM.
------------------------------------------------------------
Config.Tutorial = {
	States = {
		"Step1_GrabCoin",     -- walk to the glowing coin on the cliff plateau
		"Step2_Glide",        -- step off the west edge, auto-glide to the tree
		"Done",
	},
	-- ForceField is applied during tutorial to prevent death-frustration.
	GrantStarterCoinsOnComplete = 10,
}

------------------------------------------------------------
-- DATA
------------------------------------------------------------
Config.Data = {
	DataStoreName = "PlayerData_v3", -- bump invalidates old saves so the rewritten tutorial always runs for testers
	AutoSaveSeconds = 120,
	Default = {
		Coins = 0,
		BestGlideDistance = 0,
		Rebirths = 0,
		Upgrades = {
			Wingspan = 0,
			JumpPower = 0,
			WalkSpeed = 0,
		},
		Pets = { "Leaf" },
		EquippedPet = "Leaf",
		HasCompletedTutorial = false,
	},
}

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------
function Config.getUpgradeCost(upgradeName: string, currentLevel: number): number
	local up = Config.Shop[upgradeName]
	if not up then return math.huge end
	if currentLevel >= up.MaxLevel then return math.huge end
	return math.floor(up.BaseCost * (up.Growth ^ currentLevel))
end

function Config.getRebirthRequirement(currentRebirths: number): number
	return math.floor(Config.Rebirth.BaseRequirement * (Config.Rebirth.Growth ^ currentRebirths))
end

return Config
