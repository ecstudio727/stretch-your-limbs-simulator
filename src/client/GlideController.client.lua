--!strict
-- GlideController.client.lua
-- Handles the glide physics AND the glide UI (button, live-distance card,
-- milestone bursts).
--
-- UI placement follows the ergonomic rules we settled on:
--   * The GLIDE button sits in the Yellow Zone on the right side, anchored
--     ABOVE where the Roblox-native jump button lives on mobile. This
--     deliberately avoids the bottom-right Green Zone (where the native jump
--     button is) so players rapidly tapping jump can't misclick glide.
--   * The visible button is 150x64; the clickable hitbox is 180x96 (heavy
--     invisible padding, per Fitts's Law — capture off-center panicked taps).
--   * The live-distance card sits at the TOP of the screen. Obby UI must
--     never occupy the central column or lower-middle — that space is for
--     reading jump trajectories and tracking the character's feet.
--   * Milestone bursts rise above the distance card (stays in the peripheral
--     Red Zone; never blocks the gameplay arena).
--   * Accessibility: all animations route through UI.tween so the
--     ReducedMotionEnabled flag suppresses motion for sensitive users.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Util = require(Shared:WaitForChild("Util"))
local UI = require(Shared:WaitForChild("UI"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

------------------------------------------------------------
-- Glide state
------------------------------------------------------------
local state = {
	profile = nil :: any,
	gliding = false,
	glideConn = nil :: RBXScriptConnection?,
	linearVelocity = nil :: LinearVelocity?,
	attachment = nil :: Attachment?,
	originalScales = {} :: { [string]: number },
	glideStartPos = nil :: Vector3?,
	lastMilestone = 0,
}

Remotes.DataUpdated.OnClientEvent:Connect(function(profile)
	state.profile = profile
end)

task.spawn(function()
	local ok, profile = pcall(function()
		return Remotes.GetProfile:InvokeServer()
	end)
	if ok then state.profile = profile end
end)

local function getWingspanLevel(): number
	if not state.profile then return 0 end
	return state.profile.Upgrades and state.profile.Upgrades.Wingspan or 0
end

local function stretchLimbs(char: Model, factor: number)
	for _, name in ipairs({ "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand" }) do
		local part = char:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			if not state.originalScales[name] then
				state.originalScales[name] = part.Size.X
			end
			local orig = state.originalScales[name]
			part.Size = Vector3.new(orig * (1 + factor * 2), part.Size.Y, part.Size.Z)
		end
	end
end

local function resetLimbs(char: Model)
	for _, name in ipairs({ "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand" }) do
		local part = char:FindFirstChild(name)
		if part and part:IsA("BasePart") and state.originalScales[name] then
			part.Size = Vector3.new(state.originalScales[name], part.Size.Y, part.Size.Z)
		end
	end
end

------------------------------------------------------------
-- UI: single consolidated ScreenGui so the engine can batch the static
-- chrome. All UI refs are declared BEFORE startGlide so the Lua parser
-- resolves them as locals (otherwise they'd compile as nil globals).
------------------------------------------------------------
local screen = UI.newScreenGui("GlideControls", playerGui)

-- Live distance card (top-center, just below the HUD stats strip).
-- Hidden until glide starts. Compact phone-friendly size.
local distCard = UI.newPanel("DistanceCard")
distCard.AnchorPoint = Vector2.new(0.5, 0)
distCard.Position = UDim2.new(0.5, 0, 0, UI.Size.Margin + 46)
distCard.Size = UDim2.new(0, 200, 0, 56)
distCard.BackgroundColor3 = Color3.fromRGB(14, 24, 38)
distCard.BackgroundTransparency = 0.2
distCard.Visible = false
distCard.Parent = screen

local distStroke = distCard:FindFirstChildWhichIsA("UIStroke") :: UIStroke
distStroke.Color = UI.Colors.Glide
distStroke.Thickness = 1
distStroke.Transparency = 0.2

UI.addPadding(distCard, 4)

local distTitle = UI.newLabel("GLIDE", UI.TextSize.Micro, UI.Colors.TextAccent)
distTitle.Size = UDim2.new(1, 0, 0, 12)
distTitle.TextXAlignment = Enum.TextXAlignment.Center
distTitle.Parent = distCard

local distValue = UI.newLabel("0 studs", UI.TextSize.Heading, UI.Colors.TextPrimary)
distValue.Size = UDim2.new(1, 0, 1, -14)
distValue.Position = UDim2.new(0, 0, 0, 14)
distValue.TextXAlignment = Enum.TextXAlignment.Center
distValue.Parent = distCard

local distScale = Instance.new("UIScale")
distScale.Scale = 1
distScale.Parent = distValue

-- Milestone burst plays the "+100 STUDS!" punch animation.
-- Pure-Frame + TextLabel + UIScale — no ImageLabel / CanvasGroup, so
-- no asset fetch, no VRAM overhead.
local function playMilestoneBurst(threshold: number)
	-- Punch the main counter.
	if not UI.isReducedMotion() then
		distScale.Scale = 1
		UI.tween(distScale,
			TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true),
			{ Scale = 1.45 })
	end

	-- Flash the counter text gold, then back.
	distValue.TextColor3 = UI.Colors.Coin
	task.delay(0.35, function()
		if distValue.Parent then
			distValue.TextColor3 = UI.Colors.TextPrimary
		end
	end)

	-- Ring-flash the card border.
	local origStrokeTrans = distStroke.Transparency
	local origStrokeColor = distStroke.Color
	distStroke.Color = UI.Colors.Coin
	distStroke.Transparency = 0
	UI.tween(distStroke,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = origStrokeTrans })
	task.delay(0.6, function()
		if distStroke.Parent then distStroke.Color = origStrokeColor end
	end)

	-- Floating "+N STUDS!" label rising above the distance card.
	if UI.isReducedMotion() then return end  -- skip floater for motion-sensitive users
	local burst = UI.newLabel(threshold .. " STUDS!", UI.TextSize.Body, UI.Colors.Coin)
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.new(0.5, 0, 0, UI.Size.Margin + 46 + 86)
	burst.Size = UDim2.new(0, 220, 0, 28)
	burst.TextXAlignment = Enum.TextXAlignment.Center
	burst.TextStrokeColor3 = UI.Colors.CoinDeep
	burst.TextStrokeTransparency = 0
	burst.Font = UI.Font.Black
	burst.Parent = screen

	local burstScale = Instance.new("UIScale"); burstScale.Scale = 0.6; burstScale.Parent = burst
	UI.tween(burstScale,
		TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1.1 })
	UI.tween(burst,
		TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, UI.Size.Margin + 46 + 40), TextTransparency = 1, TextStrokeTransparency = 1 })
	task.delay(1.0, function() burst:Destroy() end)
