--!strict
-- Remotes.lua
-- Lazily creates and returns shared RemoteEvents / RemoteFunctions.
-- Lives in ReplicatedStorage.Shared so both client and server can require it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not RemotesFolder then
	RemotesFolder = Instance.new("Folder")
	RemotesFolder.Name = "Remotes"
	RemotesFolder.Parent = ReplicatedStorage
end

local function getOrCreate(name: string, className: string): Instance
	local existing = RemotesFolder:FindFirstChild(name)
	if existing then return existing end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = RemotesFolder
	return inst
end

local Remotes = {}

-- === Gameplay ===
Remotes.GlideStarted   = getOrCreate("GlideStarted",   "RemoteEvent")
Remotes.GlideEnded     = getOrCreate("GlideEnded",     "RemoteEvent")
Remotes.DataUpdated    = getOrCreate("DataUpdated",    "RemoteEvent")
Remotes.Notify         = getOrCreate("Notify",         "RemoteEvent")
Remotes.CoinPickup     = getOrCreate("CoinPickup",     "RemoteEvent")

-- === Shop / progression ===
Remotes.PurchaseUpgrade = getOrCreate("PurchaseUpgrade", "RemoteFunction")
Remotes.Rebirth         = getOrCreate("Rebirth",         "RemoteFunction")
Remotes.EquipPet        = getOrCreate("EquipPet",        "RemoteFunction")
Remotes.GetLeaderboard  = getOrCreate("GetLeaderboard",  "RemoteFunction")
Remotes.GetProfile      = getOrCreate("GetProfile",      "RemoteFunction")

-- === Tutorial ===
-- Server -> Client: change of tutorial state. Args: stateName (string), objectivePos (Vector3?)
Remotes.TutorialState   = getOrCreate("TutorialState",   "RemoteEvent")
-- Client -> Server: "I just finished step X" (server validates before advancing)
Remotes.TutorialReport  = getOrCreate("TutorialReport",  "RemoteEvent")
-- Client -> Server: user clicked Skip
Remotes.TutorialSkip    = getOrCreate("TutorialSkip",    "RemoteEvent")

return Remotes
