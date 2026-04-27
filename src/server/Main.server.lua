--!strict
-- Main.server.lua
-- OWNER: PARTNER (boot order, service wiring).
--
-- Entry point. Builds the map first so it always appears, then wires
-- services. Each service is loaded with safeRequire so a single bad
-- module never blocks boot.
--
-- Folder layout (under ServerScriptService.Server):
--   Map/          OWEN    — MapBuilder
--   Data/         PARTNER — PlayerDataService
--   Progression/  PARTNER — Shop, Rebirth, Pet, Leaderboard
--   Gameplay/     PARTNER — Glide, Coin, Hazard, Checkpoint
--   Onboarding/   PARTNER — Tutorial
--   Monetization/ PARTNER — (empty: game-passes / dev products go here)

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService:WaitForChild("Server")

require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Remotes"))

print("[Main] Booting Stretch Your Limbs Simulator...")

------------------------------------------------------------
-- Map first so the world appears even if a service fails later.
------------------------------------------------------------
local MapFolder = Server:WaitForChild("Map")
local MapBuilder = require(MapFolder:WaitForChild("MapBuilder"))
MapBuilder.build()

------------------------------------------------------------
-- safeRequire(folderName, moduleName) — never throws.
------------------------------------------------------------
local function safeRequire(folderName: string, moduleName: string)
	local folder = Server:FindFirstChild(folderName)
	if not folder then
		warn(("[Main] folder %s missing"):format(folderName))
		return nil
	end
	local module = folder:FindFirstChild(moduleName)
	if not module then
		warn(("[Main] module %s/%s missing"):format(folderName, moduleName))
		return nil
	end
	local ok, result = pcall(require, module)
	if ok then return result end
	warn(("[Main] failed to load %s/%s: %s"):format(folderName, moduleName, tostring(result)))
	return nil
end

local PlayerDataService  = safeRequire("Data",        "PlayerDataService")
local GlideService       = safeRequire("Gameplay",    "GlideService")
local CoinService        = safeRequire("Gameplay",    "CoinService")
local HazardService      = safeRequire("Gameplay",    "HazardService")
local CheckpointService  = safeRequire("Gameplay",    "CheckpointService")
local ShopService        = safeRequire("Progression", "ShopService")
local RebirthService     = safeRequire("Progression", "RebirthService")
local PetService         = safeRequire("Progression", "PetService")
local LeaderboardService = safeRequire("Progression", "LeaderboardService")
local TutorialService    = safeRequire("Onboarding",  "TutorialService")

------------------------------------------------------------
-- Init wiring. Each call is wrapped so one failure doesn't cascade.
------------------------------------------------------------
local function safeCall(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then warn(("[Main] %s init failed: %s"):format(label, tostring(err))) end
end

if PlayerDataService  then safeCall("PlayerData",  function() PlayerDataService.init() end) end
if LeaderboardService then safeCall("Leaderboard", function() LeaderboardService.init() end) end
if HazardService      then safeCall("Hazard",      function() HazardService.init() end) end
if GlideService and PlayerDataService then
	safeCall("Glide", function()
		GlideService.init({ LeaderboardService = LeaderboardService, PlayerDataService = PlayerDataService })
	end)
end
if CoinService     and PlayerDataService then safeCall("Coin",     function() CoinService.init({ PlayerDataService = PlayerDataService }) end) end
if ShopService     and PlayerDataService then safeCall("Shop",     function() ShopService.init({ PlayerDataService = PlayerDataService }) end) end
if RebirthService  and PlayerDataService then safeCall("Rebirth",  function() RebirthService.init({ PlayerDataService = PlayerDataService }) end) end
if PetService      and PlayerDataService then safeCall("Pet",      function() PetService.init({ PlayerDataService = PlayerDataService }) end) end
if CheckpointService and PlayerDataService then safeCall("Checkpoint", function() CheckpointService.init({ PlayerDataService = PlayerDataService }) end) end
if TutorialService and PlayerDataService then safeCall("Tutorial", function() TutorialService.init({ PlayerDataService = PlayerDataService }) end) end

print("[Main] Ready.")