end

------------------------------------------------------------
-- Glide physics
------------------------------------------------------------
local endGlide -- forward declaration

local function startGlide(_force: boolean?)
	if state.gliding then return end
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end

	state.gliding = true
	state.glideStartPos = hrp.Position
	state.lastMilestone = 0
	distValue.Text = "0 studs"
	distScale.Scale = 1
	distCard.Visible = true
	Remotes.GlideStarted:FireServer()

	local wingspan = getWingspanLevel()
	stretchLimbs(char, math.min(wingspan * 0.06, 1.5))

	local forwardSpeed, fallSpeed = Config.getGlideParams(wingspan)

	local attachment = Instance.new("Attachment")
	attachment.Parent = hrp
	state.attachment = attachment

	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = attachment
	lv.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	lv.MaxForce = math.huge
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.VectorVelocity = Vector3.new(0, -fallSpeed, 0)
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = hrp
	state.linearVelocity = lv

	state.glideConn = RunService.Heartbeat:Connect(function()
		if not state.gliding then return end
		local c = player.Character
		if not c then return end
		local root = c:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = c:FindFirstChildWhichIsA("Humanoid")
		if not root or not humanoid then return end

		-- End glide when grounded.
		if humanoid.FloorMaterial ~= Enum.Material.Air then
			endGlide()
			return
		end

		local look = root.CFrame.LookVector
		look = Vector3.new(look.X, 0, look.Z)
		if look.Magnitude < 0.01 then return end
		look = look.Unit
		lv.VectorVelocity = Vector3.new(look.X * forwardSpeed, -fallSpeed, look.Z * forwardSpeed)

		-- Live distance readout + per-100-stud milestone burst.
		if state.glideStartPos then
			local dist = math.floor(Util.horizontalDistance(state.glideStartPos, root.Position))
			distValue.Text = dist .. " studs"
			local milestone = math.floor(dist / 100)
			if milestone > state.lastMilestone then
				state.lastMilestone = milestone
				playMilestoneBurst(milestone * 100)
			end
		end

		-- Tilt for style.
		local gyro = root:FindFirstChild("GlideTilt") :: BodyGyro?
		if not gyro then
			local g = Instance.new("BodyGyro")
			g.Name = "GlideTilt"
			g.MaxTorque = Vector3.new(math.huge, 0, math.huge)
			g.P = 3000
			g.D = 500
			g.CFrame = CFrame.lookAt(Vector3.zero, look) * CFrame.Angles(math.rad(-15), 0, 0)
			g.Parent = root
		end
	end)
end

endGlide = function()
	if not state.gliding then return end
	state.gliding = false
	Remotes.GlideEnded:FireServer()

	if state.glideConn then state.glideConn:Disconnect() state.glideConn = nil end
	if state.linearVelocity then state.linearVelocity:Destroy() state.linearVelocity = nil end
	if state.attachment then state.attachment:Destroy() state.attachment = nil end

	-- Keep the final distance visible for ~1.2s so it's readable.
	task.delay(1.2, function()
		if not state.gliding then
			distCard.Visible = false
		end
	end)

	state.glideStartPos = nil
	state.lastMilestone = 0

	local char = player.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local gyro = hrp and hrp:FindFirstChild("GlideTilt")
		if gyro then gyro:Destroy() end
		resetLimbs(char)
	end
