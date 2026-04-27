--!strict
-- LeaderboardService.lua
-- Uses an OrderedDataStore to track the "longest glide distance" leaderboard.
-- Serves top-N via Remotes.GetLeaderboard.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local LeaderboardService = {}

-- Lazy + safe. OrderedDataStore requires API access enabled or a published place.
local ods: OrderedDataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.Leaderboard.DataStoreName)
	end)
	if ok then
		ods = result
	else
		warn("[LeaderboardService] OrderedDataStore unavailable this session. Reason:", result)
	end
end

local cache: { entries: { { name: string, distance: number } }, lastRefresh: number } = {
	entries = {},
	lastRefresh = 0,
}

function LeaderboardService.submit(player: Player, distance: number)
	if distance <= 0 or not ods then return end
	task.spawn(function()
		local ok, err = pcall(function()
			-- Only update if it's higher than the stored value.
			local current = ods:GetAsync(tostring(player.UserId))
			if not current or distance > current then
				ods:SetAsync(tostring(player.UserId), distance)
			end
		end)
		if not ok then
			warn("[LeaderboardService] submit failed:", err)
		end
	end)
end

local function refresh()
	if not ods then return end
	local ok, pages = pcall(function()
		return ods:GetSortedAsync(false, Config.Leaderboard.TopN)
	end)
	if not ok then
		warn("[LeaderboardService] refresh failed:", pages)
		return
	end
	local page = pages:GetCurrentPage()
	local entries = {}
	for _, entry in ipairs(page) do
		local userId = tonumber(entry.key)
		local name = "?"
		if userId then
			local okName, result = pcall(function()
				return Players:GetNameFromUserIdAsync(userId)
			end)
			if okName then name = result end
		end
		table.insert(entries, { name = name, distance = entry.value })
	end
	cache.entries = entries
	cache.lastRefresh = os.clock()
end

function LeaderboardService.init()
	Remotes.GetLeaderboard.OnServerInvoke = function()
		if os.clock() - cache.lastRefresh > Config.Leaderboard.RefreshSeconds then
			refresh()
		end
		return cache.entries
	end

	task.spawn(function()
		while true do
			refresh()
			task.wait(Config.Leaderboard.RefreshSeconds)
		end
	end)
end

return LeaderboardService
