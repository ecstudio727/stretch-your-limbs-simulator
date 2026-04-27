--!strict
-- Config/Map.lua
-- OWNER: OWEN (UI, visuals, map design).
--
-- Tunings that affect the SHAPE of the world. Tree dimensions, phase
-- height bands, cliff position, jump branch, coin payout per pickup.
-- Move geometry-related constants here when MapBuilder grows them.
--
-- Note: returns a plain data table. The merged `Config` (with helper
-- functions) is assembled in Config/init.lua.

local Map = {}

------------------------------------------------------------
-- MAP / TREE
-- Phased heights. Each phase is a contiguous section of the tree.
------------------------------------------------------------
Map.Map = {
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

return Map
