--!strict
-- ShopUI.client.lua
-- Right-side vertical rail of toggle buttons in the Yellow Zone, plus a
-- sliding shop/leaderboard drawer.
--
-- Layout rationale:
--   * The right-middle vertical strip is the Yellow Zone — reachable with
--     deliberate thumb extension, but NOT where the player rests their
--     thumbs during jumps. Putting shop/leaderboard/rebirth here prevents
--     accidental taps during gameplay (especially for rebirth, which is
--     functionally a commit-action: if a player misclicks it while rapidly
--     jumping they'd lose their progress).
--   * The drawer slides in from the right edge and covers the right ~40% of
--     the screen. The central column and character's feet stay visible so
--     the player can still see the 3D scene while browsing upgrades.
--   * Only one drawer is open at a time. Tapping the same rail button again
--     closes it; tapping a different button switches to that drawer.
--   * Upgrade rows are cloned/destroyed on open so the leaderboard's dynamic
--     entries don't leak memory between refreshes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Util = require(Shared:WaitForChild("Util"))
local UI = require(Shared:WaitForChild("UI"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local profile: any = nil
Remotes.DataUpdated.OnClientEvent:Connect(function(p) profile = p end)

local screen = UI.newScreenGui("ShopUI", playerGui)

------------------------------------------------------------
-- Right-rail of toggle buttons (middle-right Yellow Zone).
-- Per the doc, Yellow Zone = mid-screen edge = deliberate thumb extension.
-- Sitting mid-right keeps these buttons completely out of the bottom
-- jump thumb cluster, so rapid jumping can't accidentally open the shop
-- or (critically) trigger rebirth.
------------------------------------------------------------
local rail = Instance.new("Frame")
rail.Name = "Rail"
rail.AnchorPoint = Vector2.new(1, 0.5)
rail.Position = UDim2.new(1, -UI.Size.Margin, 0.5, 0)
rail.Size = UDim2.new(0, 44, 0, 156)
rail.BackgroundTransparency = 1
rail.Parent = screen

local railLayout = UI.addVerticalList(rail, 6)
railLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right

local function makeRailButton(label: string, color: Color3, order: number): TextButton
	local outer, _ = UI.newIconButton(label, color)
	outer.LayoutOrder = order
	outer.Parent = rail
	return outer
end

local btnShop = makeRailButton("SHOP", UI.Colors.SurfaceHot, 1)
local btnLeaderboard = makeRailButton("TOP", UI.Colors.SurfaceHot, 2)
local btnRebirth = makeRailButton("REBIRTH", UI.Colors.Rebirth, 3)

------------------------------------------------------------
-- Drawer (right-side sliding panel). A single Frame that swaps contents
-- between Shop and Leaderboard modes.
------------------------------------------------------------
local drawer = UI.newPanel("Drawer")
drawer.AnchorPoint = Vector2.new(1, 0.5)
-- Off-screen parked position (slid to the right, past the screen edge).
drawer.Position = UDim2.new(1, 260, 0.5, 0)
drawer.Size = UDim2.new(0, 240, 0.78, 0)   -- width in Offset; height Scale so it reflows
drawer.BackgroundColor3 = UI.Colors.Surface
drawer.BackgroundTransparency = 0.1
drawer.Visible = false
drawer.Parent = screen

-- Rail sits at about 1-Margin-44 from the right; park drawer just left of it.
local DRAWER_OPEN_X = -(UI.Size.Margin + 44 + 8)

UI.addPadding(drawer, 8)

local drawerTitle = UI.newLabel("", UI.TextSize.Body, UI.Colors.TextPrimary)
drawerTitle.Size = UDim2.new(1, 0, 0, 22)
drawerTitle.TextXAlignment = Enum.TextXAlignment.Center
drawerTitle.Font = UI.Font.Black
drawerTitle.Parent = drawer

local drawerBody = Instance.new("Frame")
drawerBody.Name = "Body"
drawerBody.BackgroundTransparency = 1
drawerBody.Position = UDim2.new(0, 0, 0, 28)
drawerBody.Size = UDim2.new(1, 0, 1, -32)
drawerBody.Parent = drawer

------------------------------------------------------------
-- Shop mode: upgrade list (Wingspan, JumpPower, WalkSpeed).
-- Built once and reused on every open.
------------------------------------------------------------
local shopRoot = Instance.new("Frame")
shopRoot.BackgroundTransparency = 1
shopRoot.Size = UDim2.new(1, 0, 1, 0)
shopRoot.Visible = false
shopRoot.Parent = drawerBody

local UPGRADES = { "Wingspan", "JumpPower", "WalkSpeed" }

local shopList = Instance.new("ScrollingFrame")
shopList.BackgroundTransparency = 1
shopList.BorderSizePixel = 0
shopList.Size = UDim2.new(1, 0, 1, 0)
shopList.ScrollBarThickness = 3
shopList.ScrollBarImageColor3 = UI.Colors.Stroke
shopList.CanvasSize = UDim2.new(0, 0, 0, 0)
shopList.AutomaticCanvasSize = Enum.AutomaticSize.Y
shopList.Parent = shopRoot
UI.addVerticalList(shopList, 4)

local upgradeRows: { [string]: { row: Frame, label: TextLabel, costLabel: TextLabel, button: TextButton } } = {}

local function buildUpgradeRow(name: string, order: number)
	local row = Instance.new("Frame")
	row.Name = name
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -4, 0, 48)
	row.BackgroundColor3 = UI.Colors.SurfaceSoft
	row.BackgroundTransparency = 0.1
	row.BorderSizePixel = 0
	local c = Instance.new("UICorner"); c.CornerRadius = UI.Size.CornerTight; c.Parent = row
	row.Parent = shopList

	local rowPad = Instance.new("UIPadding")
	rowPad.PaddingLeft = UDim.new(0, 6)
	rowPad.PaddingRight = UDim.new(0, 6)
	rowPad.Parent = row

	local nameLbl = UI.newLabel(name, UI.TextSize.Caption, UI.Colors.TextPrimary)
	nameLbl.Size = UDim2.new(0.55, 0, 0.5, 0)
	nameLbl.Position = UDim2.new(0, 0, 0, 4)
	nameLbl.Parent = row

	local costLbl = UI.newLabel("", UI.TextSize.Micro, UI.Colors.TextMuted)
	costLbl.Size = UDim2.new(0.55, 0, 0.5, -4)
	costLbl.Position = UDim2.new(0, 0, 0.5, 0)
	costLbl.Parent = row

	local buyOuter, buyInner = UI.newButton({
		Text = "BUY",
		Color = UI.Colors.Glide,
		Visual = Vector2.new(60, 32),
		Hitbox = Vector2.new(74, 44),
		TextSize = UI.TextSize.Caption,
	})
	buyOuter.AnchorPoint = Vector2.new(1, 0.5)
	buyOuter.Position = UDim2.new(1, 0, 0.5, 0)
	buyOuter.Parent = row

	buyOuter.Activated:Connect(function()
		local ok = Remotes.PurchaseUpgrade:InvokeServer(name)
		if not ok then
			-- Flash red briefly to indicate failure.
			local orig = buyInner.BackgroundColor3
			buyInner.BackgroundColor3 = UI.Colors.Danger
			task.delay(0.4, function()
				if buyInner.Parent then buyInner.BackgroundColor3 = orig end
			end)
		end
	end)

	upgradeRows[name] = { row = row, label = nameLbl, costLabel = costLbl, button = buyOuter }
end

for i, name in ipairs(UPGRADES) do
	buildUpgradeRow(name, i)
end

-- Rebirth row sits below upgrades with distinctive styling.
local rebirthRow = Instance.new("Frame")
rebirthRow.Name = "Rebirth"
rebirthRow.LayoutOrder = 99
rebirthRow.Size = UDim2.new(1, -4, 0, 48)
rebirthRow.BackgroundColor3 = UI.Colors.RebirthDeep
rebirthRow.BackgroundTransparency = 0.05
rebirthRow.BorderSizePixel = 0
local rebirthCorner = Instance.new("UICorner"); rebirthCorner.CornerRadius = UI.Size.CornerTight; rebirthCorner.Parent = rebirthRow
rebirthRow.Parent = shopList

local rebirthPad = Instance.new("UIPadding")
rebirthPad.PaddingLeft = UDim.new(0, 6)
rebirthPad.PaddingRight = UDim.new(0, 6)
rebirthPad.Parent = rebirthRow

local rebirthLabel = UI.newLabel("REBIRTH", UI.TextSize.Caption, UI.Colors.TextPrimary)
rebirthLabel.Size = UDim2.new(0.55, 0, 0.5, 0)
rebirthLabel.Position = UDim2.new(0, 0, 0, 4)
rebirthLabel.Font = UI.Font.Black
rebirthLabel.Parent = rebirthRow

local rebirthCostLabel = UI.newLabel("", UI.TextSize.Micro, UI.Colors.TextMuted)
rebirthCostLabel.Size = UDim2.new(0.55, 0, 0.5, -4)
rebirthCostLabel.Position = UDim2.new(0, 0, 0.5, 0)
rebirthCostLabel.Parent = rebirthRow

local rebirthOuter, _ = UI.newButton({
	Text = "REBIRTH",
	Color = UI.Colors.Rebirth,
	Visual = Vector2.new(74, 32),
	Hitbox = Vector2.new(90, 44),
	TextSize = UI.TextSize.Caption,
})
rebirthOuter.AnchorPoint = Vector2.new(1, 0.5)
rebirthOuter.Position = UDim2.new(1, 0, 0.5, 0)
rebirthOuter.Parent = rebirthRow
rebirthOuter.Activated:Connect(function()
	Remotes.Rebirth:InvokeServer()
end)

------------------------------------------------------------
-- Leaderboard mode
------------------------------------------------------------
local lbRoot = Instance.new("Frame")
lbRoot.BackgroundTransparency = 1
lbRoot.Size = UDim2.new(1, 0, 1, 0)
lbRoot.Visible = false
lbRoot.Parent = drawerBody

local lbList = Instance.new("ScrollingFrame")
lbList.BackgroundTransparency = 1
lbList.BorderSizePixel = 0
lbList.Size = UDim2.new(1, 0, 1, 0)
lbList.ScrollBarThickness = 3
lbList.ScrollBarImageColor3 = UI.Colors.Stroke
lbList.CanvasSize = UDim2.new(0, 0, 0, 0)
lbList.AutomaticCanvasSize = Enum.AutomaticSize.Y
lbList.Parent = lbRoot
UI.addVerticalList(lbList, 2)

-- Leaderboard rows are cloned/destroyed on each refresh — explicitly Destroy
-- rather than hide, so the garbage collector can reclaim them (per the
-- lifecycle rules on temporary UI).
local function clearLeaderboardRows()
	for _, child in ipairs(lbList:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
end

local function refreshLeaderboard()
	local ok, entries = pcall(function() return Remotes.GetLeaderboard:InvokeServer() end)
	if not ok or type(entries) ~= "table" then return end

	clearLeaderboardRows()
	for i, entry in ipairs(entries) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -2, 0, 22)
		row.BackgroundColor3 = (i % 2 == 0) and UI.Colors.SurfaceSoft or UI.Colors.Surface
		row.BackgroundTransparency = 0.3
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 3); rc.Parent = row
		row.Parent = lbList

		local rank = UI.newLabel("#" .. i, UI.TextSize.Micro, UI.Colors.TextMuted)
		rank.Size = UDim2.new(0, 28, 1, 0)
		rank.Position = UDim2.new(0, 4, 0, 0)
		rank.Parent = row

		local nameLbl = UI.newLabel(entry.name or "?", UI.TextSize.Micro, UI.Colors.TextPrimary)
		nameLbl.Size = UDim2.new(1, -100, 1, 0)
		nameLbl.Position = UDim2.new(0, 34, 0, 0)
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Parent = row

		local distLbl = UI.newLabel(Util.formatNumber(entry.distance or 0),
			UI.TextSize.Micro, UI.Colors.Glide)
		distLbl.Size = UDim2.new(0, 64, 1, 0)
		distLbl.Position = UDim2.new(1, -68, 0, 0)
		distLbl.TextXAlignment = Enum.TextXAlignment.Right
		distLbl.Parent = row
	end
end

------------------------------------------------------------
-- Drawer state
------------------------------------------------------------
local currentMode: string? = nil   -- "shop" / "leaderboard" / nil
local isAnimating = false

local function slideDrawer(targetX: number, onDone: () -> ()?)
	if UI.isReducedMotion() then
		drawer.Position = UDim2.new(1, targetX, 0.5, 0)
		if onDone then onDone() end
		return
	end
	isAnimating = true
	local t = UI.tween(drawer,
		TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Position = UDim2.new(1, targetX, 0.5, 0) })
	t.Completed:Connect(function()
		isAnimating = false
		if onDone then onDone() end
	end)
