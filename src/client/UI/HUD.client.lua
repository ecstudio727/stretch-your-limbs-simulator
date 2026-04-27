--!strict
-- HUD.client.lua
-- Top-of-screen passive telemetry + toast notifications.
--
-- Layout follows the Obby peripheral-UI rule: passive info lives in the
-- Red Zone (top of screen), NOT in the central column or lower-middle where
-- the player is reading jump trajectories. All elements use Offset sizing
-- with Scale-based anchoring so they reflow cleanly across desktop/console/
-- mobile without warping icons or clipping text.
--
-- Exactly ONE ScreenGui is used for all HUD elements so the engine can
-- batch the static chrome into a single draw-call pass (per UI
-- optimization rules — fewer ScreenGuis = fewer isolated render passes).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Util = require(Shared:WaitForChild("Util"))
local UI = require(Shared:WaitForChild("UI"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screen = UI.newScreenGui("HUD", playerGui)

------------------------------------------------------------
-- Coins chip (top-left). Primary currency — prominent but passive.
-- Anchored to top-left with a small margin; uses AutomaticSize so the chip
-- grows to fit large numbers without squishing text.
------------------------------------------------------------
local coinsChip = UI.newPanel("CoinsChip")
coinsChip.AnchorPoint = Vector2.new(0, 0)
coinsChip.Position = UDim2.new(0, UI.Size.Margin, 0, UI.Size.Margin)
coinsChip.Size = UDim2.new(0, 110, 0, 30)
coinsChip.AutomaticSize = Enum.AutomaticSize.X
coinsChip.BackgroundColor3 = UI.Colors.Surface
coinsChip.BackgroundTransparency = 0.2
coinsChip.Parent = screen
UI.addPadding(coinsChip, 6)
UI.addHorizontalList(coinsChip, 5)

-- Coin pip — real asset via UI.newIcon. If the icon ID is ever stripped
-- from Icons.lua, falls back to a "$" badge so the chip layout holds.
local coinPip = UI.newIcon("Coin", 18, "$")
coinPip.LayoutOrder = 1
coinPip.Parent = coinsChip

local coinsLabel = UI.newLabel("0", UI.TextSize.Body, UI.Colors.TextPrimary)
coinsLabel.Size = UDim2.new(0, 90, 1, 0)
coinsLabel.AutomaticSize = Enum.AutomaticSize.X
coinsLabel.TextXAlignment = Enum.TextXAlignment.Left
coinsLabel.LayoutOrder = 2
coinsLabel.Parent = coinsChip

------------------------------------------------------------
-- Stats strip (top-center, under the Roblox topbar).
-- Placed here because (a) it's passive info and (b) the top of the screen
-- sits cleanly in the F-pattern / Z-pattern scanning axis — the brain
-- registers the numbers without breaking focus from the gameplay arena.
------------------------------------------------------------
local statsStrip = UI.newPanel("StatsStrip")
statsStrip.AnchorPoint = Vector2.new(0.5, 0)
statsStrip.Position = UDim2.new(0.5, 0, 0, UI.Size.Margin)
statsStrip.Size = UDim2.new(0, 260, 0, 28)
statsStrip.BackgroundColor3 = UI.Colors.Surface
statsStrip.BackgroundTransparency = 0.25
statsStrip.Parent = screen
UI.addPadding(statsStrip, 4)
local statsLayout = UI.addHorizontalList(statsStrip, 12)
statsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

-- Each stat pair is icon (if available) + caption + value. The icon
-- falls back to empty so missing art reads as text-only without a layout
-- gap.
local function makeStatPair(captionText: string, iconKey: string?, order: number): (TextLabel, TextLabel)
	local group = Instance.new("Frame")
	group.BackgroundTransparency = 1
	group.Size = UDim2.new(0, 110, 1, 0)
	group.AutomaticSize = Enum.AutomaticSize.X
	group.LayoutOrder = order
	local groupLayout = UI.addHorizontalList(group, 4)
	groupLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	if iconKey then
		-- tryIcon returns nil when the asset ID isn't in Icons.lua yet —
		-- the slot collapses cleanly so missing art doesn't leave a gap.
		-- Drop a real ID into Icons.lua and the icon appears next play.
		local icon = UI.tryIcon(iconKey, 14)
		if icon then
			icon.LayoutOrder = 1
			icon.Parent = group
		end
	end

	local caption = UI.newLabel(captionText, UI.TextSize.Micro, UI.Colors.TextMuted)
	caption.Size = UDim2.new(0, 0, 1, 0)
	caption.AutomaticSize = Enum.AutomaticSize.X
	caption.LayoutOrder = 2
	caption.Parent = group

	local value = UI.newLabel("0", UI.TextSize.Caption, UI.Colors.TextPrimary)
	value.Size = UDim2.new(0, 0, 1, 0)
	value.AutomaticSize = Enum.AutomaticSize.X
	value.LayoutOrder = 3
	value.Parent = group

	group.Parent = statsStrip
	return caption, value
end

local _, rebirthsValue = makeStatPair("REBIRTHS", "Rebirth", 1)
-- BEST is the player's best single glide expressed in COINS (not studs).
-- The internal record is still BestGlideDistance; we multiply by
-- CoinsPerStud at display time so the number matches the same currency
-- the coin chip shows. Icon is the Coin asset for the same reason.
local _, bestGlideValue = makeStatPair("BEST", "Coin", 2)

-- Slide-fade-in entrance for both top chips on first appearance.
UI.attachAppearFx(coinsChip, { fromYOffset = -10, duration = 0.28 })
UI.attachAppearFx(statsStrip, { fromYOffset = -10, duration = 0.28, delay = 0.06 })

------------------------------------------------------------
-- Toast notifications. Appears below the stats strip so it never intrudes
-- on the central column (spatial awareness zone). Auto-fades respecting
-- ReducedMotion.
------------------------------------------------------------
-- Top-LEFT under the coins chip. Center-top is reserved for the stats strip
-- and the glide distance card; bottom-center is explicitly forbidden by the
-- doc for pop-up toasts (central column occlusion = blinded to hazards).
local toast = UI.newPanel("Toast")
toast.AnchorPoint = Vector2.new(0, 0)
toast.Position = UDim2.new(0, UI.Size.Margin, 0, UI.Size.Margin + 36)
toast.Size = UDim2.new(0, 220, 0, 24)
toast.BackgroundColor3 = Color3.fromRGB(26, 30, 40)
toast.BackgroundTransparency = 1
toast.Visible = false
toast.Parent = screen
UI.addPadding(toast, 4)

local toastLabel = UI.newLabel("", UI.TextSize.Micro, UI.Colors.Coin)
toastLabel.Size = UDim2.new(1, 0, 1, 0)
toastLabel.TextXAlignment = Enum.TextXAlignment.Left
toastLabel.Parent = toast

local toastToken = 0
local function showToast(msg: string)
	toastToken += 1
	local myToken = toastToken
	toastLabel.Text = msg
	toast.Visible = true

	-- Fade-in respecting ReducedMotion.
	if UI.isReducedMotion() then
		toast.BackgroundTransparency = 0.2
		toastLabel.TextTransparency = 0
	else
		toast.BackgroundTransparency = 1
		toastLabel.TextTransparency = 1
		UI.tween(toast, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0.2 })
		UI.tween(toastLabel, TweenInfo.new(0.18), { TextTransparency = 0 })
	end

	task.delay(3.2, function()
		if myToken ~= toastToken then return end
		if UI.isReducedMotion() then
			toast.Visible = false
			return
		end
		UI.tween(toast, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 })
		UI.tween(toastLabel, TweenInfo.new(0.35), { TextTransparency = 1 })
		task.delay(0.36, function()
			if myToken == toastToken then toast.Visible = false end
		end)
	end)
