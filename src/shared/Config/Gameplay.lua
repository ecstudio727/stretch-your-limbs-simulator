--!strict
-- Config/Gameplay.lua
-- OWNER: PARTNER (gameplay, monetization, progression).
--
-- All tunings that affect how the game PLAYS — character speed, glide
-- physics, shop economy, rebirth curve, pets, leaderboards, tutorial flow,
-- and persistent data. Owen should not need to edit this file; map
-- dimensions live in Config/Map.lua, palette/typography in shared/UI.lua.
--
-- Note: returns a plain data table. The merged `Config` (with helper
-- functions like getGlideParams) is assembled in Config/init.lua.

local Gameplay = {}

------------------------------------------------------------
-- MOVEMENT (base character)
------------------------------------------------------------
Gameplay.Movement = {
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
Gameplay.Glide = {
	BaseForwardSpeed = 20,              -- was 14 — level-0 glide now actually glides
	BaseFallSpeed = 24,                 -- was 32 — lighter descent so wings feel like wings
	WingspanMultiplier = 1.13,          -- exponential forward-speed growth per level
	FallSpeedReductionPerLevel = 0.3,   -- small linear reduction on top
	MinFallSpeed = 4,                   -- floor so late levels don't literally hover
	CoinsPerStud = 0.5,
	MinDistanceToReward = 10,
}

------------------------------------------------------------
-- SHOP (wingspan upgrade is the core progression stat)
------------------------------------------------------------
Gameplay.Shop = {
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
		Base = Gameplay.Movement.BaseJumpPower,
	},
	WalkSpeed = {
		MaxLevel = 20,
		BaseCost = 15,
		Growth = 1.4,
		PerLevel = 1.5,
		Base = Gameplay.Movement.BaseWalkSpeed,
	},
}

------------------------------------------------------------
-- REBIRTH
------------------------------------------------------------
Gameplay.Rebirth = {
	BaseRequirement = 1000,
	Growth = 2.5,
	CoinMultiplierPerRebirth = 0.25,
	WipeOnRebirth = { "Coins", "Upgrades" },
}

------------------------------------------------------------
-- PETS
------------------------------------------------------------
Gameplay.Pets = {
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
Gameplay.Leaderboard = {
	DataStoreName = "GlideDistance_v1",
	TopN = 20,
	RefreshSeconds = 30,
}

------------------------------------------------------------
-- TUTORIAL
-- Short, spatial, forgiving. States are enforced server-side via FSM.
------------------------------------------------------------
Gameplay.Tutorial = {
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
Gameplay.Data = {
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

return Gameplay
