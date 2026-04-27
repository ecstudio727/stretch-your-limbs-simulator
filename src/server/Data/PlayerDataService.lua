--!strict
-- PlayerDataService.lua
-- Owns per-player profile state. Persists via DataStoreService.
-- Other services read/write through this module — do NOT touch profiles directly.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Util = require(Shared:WaitForChild("Util"))

-- Lazy + safe store access. DataStore can't be used in Studio unless
-- "Enable Studio Access to API Services" is on, OR the place is published.
-- We never want a missing DataStore to prevent the game from booting.
local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[PlayerDataService] DataStore unavailable - progress will NOT save this session. Reason:", result)
	end
end

local PlayerDataService = {}

local profiles: { [Player]: any } = {}

local function keyFor(player: Player): string
	return "u_" .. tostring(player.UserId)
end

local function mergeDefaults(profile: any): any
	-- Ensure all default fields exist (useful when Config.Data.Default changes).
	local defaults = Util.deepCopy(Config.Data.Default)
	for k, v in pairs(defaults) do
		if profile[k] == nil then
			profile[k] = v
		elseif type(v) == "table" and type(profile[k]) == "table" then
			for k2, v2 in pairs(v) do
				if profile[k][k2] == nil then
					profile[k][k2] = v2
				end
			end
		end
	end
	return profile
end

local function load(player: Player): any
	if not store then
		return Util.deepCopy(Config.Data.Default)
	end
	local ok, data = pcall(function()
		return store:GetAsync(keyFor(player))
	end)
	if ok and type(data) == "table" then
		return mergeDefaults(data)
	end
	if not ok then
		warn(("[PlayerDataService] load failed for %s: %s"):format(player.Name, tostring(data)))
	end
	return Util.deepCopy(Config.Data.Default)
end

local function save(player: Player)
	if not store then return end
	local profile = profiles[player]
	if not profile then return end
	local ok, err = pcall(function()
		store:SetAsync(keyFor(player), profile)
	end)
	if not ok then
		warn(("[PlayerDataService] save failed for %s: %s"):format(player.Name, tostring(err)))
	end
end

function PlayerDataService.get(player: Player): any?
	return profiles[player]
end

function PlayerDataService.replicate(player: Player)
	local profile = profiles[player]
	if not profile then return end
	Remotes.DataUpdated:FireClient(player, profile)
end

function PlayerDataService.update(player: Player, mutator: (any) -> ())
	local profile = profiles[player]
	if not profile then return end
	mutator(profile)
	PlayerDataService.replicate(player)
end

function PlayerDataService.addCoins(player: Player, amount: number)
	local profile = profiles[player]
	if not profile then return end
	-- Apply multipliers: rebirth + equipped pet.
	local multiplier = 1 + (profile.Rebirths or 0) * Config.Rebirth.CoinMultiplierPerRebirth
	local equipped = profile.EquippedPet
	if equipped and Config.Pets.Catalog[equipped] then
		multiplier = multiplier + Config.Pets.Catalog[equipped].CoinMultiplier
	end
	local final = math.floor(amount * multiplier)
	profile.Coins += final
	PlayerDataService.replicate(player)
	return final
end

local function applyCharacterUpgrades(player: Player)
	local profile = profiles[player]
	if not profile then return end
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then return end

	local jump = Config.Movement.BaseJumpPower
		+ (profile.Upgrades.JumpPower or 0) * Config.Shop.JumpPower.PerLevel
	local walk = Config.Movement.BaseWalkSpeed
		+ (profile.Upgrades.WalkSpeed or 0) * Config.Shop.WalkSpeed.PerLevel

	humanoid.JumpPower = jump
	humanoid.WalkSpeed = walk
	humanoid.UseJumpPower = true
end

PlayerDataService.applyCharacterUpgrades = applyCharacterUpgrades

local function onPlayerAdded(player: Player)
	profiles[player] = load(player)

	-- leaderstats folder for default Roblox leaderboard UI
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	ls.Parent = player

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = profiles[player].Coins
	coins.Parent = ls

	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = profiles[player].Rebirths
	rebirths.Parent = ls

	local bestGlide = Instance.new("IntValue")
	bestGlide.Name = "BestGlide"
	bestGlide.Value = profiles[player].BestGlideDistance
	bestGlide.Parent = ls

	-- Keep leaderstats in sync with profile.
	task.spawn(function()
		while player.Parent do
			local p = profiles[player]
			if p then
				coins.Value = p.Coins
				rebirths.Value = p.Rebirths
				bestGlide.Value = p.BestGlideDistance
			end
			task.wait(1)
		end
	end)

	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("Humanoid", 5)
		task.wait(0.1)
		applyCharacterUpgrades(player)
	end)

	-- initial replication
	task.defer(function()
		PlayerDataService.replicate(player)
	end)
end

local function onPlayerRemoving(player: Player)
	save(player)
	profiles[player] = nil
end

function PlayerDataService.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- auto-save loop
	task.spawn(function()
		while true do
			task.wait(Config.Data.AutoSaveSeconds)
			for player, _ in pairs(profiles) do
				save(player)
			end
		end
	end)

	-- save all on shutdown
	game:BindToClose(function()
		for player, _ in pairs(profiles) do
			save(player)
		end
	end)

	-- GetProfile remote
	Remotes.GetProfile.OnServerInvoke = function(player)
		return profiles[player]
	end
end

return PlayerDataService