end

Remotes.Notify.OnClientEvent:Connect(showToast)

------------------------------------------------------------
-- Profile sync. Coins tween smoothly so increments feel rewarding without
-- introducing cognitive load; respect ReducedMotion by snapping instead.
------------------------------------------------------------
local lastCoins = 0
local function applyProfile(profile: any)
	if not profile then return end
	local coins = profile.Coins or 0
	if UI.isReducedMotion() or math.abs(coins - lastCoins) < 2 then
		coinsLabel.Text = Util.formatNumber(coins)
		lastCoins = coins
	else
		-- Tick up / down over ~0.4s for a bit of satisfaction.
		local start = lastCoins
		local target = coins
		lastCoins = coins
		local t0 = os.clock()
		task.spawn(function()
			while true do
				local a = math.min(1, (os.clock() - t0) / 0.4)
				local cur = math.floor(start + (target - start) * a)
				coinsLabel.Text = Util.formatNumber(cur)
				if a >= 1 then break end
				task.wait()
			end
		end)
	end
	rebirthsValue.Text = tostring(profile.Rebirths or 0)
	-- Display BEST as base coins earned (distance × CoinsPerStud), so the
	-- player sees a number in the same units as their coin balance.
	-- Multipliers (rebirth, pet) are NOT applied here — this is the
	-- baseline "what a record-breaking glide is worth" reading.
	local bestDistance = profile.BestGlideDistance or 0
	local bestCoins = math.floor(bestDistance * Config.Glide.CoinsPerStud)
	bestGlideValue.Text = Util.formatNumber(bestCoins)
end

Remotes.DataUpdated.OnClientEvent:Connect(applyProfile)

-- Pull once on startup in case we missed the initial push.
task.spawn(function()
	local ok, profile = pcall(function()
		return Remotes.GetProfile:InvokeServer()
	end)
	if ok and profile then applyProfile(profile) end
end)
