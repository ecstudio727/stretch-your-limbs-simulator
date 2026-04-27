--!strict
-- ShopService.lua
-- Handles upgrade purchases. Client invokes Remotes.PurchaseUpgrade(upgradeName).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ShopService = {}

function ShopService.init(deps: { PlayerDataService: any })
	local PlayerDataService = deps.PlayerDataService

	Remotes.PurchaseUpgrade.OnServerInvoke = function(player, upgradeName)
		if type(upgradeName) ~= "string" then
			return false, "Invalid upgrade"
		end
		local def = Config.Shop[upgradeName]
		if not def then
			return false, "Unknown upgrade"
		end

		local profile = PlayerDataService.get(player)
		if not profile then return false, "No profile" end

		local currentLevel = profile.Upgrades[upgradeName] or 0
		if currentLevel >= def.MaxLevel then
			return false, "Max level"
		end

		local cost = Config.getUpgradeCost(upgradeName, currentLevel)
		if profile.Coins < cost then
			return false, ("Need %d coins"):format(cost)
		end

		PlayerDataService.update(player, function(p)
			p.Coins -= cost
			p.Upgrades[upgradeName] = currentLevel + 1
		end)

		-- WalkSpeed/JumpPower apply to live character; wingspan affects glide math only.
		if upgradeName == "WalkSpeed" or upgradeName == "JumpPower" then
			PlayerDataService.applyCharacterUpgrades(player)
		end

		Remotes.Notify:FireClient(player, ("%s -> lvl %d"):format(upgradeName, currentLevel + 1))
		return true, "OK"
	end
end

return ShopService
