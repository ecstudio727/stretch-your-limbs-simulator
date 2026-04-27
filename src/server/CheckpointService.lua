--!strict
-- CheckpointService.lua
-- Binds every BasePart in workspace.Map tagged with IsCheckpoint=true so that
-- touching it becomes that player's new spawn point. On CharacterAdded the
-- player is teleported to their last checkpoint (if any). New joiners spawn
-- at the default SpawnPad as usual.
--
-- Per-player checkpoint state is kept in memory only — it naturally resets
-- when the player leaves. The tutorial still runs first for first-time
-- players; we never override the cliff placement that TutorialService does.

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared  = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local CheckpointService = {}

-- Last checkpoint part each player has touched. Cleared on leave.
local lastCheckpoint: { [Player]: BasePart } = {}

local function getPlayerFromHit(hit: BasePart): (Player?, Humanoid?)
	local char = hit.Parent
	if not char then return nil, nil end
	local humanoid = char:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then return nil, nil end
	local player = Players:GetPlayerFromCharacter(char)
	return player, humanoid
end

local function bindCheckpoint(part: BasePart)
	part.Touched:Connect(function(hit)
		local player, humanoid = getPlayerFromHit(hit)
		if not player or not humanoid or humanoid.Health <= 0 then return end
		-- Dedup: don't spam the player if they're walking all over the same checkpoint.
		if lastCheckpoint[player] == part then return end
		lastCheckpoint[player] = part
		if Remotes.Notify then
			Remotes.Notify:FireClient(player, "Checkpoint reached!")
		end
	end)
end

local function scanMap()
	local map = Workspace:WaitForChild("Map")
	for _, d in ipairs(map:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("IsCheckpoint") then
			bindCheckpoint(d)
		end
	end
	map.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") and d:GetAttribute("IsCheckpoint") then
			bindCheckpoint(d)
		end
	end)
end

local function respawnAtCheckpoint(player: Player, deps: any)
	local char = player.Character
	if not char then return end
	local hrp = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not hrp then return end

	-- Give TutorialService a beat to claim tutorial-stage players first.
	task.wait(0.5)

	-- Sanity checks — player might have left / respawned again.
	if not hrp.Parent then return end
	if player.Character ~= char then return end

	-- Respect tutorial: first-time players belong on the practice cliff.
	local profile = deps.PlayerDataService and deps.PlayerDataService.get(player)
	if profile and not profile.HasCompletedTutorial then return end

	local cp = lastCheckpoint[player]
	if not cp or not cp.Parent then return end

	-- Fixed vertical offset clears the tallest checkpoint shape we place
	-- (Phase 3 cylinder caps, half-height 4) with a small grace drop.
	hrp.CFrame = CFrame.new(cp.Position + Vector3.new(0, 5, 0))
end

function CheckpointService.init(deps: { PlayerDataService: any })
	scanMap()

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			respawnAtCheckpoint(player, deps)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastCheckpoint[player] = nil
	end)

	print("[CheckpointService] Ready.")
end

-- Public: let other services (e.g. Rebirth) clear a player's checkpoint
-- so they spawn at the base again.
function CheckpointService.reset(player: Player)
	lastCheckpoint[player] = nil
end

return CheckpointService
