--!strict
-- TutorialService.lua
-- Server-side FSM that guides a first-time player through a short practice run:
--   Step1_GrabCoin    -> walk to the coin on the cliff pedestal, touch it
--   Step2_Glide       -> walk off the west edge (TutorialLedgeEdge trigger)
--   Step2_Glide_InAir -> client auto-starts glide, we wait for landing
--   Done              -> teleport to the tree base, remove ForceField, persist flag
--
-- The tutorial happens on a physical cliff plateau to the east of the tree.
-- Stepping off the edge sends the player on a short auto-glide that deposits
-- them on a wide grass landing strip at the tree base. A ForceField is on the
-- whole time so the player can't die from falling.

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local TutorialService = {}

-- Per-player tutorial state: { state = string, forceField = ForceField? }
local playerStates: { [Player]: any } = {}

local function getMap(): Folder
	return Workspace:WaitForChild("Map") :: Folder
end

local function getObjectivePosition(state: string): Vector3?
	local map = getMap()
	local cliff = map:FindFirstChild("PracticeCliff")
	if not cliff then return nil end
	if state == "Step1_GrabCoin" then
		local coin = cliff:FindFirstChild("TutorialCoin")
		return coin and (coin :: BasePart).Position or nil
	elseif state == "Step2_Glide" then
		local ledge = cliff:FindFirstChild("TutorialLedge")
		return ledge and (ledge :: BasePart).Position or nil
	end
	return nil
end

local function pushState(player: Player, state: string)
	local info = playerStates[player]
	if not info then return end
	info.state = state
	Remotes.TutorialState:FireClient(player, state, getObjectivePosition(state))
end

local function applyForceField(player: Player)
	local char = player.Character
	if not char then return end
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("ForceField") then child:Destroy() end
	end
	local ff = Instance.new("ForceField")
	ff.Visible = false
	ff.Parent = char
	local info = playerStates[player]
	if info then info.forceField = ff end
end

local function removeForceField(player: Player)
	local info = playerStates[player]
	if info and info.forceField then
		info.forceField:Destroy()
		info.forceField = nil
	end
	local char = player.Character
	if char then
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("ForceField") then child:Destroy() end
		end
	end
end

-- Teleport the player onto the cliff plateau, facing westward toward the tree.
local function teleportToPracticeCliff(player: Player)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	local map = getMap()
	local cliff = map:FindFirstChild("PracticeCliff")
	if not cliff then return end
	local pedestal = cliff:FindFirstChild("TutorialPedestal") :: BasePart?
	if not pedestal then return end

	-- Spawn east of the pedestal, looking west toward the tree so the player
	-- naturally walks toward the coin, then the cliff edge.
	local spawnPos = pedestal.Position + Vector3.new(12, 4, 0)
	local look = Vector3.new(-1, 0, 0)
	hrp.CFrame = CFrame.lookAt(spawnPos, spawnPos + look)
end

local function teleportToTreeBase(player: Player)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	local map = getMap()
	local spawnPad = map:FindFirstChild("SpawnPad") :: BasePart?
	if spawnPad then
		hrp.CFrame = CFrame.new(spawnPad.Position + Vector3.new(0, 5, 0))
	end
end

local function finishTutorial(player: Player, deps: any)
	local info = playerStates[player]
	if not info then return end
	if info.state == "Done" then return end
	info.state = "Done"

	removeForceField(player)

	deps.PlayerDataService.update(player, function(p)
		p.HasCompletedTutorial = true
		p.Coins += Config.Tutorial.GrantStarterCoinsOnComplete
	end)

	Remotes.TutorialState:FireClient(player, "Done", nil)
	Remotes.Notify:FireClient(player, "Tutorial complete! +" .. Config.Tutorial.GrantStarterCoinsOnComplete .. " coins.")

	teleportToTreeBase(player)
end

------------------------------------------------------------
-- Hazard wiring for tutorial-specific parts
------------------------------------------------------------
local function wireTutorialParts(deps: any)
	local map = getMap()
	local cliff = map:WaitForChild("PracticeCliff")

	local coin = cliff:WaitForChild("TutorialCoin") :: BasePart
	coin.Touched:Connect(function(hit)
		local char = hit.Parent
		local humanoid = char and char:FindFirstChildWhichIsA("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
		local player = Players:GetPlayerFromCharacter(char)
		if not player then return end
		local info = playerStates[player]
		if not info or info.state ~= "Step1_GrabCoin" then return end

		-- Claim the coin visually for this tutorial player.
		coin.Transparency = 1
		task.delay(3, function()
			coin.Transparency = 0
		end)

		deps.PlayerDataService.addCoins(player, coin:GetAttribute("Value") or 5)
		pushState(player, "Step2_Glide")
		Remotes.Notify:FireClient(player, "Nice! Now walk off the cliff edge to glide to the tree.")
	end)

	local ledgeEdge = cliff:WaitForChild("TutorialLedgeEdge") :: BasePart
	ledgeEdge.Touched:Connect(function(hit)
		local char = hit.Parent
		local humanoid = char and char:FindFirstChildWhichIsA("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
		local player = Players:GetPlayerFromCharacter(char)
		if not player then return end
		local info = playerStates[player]
		if not info or info.state ~= "Step2_Glide" then return end

		-- Client reacts to the _InAir sub-state and calls _G.SYLS_StartGlide.
		pushState(player, "Step2_Glide_InAir")

		task.spawn(function()
			local landing = (getMap():FindFirstChild("PracticeCliff") :: Folder)
				:FindFirstChild("TutorialLandingPad") :: BasePart?
			if not landing then finishTutorial(player, deps); return end

			local done = false
			local conn
			conn = landing.Touched:Connect(function(h)
				if done then return end
				local c = h.Parent
				if c == player.Character then
					done = true
					if conn then conn:Disconnect() end
					finishTutorial(player, deps)
				end
			end)
			-- Safety fallback: finish after 10s even if the landing pad didn't fire.
			task.delay(10, function()
				if done then return end
				done = true
				if conn then conn:Disconnect() end
				finishTutorial(player, deps)
			end)
		end)
	end)
end

------------------------------------------------------------
-- Public
------------------------------------------------------------
function TutorialService.init(deps: { PlayerDataService: any })
	wireTutorialParts(deps)

	Remotes.TutorialSkip.OnServerEvent:Connect(function(player)
		local info = playerStates[player]
		if not info or info.state == "Done" then return end
		finishTutorial(player, deps)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(char)
			-- Wait a moment for profile to load.
			task.wait(0.3)
			local profile = deps.PlayerDataService.get(player)
			if not profile then return end
			if profile.HasCompletedTutorial then
				-- Returning player: no tutorial.
				playerStates[player] = { state = "Done" }
				Remotes.TutorialState:FireClient(player, "Done", nil)
				return
			end
			-- First-time player: begin tutorial on the cliff.
			playerStates[player] = { state = "Step1_GrabCoin" }
			applyForceField(player)
			teleportToPracticeCliff(player)
			pushState(player, "Step1_GrabCoin")
			Remotes.Notify:FireClient(player, "Welcome to Stretch Your Limbs Simulator! Grab the glowing coin on the pedestal to begin.")
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerStates[player] = nil
	end)

	print("[TutorialService] Ready.")
end

return TutorialService
