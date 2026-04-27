--!strict
-- PetService.lua
-- Skeleton pet system. For now: each player owns at least the starter pet.
-- Clients can equip any pet they own. Equipped pet boosts coin gains (applied in PlayerDataService.addCoins).
-- TODO: hatching, gacha egg system, pet 3D models following the player.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PetService = {}

function PetService.init(deps: { PlayerDataService: any })
	local PlayerDataService = deps.PlayerDataService

	Remotes.EquipPet.OnServerInvoke = function(player, petId)
		if type(petId) ~= "string" then return false, "Invalid pet" end
		local profile = PlayerDataService.get(player)
		if not profile then return false, "No profile" end

		-- Must own the pet.
		local owns = false
		for _, owned in ipairs(profile.Pets or {}) do
			if owned == petId then owns = true; break end
		end
		if not owns then return false, "You don't own this pet" end
		if not Config.Pets.Catalog[petId] then return false, "Unknown pet" end

		PlayerDataService.update(player, function(p)
			p.EquippedPet = petId
		end)
		return true, "Equipped"
	end
end

return PetService
