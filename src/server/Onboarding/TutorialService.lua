--!strict
-- TutorialService.lua
--
-- Floating-island tutorial. First-join players spawn on a sky island east
-- of the tree, see a quick prompt, and reach the main island however they
-- want — glide, fall, die-and-respawn — all paths complete the tutorial.
--
-- Owen's call: NO BOUNDARIES. No ForceField, no fall-recovery teleport,
-- no strict "must have glided" check on landing. The tutorial just gates
-- the HasCompletedTutorial flag + starter-coin grant; it doesn't try to
-- trap or restrict the player.
--
-- FSM states (server-authoritative):
--   Greet  → 2-second welcome banner on the floating island
--   Glide  → "step off & press F" prompt + 3D arrow at launch edge
--   Done   → any touch of MainIslandLanding completes; +10 starter coins
--
-- If the player falls into the void instead of gliding, FallenPartsDestroyHeight
-- kills them and they respawn at the main SpawnLocation — which is on top
-- of the main island, so MainIslandLanding's touch sensor naturally fires
-- on respawn and the tutorial completes anyway. No special handling needed.

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local TutorialService = {}

-- Per-player tutorial state.
type StateInfo = {
	state: string,
	forceField: ForceField?,
	finished: boolean,
}
local playerStates: { [Player]: StateInfo } = {}

local function getMap(): Folder
	return Workspace:WaitForChild("Map") :: Folder
end

local function getIslandTopPart(): BasePart?
	local map = getMap()
	local island = map:FindFirstChild("TutorialIsland")
	return island and (island :: Folder):FindFirstChild("IslandTop") :: BasePart?
end

local function pushState(player: Player, state: string)
	local info = playerStates[player]
	if not info or info.finished then return end
	info.state = state
	Remotes.TutorialState:FireClient(player, state, nil)
end

-- ForceField helpers retained but unused — Owen wants no boundaries
-- during tutorial, including no invincibility. Calls to applyForceField
-- have been removed below. Functions kept as no-ops so we don't have to
-- audit every reference if we ever want them back.
local function applyForceField(_player: Player)
	-- intentionally no-op: tutorial has no ForceField protection.
end

local function removeForceField(player: Player)
	-- Defensive: still strip any ForceField attached to the character,
	-- in case one was left over from a previous codepath.
	local char = player.Character
	if not char then return end
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("ForceField") then child:Destroy() end
	end
end

-- Place the player on top of the floating island, facing west toward
-- the main world (so walking forward steps off the launch edge).
local function teleportToIsland(player: Player)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end

	local islandTop = getIslandTopPart()
	if not islandTop then return end

	-- Stand on the island's eastern half so they have room to walk west.
	local spawnPos = islandTop.Position + Vector3.new(8, 4, 0)
	local lookTarget = spawnPos + Vector3.new(-1, 0, 0)  -- face west
	hrp.CFrame = CFrame.lookAt(spawnPos, lookTarget)
end

-- After tutorial completes, drop the player at the regular spawn pad.
local function teleportToSpawn(player: Player)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	local spawnPad = getMap():FindFirstChild("SpawnPad") :: BasePart?
	if spawnPad then
		hrp.CFrame = CFrame.new(spawnPad.Position + Vector3.new(0, 5, 0))
	end
end

local function finishTutorial(player: Player, deps: any)
	local info = playerStates[player]
	if not info or info.finished then return end
	info.finished = true
	info.state = "Done"

	removeForceField(player)

	deps.PlayerDataService.update(player, function(p)
		p.HasCompletedTutorial = true
		p.Coins = (p.Coins or 0) + Config.Tutorial.GrantStarterCoinsOnComplete
	end)

	Remotes.TutorialState:FireClient(player, "Done", nil)
	Remotes.Notify:FireClient(player, "Tutorial complete! +" .. Config.Tutorial.GrantStarterCoinsOnComplete .. " coins.")

	teleportToSpawn(player)
end

------------------------------------------------------------
-- Wire the in-world tutorial parts (MainIslandLanding touch sensor and
-- the GlideStarted remote) once at init time.
------------------------------------------------------------
local function wireTutorialParts(deps: any)
	local map = getMap()
	local island = map:WaitForChild("TutorialIsland") :: Folder
	local landing = island:WaitForChild("MainIslandLanding") :: BasePart

	-- Glide started by a tutorial player → mark them as having reached
	-- the Glide phase (so the landing-zone touch counts as success).
	Remotes.GlideStarted.OnServerEvent:Connect(function(player)
		local info = playerStates[player]
		if not info or info.finished then return end
		if info.state == "Greet" or info.state == "Glide" then
			pushState(player, "Glide")
		end
	end)

	-- Player's character touches the main island landing zone → tutorial
	-- complete. NO state guard (Owen's "no boundaries" rule): any
	-- contact with MainIslandLanding while mid-tutorial finishes it,
	-- whether they glided, fell, or respawned onto the main island.
	landing.Touched:Connect(function(hit)
		local char = hit.Parent
		if not char then return end
		local player = Players:GetPlayerFromCharacter(char)
		if not player then return end
		local info = playerStates[player]
		if not info or info.finished then return end
		finishTutorial(player, deps)
	end)
end

-- (Fall-recovery loop removed — Owen's "no boundaries" rule. Players
-- who fall off the tutorial island just respawn at the main spawn pad
-- via FallenPartsDestroyHeight, where MainIslandLanding's touch sensor
-- finishes the tutorial naturally on the next frame.)

------------------------------------------------------------
-- Public
------------------------------------------------------------
function TutorialService.init(deps: { PlayerDataService: any })
	wireTutorialParts(deps)

	-- Skip button → fast-finish. Honored from any state.
	Remotes.TutorialSkip.OnServerEvent:Connect(function(player)
		local info = playerStates[player]
		if not info or info.finished then return end
		finishTutorial(player, deps)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(char)
			task.wait(0.3)
			local profile = deps.PlayerDataService.get(player)
			if not profile then return end

			if profile.HasCompletedTutorial then
				playerStates[player] = { state = "Done", finished = true }
				Remotes.TutorialState:FireClient(player, "Done", nil)
				return
			end

			playerStates[player] = { state = "Greet", finished = false }
			-- No ForceField. No safety net. Player is free to die / fall /
			-- explore however they want.
			teleportToIsland(player)
			pushState(player, "Greet")

			task.delay(Config.Tutorial.GreetDuration, function()
				local info = playerStates[player]
				if not info or info.finished then return end
				if info.state == "Greet" then
					pushState(player, "Glide")
				end
			end)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerStates[player] = nil
	end)

	print("[TutorialService] Floating-island tutorial ready.")
end

return TutorialService
