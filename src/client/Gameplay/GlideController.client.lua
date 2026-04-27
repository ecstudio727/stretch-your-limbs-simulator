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

local distValue = UI.newLabel("0 coins", UI.TextSize.Heading, UI.Colors.TextPrimary)
distValue.Size = UDim2.new(1, 0, 1, -14)
distValue.Position = UDim2.new(0, 0, 0, 14)
distValue.TextXAlignment = Enum.TextXAlignment.Center
distValue.Parent = distCard

local distScale = Instance.new("UIScale")
distScale.Scale = 1
distScale.Parent = distValue

-- Milestone burst plays the "+100 COINS!" punch animation.
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

	-- Floating "+N COINS!" label rising above the distance card.
	if UI.isReducedMotion() then return end  -- skip floater for motion-sensitive users
	local burst = UI.newLabel(threshold .. " COINS!", UI.TextSize.Body, UI.Colors.Coin)
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
	distValue.Text = "0 coins"
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

		-- Live coin readout + per-100-stud milestone burst. The trigger
		-- cadence stays "every 100 distance studs" (well-tuned ~3-4 sec
		-- intervals at level 0) but both the live readout and the burst
		-- label show the actual coin amount the player is earning, to
		-- stay consistent with the BEST stat in HUD.
		if state.glideStartPos then
			local dist = math.floor(Util.horizontalDistance(state.glideStartPos, root.Position))
			local coins = math.floor(dist * Config.Glide.CoinsPerStud)
			distValue.Text = coins .. " coins"
			local milestone = math.floor(dist / 100)
			if milestone > state.lastMilestone then
				state.lastMilestone = milestone
				playMilestoneBurst(math.floor(milestone * 100 * Config.Glide.CoinsPerStud))
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
-- On-screen GLIDE button — big 3D candy square anchored bottom-center.
--
-- Style is lifted from flip-a-coin-for-brainrots' FLIP button: lifted
-- shadow + shine highlight + stud texture + click burst, FredokaOne text.
-- The button itself lives in shared/UI.lua as UI.new3DButton so other
-- screens can reuse it.
--
-- Sized so it dominates the bottom of the screen (it's THE main game
-- action). On desktop 160×160, on mobile 120×120 — both well above the
-- 44×44 hitbox minimum and big enough to thumb-tap without aiming.
------------------------------------------------------------
local glideIsMobile = UI.isTouch()
-- Wide rectangle, matching the proportions of the FLIP button reference
-- (~3:1 width:height) but a touch chunkier so it dominates the bottom.
local GLIDE_BTN_W = glideIsMobile and 220 or 320
local GLIDE_BTN_H = glideIsMobile and 72  or 100
local GLIDE_BTN_BOTTOM_MARGIN = glideIsMobile and 16 or 28

-- State color palettes. Shadow is a darker shade of the top so the
-- "lifted" silhouette stays consistent on every state swap.
local GLIDE_COLORS = {
	ready = { top = Color3.fromRGB(40, 200, 40),  bottom = Color3.fromRGB(20, 140, 20) },  -- green = airborne, can glide
	active = { top = Color3.fromRGB(255, 140, 50), bottom = Color3.fromRGB(180, 80, 20) }, -- orange = currently gliding
	idle = { top = Color3.fromRGB(120, 125, 130), bottom = Color3.fromRGB(70, 75, 80) },   -- grey = grounded, unavailable
}

local glideBtn, glideContainer, glideShadow = UI.new3DButton({
	Parent = screen,
	Text = "GLIDE",
	Size = UDim2.new(0, GLIDE_BTN_W, 0, GLIDE_BTN_H),
	-- Bottom-center, lifted off the screen edge so the press-down anim
	-- has room to drop without clipping the bottom.
	Position = UDim2.new(0.5, 0, 1, -GLIDE_BTN_BOTTOM_MARGIN),
	AnchorPoint = Vector2.new(0.5, 1),
	TopColor = GLIDE_COLORS.ready.top,
	BottomColor = GLIDE_COLORS.ready.bottom,
	Mobile = glideIsMobile,
})
glideBtn.Activated:Connect(tryActivateGlide)

-- Visual state: green when airborne & available, orange when active,
-- grey when grounded. RenderStepped fires every frame but we only mutate
-- properties on actual state transitions, so the engine still skips most.
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

	local palette = GLIDE_COLORS[s]
	glideBtn.BackgroundColor3 = palette.top
	glideShadow.BackgroundColor3 = palette.bottom
	glideBtn.Text = (s == "active") and "STOP" or "GLIDE"
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
