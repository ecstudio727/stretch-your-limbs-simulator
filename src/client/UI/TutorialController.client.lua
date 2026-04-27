--!strict
-- TutorialController.client.lua
-- Client-side tutorial UX:
--   * A 3D floating arrow above the player pointing at the current objective.
--   * Highlight + BillboardGui on the current objective.
--   * An objective callout banner near the top of the screen.
--   * A Skip button in the top-right (Red Zone — passive, requires
--     deliberate reach, so it can't be hit mid-jump).
--   * When tutorial enters Step2_Glide_InAir, force-start glide via
--     _G.SYLS_StartGlide.
--
-- UI rationale: the skip button explicitly does NOT sit in any Green Zone.
-- Placing a destructive / commit-style action next to the jump input causes
-- accidental taps during high-frustration moments (the exact pattern the
-- doc warns about for Skip Stage buttons — misclick = broken trust).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = require(Shared:WaitForChild("UI"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local currentState: string? = nil
local currentObjective: Vector3? = nil

------------------------------------------------------------
-- Single ScreenGui for all tutorial chrome (so the engine can batch
-- the static elements together).
------------------------------------------------------------
local screen = UI.newScreenGui("Tutorial", playerGui)

------------------------------------------------------------
-- Objective banner (top-center, below the HUD stats strip).
-- Passive info — Red Zone. Compact for phones.
------------------------------------------------------------
local banner = UI.newPanel("ObjectiveBanner")
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, UI.Size.Margin + 46)
banner.Size = UDim2.new(0, 260, 0, 40)
banner.BackgroundColor3 = UI.Colors.Surface
banner.BackgroundTransparency = 0.15
banner.Visible = false
banner.Parent = screen

-- Accent stroke colour swapped to tutorial gold.
local bannerStroke = banner:FindFirstChildWhichIsA("UIStroke") :: UIStroke
bannerStroke.Color = UI.Colors.Coin
bannerStroke.Transparency = 0.2
bannerStroke.Thickness = 1

UI.addPadding(banner, 6)

local bannerCaption = UI.newLabel("TUTORIAL", UI.TextSize.Micro, UI.Colors.Coin)
bannerCaption.Size = UDim2.new(1, 0, 0, 12)
bannerCaption.TextXAlignment = Enum.TextXAlignment.Center
bannerCaption.Parent = banner

local bannerObjective = UI.newLabel("", UI.TextSize.Body, UI.Colors.TextPrimary)
bannerObjective.Size = UDim2.new(1, 0, 1, -14)
bannerObjective.Position = UDim2.new(0, 0, 0, 14)
bannerObjective.TextXAlignment = Enum.TextXAlignment.Center
bannerObjective.Font = UI.Font.Black
bannerObjective.Parent = banner

------------------------------------------------------------
-- Skip button — middle-LEFT Yellow Zone (mid-screen vertical periphery).
-- Per the heatmap doc, Skip-Stage-style commit actions belong in the
-- middle-right OR middle-left Yellow Zone, explicitly NOT in any Green
-- Zone and NOT in the bottom thumb cluster — that placement causes
-- accidental taps during frustrated rapid jumping ("Accidental
-- Monetization"). We put it on the LEFT so it doesn't collide with the
-- Shop rail (which sits in the middle-RIGHT Yellow Zone).
-- Visual 96x36, hitbox 120x48 (Fitts's Law), slightly dimmed so it
-- doesn't compete with the objective banner.
------------------------------------------------------------
-- Icon-only square button (44×44 visual, padded hitbox). The icon key
-- falls back to the "SKIP" word if the asset ID is ever missing from
-- Icons.lua, so the button stays meaningful no matter what.
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
-- 3D floating arrow — a glowing wedge that hovers above the player
-- and points toward the current objective.
------------------------------------------------------------
local pointer = Instance.new("WedgePart")
pointer.Name = "ArrowTip"
pointer.Anchored = true
pointer.CanCollide = false
pointer.CanQuery = false
pointer.CanTouch = false
pointer.CastShadow = false
pointer.Size = Vector3.new(4, 3, 5)
pointer.Material = Enum.Material.Neon
pointer.Color = Color3.fromRGB(255, 220, 60)
pointer.Transparency = 0.1

------------------------------------------------------------
-- Highlight + billboard on the current objective
------------------------------------------------------------
local currentObjectiveHighlight: Highlight? = nil
local currentObjectiveBillboard: BillboardGui? = nil

local function clearObjectiveMarkers()
	if currentObjectiveHighlight then
		currentObjectiveHighlight:Destroy()
		currentObjectiveHighlight = nil
	end
	if currentObjectiveBillboard then
		currentObjectiveBillboard:Destroy()
		currentObjectiveBillboard = nil
	end
end

local function findObjectivePart(state: string): BasePart?
	local map = Workspace:FindFirstChild("Map")
	if not map then return nil end
	local cliff = map:FindFirstChild("PracticeCliff")
	if not cliff then return nil end
	if state == "Step1_GrabCoin" then
		return cliff:FindFirstChild("TutorialCoin") :: BasePart?
	elseif state == "Step2_Glide" then
		return cliff:FindFirstChild("TutorialLedge") :: BasePart?
	end
	return nil
end

local function labelForState(state: string): string
	if state == "Step1_GrabCoin" then return "Grab the glowing coin" end
	if state == "Step2_Glide" then return "Step off the cliff to glide" end
	return ""
end

local function updateObjectiveMarkers(state: string)
	clearObjectiveMarkers()
	local part = findObjectivePart(state)
	if not part then return end

	local hl = Instance.new("Highlight")
	hl.FillColor = UI.Colors.Coin
	hl.OutlineColor = Color3.fromRGB(255, 255, 255)
	hl.FillTransparency = 0.7
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = part
	currentObjectiveHighlight = hl

	local bb = Instance.new("BillboardGui")
	bb.Adornee = part
	bb.Size = UDim2.new(0, 160, 0, 32)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 500
	bb.Parent = part
	currentObjectiveBillboard = bb

	-- 3D callout: Frame backdrop + label. No ImageLabel / CanvasGroup used
	-- so the billboard costs only primitive shader math.
	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.25
	backdrop.BorderSizePixel = 0
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = backdrop
	local bs = Instance.new("UIStroke"); bs.Color = UI.Colors.Coin; bs.Thickness = 2; bs.Parent = backdrop
	backdrop.Parent = bb

	local lbl = UI.newLabel(labelForState(state), UI.TextSize.Caption, UI.Colors.Coin)
	lbl.Size = UDim2.new(1, -6, 1, 0)
	lbl.Position = UDim2.new(0, 3, 0, 0)
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.Font = UI.Font.Black
	lbl.Parent = backdrop
end

------------------------------------------------------------
-- Arrow follow loop
------------------------------------------------------------
local arrowConn: RBXScriptConnection? = nil

local function startArrowFollow()
	if arrowConn then return end
	pointer.Parent = Workspace
	arrowConn = RunService.RenderStepped:Connect(function()
		local char = player.Character
		if not char then return end
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp or not currentObjective then return end

		local objective = currentObjective
		local anchor = hrp.Position + Vector3.new(0, 6, 0)
		local dir = (objective - anchor)
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude < 0.1 then flat = Vector3.new(0, 0, -1) end
		flat = flat.Unit
		pointer.CFrame = CFrame.lookAt(anchor + flat * 3, anchor + flat * 6) * CFrame.Angles(0, math.rad(180), 0)
	end)
end

local function stopArrowFollow()
	if arrowConn then arrowConn:Disconnect() arrowConn = nil end
	pointer.Parent = nil
end

------------------------------------------------------------
-- State transitions
------------------------------------------------------------
Remotes.TutorialState.OnClientEvent:Connect(function(state: string, objective: Vector3?)
	currentState = state
	currentObjective = objective

	if state == "Done" then
		stopArrowFollow()
		clearObjectiveMarkers()
		skipOuter.Visible = false
		banner.Visible = false
		return
	end

	skipOuter.Visible = true

	if state == "Step2_Glide_InAir" then
		-- Server is waiting for us to land. Trigger auto-glide.
		clearObjectiveMarkers()
		stopArrowFollow()
		bannerObjective.Text = "Gliding!"
		banner.Visible = true
		if _G.SYLS_StartGlide then
			_G.SYLS_StartGlide()
		end
		return
	end

	-- Normal visible step: banner + arrow + highlight.
	bannerObjective.Text = labelForState(state)
	banner.Visible = true
	startArrowFollow()
	updateObjectiveMarkers(state)
end)

-- If the character respawns mid-tutorial, re-apply markers to the right step.
player.CharacterAdded:Connect(function()
	if currentState and currentState ~= "Done" and currentState ~= "Step2_Glide_InAir" then
		task.wait(0.5)
		updateObjectiveMarkers(currentState)
	end
end)

print("[TutorialController] Ready. Waiting for tutorial state from server.")
