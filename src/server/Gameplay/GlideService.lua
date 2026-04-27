--!strict
-- GlideService.lua
-- Tracks where a player started gliding (when they fire GlideStarted from the jump tip),
-- validates the end position, and awards coins based on horizontal distance.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Util = require(Shared:WaitForChild("Util"))

local GlideService = {}

local activeGlides: { [Player]: { startPos: Vector3, startTime: number } } = {}

local LeaderboardService -- late-bound via init() to avoid circular require

function GlideService.init(deps: { LeaderboardService: any, PlayerDataService: any })
	LeaderboardService = deps.LeaderboardService
	local PlayerDataService = deps.PlayerDataService

	Remotes.GlideStarted.OnServerEvent:Connect(function(player)
		local char = player.Character
		if not char then return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		-- Glides from ANY height are tracked. The leaderboard naturally rewards
		-- gliding from higher up (more fall-time = more distance), and the
		-- elapsed-time sanity check at GlideEnded still blocks teleport cheats.
		-- No height gate here — players stuck mid-climb should still score off
		-- any ledge they jump from.
		activeGlides[player] = {
			startPos = hrp.Position,
			startTime = os.clock(),
		}
	end)

	Remotes.GlideEnded.OnServerEvent:Connect(function(player)
		local info = activeGlides[player]
		if not info then return end
		activeGlides[player] = nil

		local char = player.Character
		if not char then return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local distance = Util.horizontalDistance(info.startPos, hrp.Position)
		if distance < Config.Glide.MinDistanceToReward then return end

		-- Anti-cheat sanity: a reasonable max glide is bounded by fall time * max forward speed.
		-- (Rough cap — we don't want to be strict here, just block absurd values.)
		local elapsed = os.clock() - info.startTime
		local maxReasonable = elapsed * 200 + 200
		if distance > maxReasonable then
			warn(("[GlideService] suspicious glide from %s: %d studs in %.1fs"):format(player.Name, distance, elapsed))
			return
		end

		-- Award coins.
		local coinsEarned = math.floor(distance * Config.Glide.CoinsPerStud)
		if coinsEarned > 0 then
			local actual = PlayerDataService.addCoins(player, coinsEarned)
			Remotes.Notify:FireClient(player, ("+%d coins (%d stud glide)"):format(actual or coinsEarned, math.floor(distance)))
		end

		-- Update best-glide record.
		local profile = PlayerDataService.get(player)
		if profile and distance > (profile.BestGlideDistance or 0) then
			PlayerDataService.update(player, function(p)
				p.BestGlideDistance = math.floor(distance)
			end)
			Remotes.Notify:FireClient(player, ("NEW RECORD: %d studs!"):format(math.floor(distance)))
		end

		-- Post to leaderboard.
		if LeaderboardService then
			LeaderboardService.submit(player, math.floor(distance))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		activeGlides[player] = nil
	end)
end

return GlideService