end

-- Tutorial hook.
_G.SYLS_StartGlide = function()
	startGlide(true)
end

local function tryActivateGlide()
	if state.gliding then
		endGlide()
		return
	end
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char:FindFirstChildWhichIsA("Humanoid")
	if not hrp or not humanoid then return end
	if humanoid.FloorMaterial == Enum.Material.Air then
		startGlide()
	end
end

-- Keybind: F (primary) and E (legacy alias). Space is deliberately NOT bound
-- — it conflicts with the default jump input.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.E then
		tryActivateGlide()
	end
end)

------------------------------------------------------------
-- On-screen GLIDE button.
--
-- GLIDE is a split-second reaction action — per the heatmap doc, those
-- belong in the GREEN ZONE. The bottom-right Green Zone is owned by the
-- native Roblox jump button, so we anchor the GLIDE button DIRECTLY
-- ADJACENT to it (~24 px to its left), which is the exact pattern the
-- doc recommends: "fetch the absolute position of the native jump button
-- and create custom buttons twenty to seventy pixels adjacent to it".
-- The native jump button on mobile is ~70 px wide and sits ~20 px from
-- the bottom-right corner, so our visible glide button lands in a place
-- the thumb can flick to without regripping.
--
-- Visual 64x64 circular button, 96x96 invisible hitbox so off-center
-- panicked taps still register (Fitts's Law).
------------------------------------------------------------
local JUMP_BTN_EST_WIDTH = 70   -- Roblox native jump button (mobile)
local JUMP_BTN_EST_RIGHT = 20   -- distance from screen right edge
local JUMP_BTN_EST_BOTTOM = 20  -- distance from screen bottom edge
local GLIDE_JUMP_GAP = 24       -- gap so the two buttons don't collide

local glideBtnOuter, glideBtnInner = UI.newButton({
	Text = "GLIDE",
	Color = UI.Colors.Glide,
	TextColor = UI.Colors.TextPrimary,
	Visual = Vector2.new(64, 64),
	Hitbox = Vector2.new(96, 96),
	TextSize = UI.TextSize.Caption,
	Font = UI.Font.Black,
})
glideBtnOuter.AnchorPoint = Vector2.new(1, 1)
-- Anchor to bottom-right, then push LEFT by (native jump width + right
-- margin + our gap) so we sit just to the left of the native jump button.
glideBtnOuter.Position = UDim2.new(
	1, -(JUMP_BTN_EST_RIGHT + JUMP_BTN_EST_WIDTH + GLIDE_JUMP_GAP),
	1, -JUMP_BTN_EST_BOTTOM
)
glideBtnOuter.Parent = screen
glideBtnOuter.Activated:Connect(tryActivateGlide)

-- Make the visual a circle so it reads distinctly from the square native
-- jump button next to it.
local glideInnerCorner = glideBtnInner:FindFirstChildWhichIsA("UICorner")
if glideInnerCorner then glideInnerCorner.CornerRadius = UDim.new(1, 0) end

-- Find the inner label so we can retheme it by state.
local glideBtnLabel = glideBtnInner:FindFirstChildWhichIsA("TextLabel")

-- Visual state: bright when airborne & available, orange when active, dim
-- when grounded. Runs on RenderStepped but only mutates properties when the
-- state actually changes, so the engine can still skip most frames.
local lastBtnState = ""
RunService.RenderStepped:Connect(function()
	local char = player.Character
	local humanoid = char and char:FindFirstChildWhichIsA("Humanoid")
	local airborne = humanoid and humanoid.FloorMaterial == Enum.Material.Air

	local s
	if state.gliding then s = "active"
	elseif airborne then s = "ready"
	else s = "idle" end

	if s == lastBtnState then return end
	lastBtnState = s

	if s == "active" then
		glideBtnInner.BackgroundColor3 = Color3.fromRGB(230, 140, 60)
		if glideBtnLabel then glideBtnLabel.Text = "STOP" end
	elseif s == "ready" then
		glideBtnInner.BackgroundColor3 = UI.Colors.Glide
		if glideBtnLabel then glideBtnLabel.Text = "GLIDE" end
	else
		glideBtnInner.BackgroundColor3 = UI.Colors.Disabled
		if glideBtnLabel then glideBtnLabel.Text = "GLIDE" end
	end
end)

player.CharacterAdded:Connect(function()
	state.gliding = false
	state.glideStartPos = nil
	state.lastMilestone = 0
	distCard.Visible = false
	if state.glideConn then state.glideConn:Disconnect() state.glideConn = nil end
	if state.linearVelocity then state.linearVelocity:Destroy() state.linearVelocity = nil end
	if state.attachment then state.attachment:Destroy() state.attachment = nil end
end)

print("[GlideController] Press F (or tap the GLIDE button) while airborne to stretch your limbs and glide.")