end

local function openMode(mode: string)
	if currentMode == mode then return end
	currentMode = mode
	shopRoot.Visible = (mode == "shop")
	lbRoot.Visible = (mode == "leaderboard")
	drawerTitle.Text = (mode == "shop") and "SHOP" or "LONGEST GLIDES"
	if mode == "leaderboard" then refreshLeaderboard() end
	drawer.Visible = true
	slideDrawer(DRAWER_OPEN_X, nil)
end

local function closeDrawer()
	if not currentMode then return end
	currentMode = nil
	slideDrawer(260, function()
		drawer.Visible = false
		-- Free leaderboard rows when drawer is closed so they don't linger.
		clearLeaderboardRows()
	end)
end

btnShop.Activated:Connect(function()
	if isAnimating then return end
	if currentMode == "shop" then closeDrawer() else openMode("shop") end
end)
btnLeaderboard.Activated:Connect(function()
	if isAnimating then return end
	if currentMode == "leaderboard" then closeDrawer() else openMode("leaderboard") end
end)
btnRebirth.Activated:Connect(function()
	if isAnimating then return end
	-- Rebirth rail button also opens the shop drawer (rebirth row is at the
	-- bottom of it) — keeping the confirmation visible avoids accidental
	-- one-tap rebirths from a floating button.
	openMode("shop")
end)

------------------------------------------------------------
-- Live profile -> shop labels. Only mutates when values actually change so
-- static frames stay batched by the renderer.
------------------------------------------------------------
local lastDerived: { [string]: string } = {}
task.spawn(function()
	while true do
		if profile then
			for _, name in ipairs(UPGRADES) do
				local rowRef = upgradeRows[name]
				if rowRef then
					local lvl = profile.Upgrades and profile.Upgrades[name] or 0
					local cost = Config.getUpgradeCost(name, lvl)
					local text: string
					if cost == math.huge then
						text = ("Lv %d  (MAX)"):format(lvl)
					else
						text = ("Lv %d  |  %s coins"):format(lvl, Util.formatNumber(cost))
					end
					if lastDerived[name] ~= text then
						lastDerived[name] = text
						rowRef.costLabel.Text = text
						rowRef.label.Text = name
					end
				end
			end
			local required = Config.getRebirthRequirement(profile.Rebirths or 0)
			local rebText = ("Requires %s coins"):format(Util.formatNumber(required))
			if lastDerived.__rebirth ~= rebText then
				lastDerived.__rebirth = rebText
				rebirthCostLabel.Text = rebText
			end
		end
		task.wait(0.5)
	end
end)
