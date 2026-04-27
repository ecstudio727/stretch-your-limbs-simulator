--!strict
-- RebirthService.lua
-- Wipes coins + upgrades, increments rebirth count, applies permanent coin multiplier.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local RebirthService = {}

function RebirthService.init(deps: { PlayerDataService: any })
	local PlayerDataService = deps.PlayerDataService

	Remotes.Rebirth.OnServerInvoke = function(player)
		local profile = PlayerDataService.get(player)
		if not profile then return false, "No profile" end

		local required = Config.getRebirthRequirement(profile.Rebirths or 0)
		if profile.Coins < required then
			return false, ("Need %d coins"):format(required)
		end

		PlayerDataService.update(player, function(p)
			p.Rebirths = (p.Rebirths or 0) + 1
			p.Coins = 0
			p.Upgrades = {
				Wingspan = 0,
				JumpPower = 0,
				WalkSpeed = 0,
			}
		end)

		PlayerDataService.applyCharacterUpgrades(player)
		Remotes.Notify:FireClient(player, ("REBIRTH %d! +%d%% coins forever."):format(
			profile.Rebirths,
			math.floor(Config.Rebirth.CoinMultiplierPerRebirth * 100)
		))
		return true, "OK"
	end
end

return RebirthService
