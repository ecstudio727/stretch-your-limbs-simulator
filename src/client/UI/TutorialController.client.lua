--!strict
-- TutorialController.client.lua
--
-- Floating-island tutorial UX. Entirely custom 3D arrow + screen prompt
-- (no more WedgePart / objective billboard from the old tutorial). Three
-- states sent by the server:
--
--   Greet  → 2-second welcome prompt centered on screen
--   Glide  → big "STEP OFF & PRESS F TO GLIDE" prompt, plus a 3D arrow
--            hovering above the launch edge of the floating island
--   Done   → all tutorial UI / arrow torn down
--
-- The 3D arrow is built from primitives (cone-tip cylinder + shaft
-- cylinder), so no external assets to fail to load. It bobs up-and-down
-- with a sine wave and gently spins so it reads as motion-attentive.

local Players   = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace  = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = require(Shared:WaitForChild("UI"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local currentState: string? = nil

------------------------------------------------------------
-- Single ScreenGui for tutorial chrome
------------------------------------------------------------
local screen = UI.newScreenGui("Tutorial", playerGui)

------------------------------------------------------------
-- Big centered prompt panel — the main "what to do" instruction.
-- Top-center, well above the player's character (which sits in the
-- lower-middle of the screen during normal play).
------------------------------------------------------------
local prompt = UI.newPanel("TutorialPrompt")
prompt.AnchorPoint = Vector2.new(0.5, 0)
prompt.Position = UDim2.new(0.5, 0, 0, UI.Size.Margin + 84)
prompt.Size = UDim2.new(0, 380, 0, 90)
prompt.BackgroundColor3 = Color3.fromRGB(20, 30, 45)
prompt.BackgroundTransparency = 0.05
prompt.Visible = false
prompt.Parent = screen

local promptStroke = prompt:FindFirstChildWhichIsA("UIStroke") :: UIStroke
promptStroke.Color = Color3.fromRGB(255, 215, 70)
promptStroke.Thickness = 3
promptStroke.Transparency = 0

UI.addPadding(prompt, 10)

local promptCaption = UI.newLabel("TUTORIAL", UI.TextSize.Micro, Color3.fromRGB(255, 215, 70))
promptCaption.Size = UDim2.new(1, 0, 0, 14)
promptCaption.TextXAlignment = Enum.TextXAlignment.Center
promptCaption.Parent = prompt

local promptTitle = UI.newLabel("", UI.TextSize.Heading, UI.Colors.TextPrimary)
promptTitle.Size = UDim2.new(1, 0, 0, 28)
promptTitle.Position = UDim2.new(0, 0, 0, 16)
promptTitle.TextXAlignment = Enum.TextXAlignment.Center
promptTitle.Font = UI.Font.Black
promptTitle.Parent = prompt

local promptHint = UI.newLabel("", UI.TextSize.Body, UI.Colors.TextMuted)
promptHint.Size = UDim2.new(1, 0, 0, 24)
promptHint.Position = UDim2.new(0, 0, 0, 46)
promptHint.TextXAlignment = Enum.TextXAlignment.Center
promptHint.Parent = prompt

------------------------------------------------------------
-- Skip button — middle-LEFT Yellow Zone, dim, deliberate reach to
-- avoid mis-tap during high-action moments.
------------------------------------------------------------
local skipOuter, skipInner = UI.newButton({
	Text = "",
	Color = UI.Colors.SurfaceSoft,
	Visual = Vector2.new(44, 44),
	Hitbox = Vector2.new(56, 56),
})
local skipIcon = UI.newIcon("Skip", 22, "SKIP")
skipIcon.AnchorPoint = Vector2.new(0.5, 0.5)
skipIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
skipIcon.Parent = skipInner

skipOuter.AnchorPoint = Vector2.new(0, 0.5)
skipOuter.Position = UDim2.new(0, UI.Size.Margin, 0.5, 0)
skipOuter.Visible = false
skipOuter.Parent = screen
skipOuter.Activated:Connect(function()
	Remotes.TutorialSkip:FireServer()
end)
skipInner.BackgroundTransparency = 0.2

------------------------------------------------------------
-- 3D arrow — built from primitives so no asset dependency. A vertical
-- yellow cylinder shaft topped with a wider, shorter cylinder tip
-- pointing downward at whatever target the arrow is "anchored" to.
-- Bobs up-and-down + spins gently around its Y axis.
------------------------------------------------------------
local arrowModel: Model? = nil
local arrowTargetPos: Vector3? = nil
local arrowConn: RBXScriptConnection? = nil

local function buildArrow(): Model
	local model = Instance.new("Model")
	model.Name = "TutorialArrow"

	-- Shaft: thick neon-yellow cylinder.
	local shaft = Instance.new("Part")
	shaft.Name = "Shaft"
	shaft.Anchored = true
	shaft.CanCollide = false
	shaft.CanQuery = false
	shaft.CanTouch = false
	shaft.CastShadow = false
	shaft.Shape = Enum.PartType.Cylinder
	shaft.Material = Enum.Material.Neon
	shaft.Color = Color3.fromRGB(255, 220, 60)
	shaft.Size = Vector3.new(7, 2.4, 2.4)  -- 7 long, 2.4 diameter
	shaft.Parent = model

	-- Tip: stubby fat cone-ish cylinder pointing down.
	local tip = Instance.new("Part")
	tip.Name = "Tip"
	tip.Anchored = true
	tip.CanCollide = false
	tip.CanQuery = false
	tip.CanTouch = false
	tip.CastShadow = false
	tip.Shape = Enum.PartType.Cylinder
	tip.Material = Enum.Material.Neon
	tip.Color = Color3.fromRGB(255, 180, 30)
	tip.Size = Vector3.new(3, 5, 5)
	tip.Parent = model

	-- Glow PointLight at the tip so it pops at distance.
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 90)
	light.Range = 18
	light.Brightness = 1.4
	light.Parent = tip

	model.PrimaryPart = shaft
	return model
