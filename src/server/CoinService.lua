--!strict
-- CoinService.lua
-- Wires up coin pickup parts (built by MapBuilder). Touch a coin -> award value,
-- destroy the coin, respawn it after a short delay so the obby stays populated.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local CoinService = {}

local RESPAWN_SECONDS = 20

local function bindCoin(coin: BasePart, playerDataService: any)
	local claimed = false
	coin.Touched:Connect(function(hit)
		if claimed then return end
		local char = hit.Parent
		if not char then return end
		local humanoid = char:FindFirstChildWhichIsA("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
		local player = Players:GetPlayerFromCharacter(char)
		if not player then return end

		claimed = true
		local value = coin:GetAttribute("Value") or 1
		local actual = playerDataService.addCoins(player, value)
		Remotes.CoinPickup:FireClient(player, coin.Position, actual or value)

		coin.Transparency = 1
		coin.CanCollide = false

		task.delay(RESPAWN_SECONDS, function()
			if coin.Parent then
				coin.Transparency = 0
				coin.CanCollide = false -- coins are always non-collide
				claimed = false
			end
		end)
	end)
end

function CoinService.init(deps: { PlayerDataService: any })
	local map = Workspace:WaitForChild("Map")
	local coinsFolder = map:WaitForChild("Coins")
	for _, coin in ipairs(coinsFolder:GetChildren()) do
		if coin:IsA("BasePart") then
			bindCoin(coin, deps.PlayerDataService)
		end
	end
	coinsFolder.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") then
			bindCoin(child, deps.PlayerDataService)
		end
	end)
end

return CoinService
