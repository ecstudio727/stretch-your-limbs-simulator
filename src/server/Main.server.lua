--!strict
-- Main.server.lua
-- Entry point. Builds the map first so it always appears, then wires services.

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService:WaitForChild("Server")

require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Remotes"))

print("[Main] Booting Stretch Your Limbs Simulator...")

-- Build the map FIRST so it appears even if any service fails later.
local MapBuilder = require(Server:WaitForChild("MapBuilder"))
MapBuilder.build()

local function safeRequire(name: string)
	local ok, result = pcall(require, Server:WaitForChild(name))
	if ok then return result end
	warn(("[Main] failed to load %s: %s"):format(name, tostring(result)))
	return nil
end

local PlayerDataService  = safeRequire("PlayerDataService")
local GlideService       = safeRequire("GlideService")
local CoinService        = safeRequire("CoinService")
local ShopService        = safeRequire("ShopService")
local RebirthService     = safeRequire("RebirthService")
local PetService         = safeRequire("PetService")
local LeaderboardService = safeRequire("LeaderboardService")
local HazardService      = safeRequire("HazardService")
local CheckpointService  = safeRequire("CheckpointService")
local TutorialService    = safeRequire("TutorialService")

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