end

-- Re-anchors the arrow group above `targetPos`, tip aimed downward at
-- the target. `t` is the elapsed time used for the bob+spin.
local function updateArrow(model: Model, targetPos: Vector3, t: number)
	local shaft = model:FindFirstChild("Shaft") :: BasePart?
	local tip = model:FindFirstChild("Tip") :: BasePart?
	if not shaft or not tip then return end

	-- Bob 1.5 studs up/down on a 1.6s sine wave.
	local bobOffset = math.sin(t * (math.pi * 2 / 1.6)) * 1.5
	-- Anchor the arrow so the tip's bottom edge sits ~6 studs above the
	-- target; the shaft sits above the tip with a tiny gap.
	local tipCenter = targetPos + Vector3.new(0, 9 + bobOffset, 0)
	local shaftCenter = tipCenter + Vector3.new(0, 5.5, 0)  -- 2.5 (half tip) + 0.5 + 3.5 (half shaft)

	-- Tip rotated so its long axis (+X local) points DOWN.
	tip.CFrame = CFrame.new(tipCenter) * CFrame.Angles(0, 0, math.rad(90))
	-- Shaft is vertical, also rotated so +X is up.
	shaft.CFrame = CFrame.new(shaftCenter) * CFrame.Angles(0, 0, math.rad(90))
end

local function destroyArrow()
	if arrowConn then arrowConn:Disconnect(); arrowConn = nil end
	if arrowModel then arrowModel:Destroy(); arrowModel = nil end
	arrowTargetPos = nil
end

local function spawnArrowAtLaunchEdge()
	destroyArrow()
	-- Find the launch-edge target in world space.
	local map = Workspace:FindFirstChild("Map")
	if not map then return end
	local island = map:FindFirstChild("TutorialIsland")
	if not island then return end
	local launchEdge = island:FindFirstChild("LaunchEdge") :: BasePart?
	if not launchEdge then return end

	arrowTargetPos = launchEdge.Position
	arrowModel = buildArrow()
	arrowModel.Parent = Workspace

	local startTime = os.clock()
	arrowConn = RunService.RenderStepped:Connect(function()
		if arrowModel and arrowTargetPos then
			updateArrow(arrowModel, arrowTargetPos, os.clock() - startTime)
		end
	end)
end

------------------------------------------------------------
-- Prompt copy per state
------------------------------------------------------------
local function setPromptForState(state: string)
	if state == "Greet" then
		promptCaption.Text = "WELCOME"
		promptTitle.Text = "Stretch Your Limbs!"
		promptHint.Text = "You're on a floating island. Glide to reach the tree!"
		prompt.Visible = true
		skipOuter.Visible = true
	elseif state == "Glide" then
		promptCaption.Text = "STEP 1 / 1"
		promptTitle.Text = "Step off & press F"
		promptHint.Text = (UI.isTouch() and "Walk off the edge → tap GLIDE!" or "Walk off the edge → press F to glide!")
		prompt.Visible = true
		skipOuter.Visible = true
	elseif state == "Done" then
		prompt.Visible = false
		skipOuter.Visible = false
		destroyArrow()
	end
end

------------------------------------------------------------
-- Server → client state transitions
------------------------------------------------------------
Remotes.TutorialState.OnClientEvent:Connect(function(state: string)
	currentState = state
	setPromptForState(state)

	if state == "Greet" then
		-- Don't spawn the arrow yet — let the welcome breathe.
		destroyArrow()
	elseif state == "Glide" then
		-- Now show the arrow at the launch edge.
		spawnArrowAtLaunchEdge()
	elseif state == "Done" then
		destroyArrow()
	end
end)

-- Re-apply the arrow / prompt if the player respawns mid-tutorial.
player.CharacterAdded:Connect(function()
	if currentState and currentState ~= "Done" then
		task.wait(0.4)
		setPromptForState(currentState)
		if currentState == "Glide" then
			spawnArrowAtLaunchEdge()
		end
	end
end)

print("[TutorialController] Floating-island tutorial UI ready.")
