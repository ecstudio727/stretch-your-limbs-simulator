--!strict
-- Config/init.lua
-- OWNER: JOINT (touch with care — both Owen and Ruben read this).
--
-- This is the merged, public-facing Config table. Sub-modules:
--   * Gameplay.lua → RUBEN  (movement, glide, shop, rebirth, pets, data, tutorial, leaderboard)
--   * Map.lua      → OWEN     (tree dims, phase bands, coin value)
--
-- All callers continue to do `require(Shared.Config)` and read
-- `Config.Glide.X`, `Config.Map.X`, `Config.Shop.X`, etc. — the merge
-- below preserves the flat namespace the rest of the codebase expects.
--
-- Helper functions live here (not in sub-modules) so their bodies can
-- refer to the merged `Config` table unambiguously.

local Gameplay = require(script:WaitForChild("Gameplay"))
local MapMod   = require(script:WaitForChild("Map"))

local Config = {}

for k, v in pairs(Gameplay) do Config[k] = v end
for k, v in pairs(MapMod)   do Config[k] = v end

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------
--- Returns (forwardSpeed, fallSpeed) for a given wingspan level.
function Config.getGlideParams(wingspanLevel: number): (number, number)
	local forward = Config.Glide.BaseForwardSpeed * (Config.Glide.WingspanMultiplier ^ wingspanLevel)
	local fall = math.max(
		Config.Glide.BaseFallSpeed - wingspanLevel * Config.Glide.FallSpeedReductionPerLevel,
		Config.Glide.MinFallSpeed
	)
	return forward, fall
end

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
