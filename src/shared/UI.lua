--!strict
-- UI.lua
-- Shared UI theme + helpers for Stretch Your Limbs Simulator.
--
-- Design principles encoded here follow the Obby / cross-platform optimization
-- guidelines we settled on:
--   * Reflow Sizing Model: content uses Offset (pixels) so physical hitboxes
--     stay consistent across devices; containers use Scale so the layout can
--     reflow as the screen shrinks.
--   * Fixed TextSize baselines — NEVER TextScaled=true (inconsistent font
--     sizes across sibling elements + ~10x render cost per frame).
--   * 44x44 minimum tap target; primary CTAs use a 144x60+ hitbox with a
--     slightly smaller visual button (Fitts's Law — capture off-center taps).
--   * Peripheral layout for Obby gameplay: keep center and lower-middle clear
--     for spatial awareness; push interactive UI to the edges with ~6px margin.
--   * Ergonomic zones: bottom-left / bottom-right are owned by Roblox
--     (thumbstick + jump button on mobile). Custom buttons sit in the
--     Yellow Zone (middle-right vertical) to avoid mis-taps during jumps.
--   * Prefer Frames + UICorner + UIGradient over CanvasGroups (CanvasGroups
--     spend VRAM on an intermediate buffer and down-res on low-end devices).
--   * Prefer Frames over ImageLabels wherever a pure primitive works.
--   * Respect GuiService.PreferredTransparency (accessibility) and
--     ReducedMotionEnabled (tween suppression for motion-sensitive users).
--   * Sibling ZIndex behavior (default) — modular, encapsulated components.

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Icons = require(script.Parent:WaitForChild("Icons"))
local StudsUI = require(script.Parent:WaitForChild("StudsUI"))

local UI = {}

-- Re-export the raw icon table so callers can read it without a second require.
UI.Icons = Icons

------------------------------------------------------------
-- Palette
------------------------------------------------------------
UI.Colors = {
	-- Surfaces
	Surface         = Color3.fromRGB(18, 24, 34),
	SurfaceSoft     = Color3.fromRGB(30, 38, 52),
	SurfaceHot      = Color3.fromRGB(48, 60, 82),

	-- Text
	TextPrimary     = Color3.fromRGB(245, 248, 255),
	TextMuted       = Color3.fromRGB(170, 190, 210),
	TextAccent      = Color3.fromRGB(120, 200, 255),

	-- Accents
	Coin            = Color3.fromRGB(255, 210, 70),
	CoinDeep        = Color3.fromRGB(180, 130, 30),
	Glide           = Color3.fromRGB(90, 190, 255),
	GlideDeep       = Color3.fromRGB(30, 100, 170),
	Rebirth         = Color3.fromRGB(220, 110, 210),
	RebirthDeep     = Color3.fromRGB(130, 40, 140),
	Danger          = Color3.fromRGB(230, 90, 90),
	Success         = Color3.fromRGB(120, 230, 150),
	Disabled        = Color3.fromRGB(80, 90, 100),
	Stroke          = Color3.fromRGB(90, 130, 170),
}

------------------------------------------------------------
-- Typography (fixed sizes — no TextScaled).
-- Baseline 20 is calibrated for ~160 DPI readability.
------------------------------------------------------------
UI.Font = {
	Body      = Enum.Font.Gotham,
	Bold      = Enum.Font.GothamBold,
	Black     = Enum.Font.GothamBlack,
}

-- Text sizes are tuned for phone landscape. The 20-pt baseline stays
-- because the doc calibrates it to ~1/8 inch physical height on a 160-DPI
-- phone; everything else shrinks around it so info-dense labels don't
-- swallow the screen on small displays.
UI.TextSize = {
	Micro     = 11,  -- side-captions, ranks
	Caption   = 13,  -- secondary info
	Body      = 15,  -- primary info
	Baseline  = 18,  -- readable baseline
	Title     = 20,  -- panel titles
	Heading   = 24,
	Display   = 30,  -- glide distance, hero stat
}

------------------------------------------------------------
-- Sizing / padding constants. All offsets, so hitboxes stay consistent
-- across devices. Tuned for phone landscape first — desktop inherits the
-- same pixel sizes (which look appropriately compact on large screens).
------------------------------------------------------------
UI.Size = {
	Margin         = 6,        -- minimum breathing room from screen edge
	Gutter         = 6,        -- gap between sibling controls
	Corner         = UDim.new(0, 10),
	CornerTight    = UDim.new(0, 6),
	StrokeThick    = 1,
	HitboxMin      = Vector2.new(44, 44),   -- WCAG minimum
	TapButton      = Vector2.new(120, 44),  -- primary CTA (visual)
	TapButtonSmall = Vector2.new(96, 36),   -- secondary
	IconButton     = Vector2.new(44, 44),   -- rail / toolbar icon
}

------------------------------------------------------------
-- Accessibility helpers
------------------------------------------------------------
function UI.isReducedMotion(): boolean
	local ok, v = pcall(function() return GuiService.ReducedMotionEnabled end)
	if ok then return v end
	return false
end

function UI.getPreferredTransparency(): number
	local ok, v = pcall(function() return GuiService.PreferredTransparency end)
	if ok and typeof(v) == "number" then return v end
	return 1
end

-- Tween that respects ReducedMotionEnabled — if motion is reduced, the tween
-- collapses to a 0-duration snap so state still advances but nothing slides.
function UI.tween(inst: Instance, info: TweenInfo, props: { [string]: any }): Tween
	if UI.isReducedMotion() then
		info = TweenInfo.new(
			0,
			info.EasingStyle,
			info.EasingDirection,
			0,
			false,
			0
		)
	end
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

-- Apply a PreferredTransparency-aware background transparency. Call once with
-- the desired "visible" transparency; this returns the effective value and
-- also sets BackgroundTransparency on the element.
function UI.applyBackgroundTransparency(frame: GuiObject, designTransparency: number)
	local factor = UI.getPreferredTransparency()
	local effective = math.clamp(designTransparency * factor, 0, 1)
	frame.BackgroundTransparency = effective
end

------------------------------------------------------------
-- Primitive factories. Every factory returns a Frame/Label/Button with the
-- project's theme already applied. Consumers only set size/position/content.
------------------------------------------------------------
function UI.newScreenGui(name: string, parent: Instance): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling   -- modular components
	gui.IgnoreGuiInset = false                         -- default: respect topbar
	-- ScreenInsets defaults to CoreUISafeInsets, which keeps UI clear of
	-- hardware notches AND the native topbar. That's what we want for
	-- interactive HUDs.
	gui.Parent = parent
	return gui
end

function UI.newPanel(name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = UI.Colors.Surface
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UI.Size.Corner
	corner.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Color = UI.Colors.Stroke
	stroke.Thickness = UI.Size.StrokeThick
	stroke.Transparency = 0.6
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = f
	return f
end

function UI.newLabel(text: string, size: number?, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = UI.Font.Bold
	l.TextSize = size or UI.TextSize.Baseline
	l.TextColor3 = color or UI.Colors.TextPrimary
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Text = text
	-- TextScaled is DELIBERATELY off — fixed size keeps sibling elements
	-- visually consistent and saves the per-frame recompute cost.
	return l
end

-- Primary action button. The visible rect is `visual`; the clickable rect is
-- padded out to `hitbox` so off-center taps still register (Fitts's Law).
-- Hover/press animation is delegated to UI.attachHoverFx so every button in
-- the codebase shares the same crisp motion (UIScale-driven, idempotent,
-- ReducedMotion-aware).
function UI.newButton(opts: {
	Text: string,
	Color: Color3?,
	TextColor: Color3?,
	Visual: Vector2?,      -- visible rect, defaults to TapButton
	Hitbox: Vector2?,      -- clickable rect, defaults to Visual + 24px
	TextSize: number?,
	Font: Enum.Font?,
}): (TextButton, Frame)
	local visual = opts.Visual or UI.Size.TapButton
	local hitbox = opts.Hitbox or Vector2.new(visual.X + 24, visual.Y + 20)
	-- Enforce 44x44 minimum tap target.
	hitbox = Vector2.new(math.max(hitbox.X, UI.Size.HitboxMin.X), math.max(hitbox.Y, UI.Size.HitboxMin.Y))

	-- Outer invisible hitbox.
	local outer = Instance.new("TextButton")
	outer.Text = ""
	outer.AutoButtonColor = false
	outer.BackgroundTransparency = 1
	outer.Size = UDim2.new(0, hitbox.X, 0, hitbox.Y)

	-- Inner visual rect.
	local inner = Instance.new("Frame")
	inner.Name = "Visual"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.new(0.5, 0, 0.5, 0)
	inner.Size = UDim2.new(0, visual.X, 0, visual.Y)
	inner.BackgroundColor3 = opts.Color or UI.Colors.SurfaceHot
	inner.BorderSizePixel = 0
	inner.Parent = outer
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UI.Size.CornerTight
	corner.Parent = inner
	local stroke = Instance.new("UIStroke")
	stroke.Color = UI.Colors.Stroke
	stroke.Thickness = 1
	stroke.Transparency = 0.4
	stroke.Parent = inner

	-- Only insert a label if Text is non-empty. Icon-only buttons (rail
	-- toggles, glide button once art lands) skip this and parent their
	-- own ImageLabel into `inner` instead.
	if opts.Text and opts.Text ~= "" then
		local label = UI.newLabel(opts.Text, opts.TextSize or UI.TextSize.Baseline, opts.TextColor or UI.Colors.TextPrimary)
		label.Size = UDim2.new(1, -12, 1, 0)
		label.Position = UDim2.new(0, 6, 0, 0)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.Font = opts.Font or UI.Font.Black
		label.Parent = inner
	end

	UI.attachHoverFx(outer, inner)
	return outer, inner
end

-- Returns an ImageLabel for `key` or nil if no asset is registered yet.
-- Use this when missing art should leave no layout slot at all (e.g. an
-- optional stat-row icon). For meaningful text fallbacks (a button label),
-- use UI.newIcon instead.
function UI.tryIcon(key: string, sizePx: number): ImageLabel?
	local id = Icons[key]
	if not id then return nil end
	local img = Instance.new("ImageLabel")
	img.Name = "Icon_" .. key
	img.BackgroundTransparency = 1
	img.Size = UDim2.new(0, sizePx, 0, sizePx)
	img.Image = id
	img.ScaleType = Enum.ScaleType.Fit
	return img
end

-- Returns a GuiObject sized `sizePx × sizePx`. If the icon key has a real
-- asset ID an ImageLabel is returned; otherwise a TextLabel showing the
-- fallback text (or the first 2 letters of the key) so layout doesn't shift
-- as art is added incrementally.
function UI.newIcon(key: string, sizePx: number, fallbackText: string?): GuiObject
	local id = Icons[key]
	if id then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon_" .. key
		img.BackgroundTransparency = 1
		img.Size = UDim2.new(0, sizePx, 0, sizePx)
		img.Image = id
		img.ScaleType = Enum.ScaleType.Fit
		return img
	end
	local txt = Instance.new("TextLabel")
	txt.Name = "IconFallback_" .. key
	txt.BackgroundTransparency = 1
	txt.Size = UDim2.new(0, sizePx, 0, sizePx)
	txt.Text = fallbackText or string.upper(string.sub(key, 1, 2))
	txt.TextColor3 = UI.Colors.TextMuted
	txt.Font = UI.Font.Black
	txt.TextScaled = true
	txt.TextWrapped = false
	return txt
end

-- Right-rail icon button. 88×88 visual rect (2× the small IconButton size),
-- 92×92 hitbox, real icon centered inside (or fallback text). Sized
-- generously because these are the primary nav buttons; smaller utility
-- buttons should use UI.newButton with a custom Visual instead.
function UI.newRailButton(opts: {
	Icon: string,
	Fallback: string?,
	Color: Color3?,
	IconSize: number?,
	Visual: Vector2?,   -- override if you want a non-rail-sized icon button
}): (TextButton, Frame)
	local visual = opts.Visual or Vector2.new(88, 88)
	local outer, inner = UI.newButton({
		Text = "",
		Color = opts.Color or UI.Colors.SurfaceHot,
		Visual = visual,
		Hitbox = Vector2.new(visual.X + 4, visual.Y + 4),
	})
	local icon = UI.newIcon(opts.Icon, opts.IconSize or math.floor(visual.X * 0.66), opts.Fallback)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.Parent = inner
	return outer, inner
end

-- Legacy-shape wrapper kept so older calls keep compiling. Prefer
-- newRailButton when adding new code so icon keys stay searchable.
function UI.newIconButton(textOrKey: string, color: Color3): (TextButton, Frame)
	if Icons[textOrKey] then
		return UI.newRailButton({ Icon = textOrKey, Color = color })
	end
	return UI.newButton({
		Text = textOrKey,
		Color = color,
		Visual = UI.Size.IconButton,
		Hitbox = Vector2.new(48, 48),
		TextSize = UI.TextSize.Micro,
		Font = UI.Font.Bold,
	})
end

------------------------------------------------------------
-- Motion helpers. Centralized so every button in the game shares the
-- exact same hover/press feel — change the timings here once and the
-- whole UI updates.
------------------------------------------------------------

-- Standard hover + press behavior driven by a single UIScale on the inner.
-- Tracks hover/press state independently so press-then-leave doesn't strand
-- the button at scale 0.94. Idempotent guard prevents double-attach.
function UI.attachHoverFx(outer: GuiButton, inner: GuiObject?)
	if outer:GetAttribute("HoverFxAttached") then return end
	outer:SetAttribute("HoverFxAttached", true)

	local target = inner or outer
	local scale = target:FindFirstChildWhichIsA("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Scale = 1
		scale.Parent = target
	end
	local stroke = target:FindFirstChildWhichIsA("UIStroke")
	local origStrokeT = stroke and stroke.Transparency or 0

	local hovered = false
	local pressed = false

	local function refresh()
		local s = 1.0
		if pressed then s = 0.94
		elseif hovered then s = 1.06 end
		UI.tween(scale, TweenInfo.new(
			pressed and 0.06 or 0.16,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		), { Scale = s })
		if stroke then
			UI.tween(stroke, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = (hovered or pressed) and math.max(0, origStrokeT - 0.4) or origStrokeT,
			})
		end
	end

	outer.MouseEnter:Connect(function() hovered = true; refresh() end)
	outer.MouseLeave:Connect(function() hovered = false; pressed = false; refresh() end)
	outer.MouseButton1Down:Connect(function() pressed = true; refresh() end)
	outer.MouseButton1Up:Connect(function() pressed = false; refresh() end)
end

------------------------------------------------------------
-- 3D candy button — the chunky lifted-shadow style players associate
-- with simulator games. Lifted from flip-a-coin-for-brainrots'
-- make3DButton helper. Returns (button, container, shadow):
--   * button     — the TextButton you wire input to
--   * container  — the outer Frame, set its Position/AnchorPoint
--   * shadow     — the dark Frame underneath (recolor it together with
--                  the button when state-swapping, otherwise the lift
--                  effect breaks)
------------------------------------------------------------
function UI.new3DButton(opts: {
	Parent: Instance?,
	Text: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	TopColor: Color3?,
	BottomColor: Color3?,
	Mobile: boolean?,
	Font: Enum.Font?,
	TextSize: number?,
}): (TextButton, Frame, Frame)
	local mobile = opts.Mobile
	if mobile == nil then mobile = UI.isTouch() end

	local SHADOW_LIFT = mobile and 4 or 8
	local BTN_INSET   = mobile and 4 or 8
	local PRESS_DROP  = mobile and 2 or 5
	local CORNER_BTN  = mobile and 10 or 16
	local CORNER_SHINE = mobile and 8 or 12

	local container = Instance.new("Frame")
	container.Name = "Button3D"
	container.Size = opts.Size or UDim2.new(0, 200, 0, 80)
	container.Position = opts.Position or UDim2.new(0.5, 0, 0.5, 0)
	container.AnchorPoint = opts.AnchorPoint or Vector2.new(0, 0)
	container.BackgroundTransparency = 1
	if opts.Parent then container.Parent = opts.Parent end

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.Size = UDim2.new(1, 0, 1, -BTN_INSET / 2)
	shadow.Position = UDim2.new(0, 0, 0, SHADOW_LIFT)
	shadow.BackgroundColor3 = opts.BottomColor or Color3.fromRGB(20, 140, 20)
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 1
	shadow.Parent = container
	local shadowCorner = Instance.new("UICorner"); shadowCorner.CornerRadius = UDim.new(0, CORNER_BTN); shadowCorner.Parent = shadow

	local btn = Instance.new("TextButton")
	btn.Name = "Button"
	btn.Size = UDim2.new(1, 0, 1, -BTN_INSET)
	btn.Position = UDim2.new(0, 0, 0, 0)
	btn.BackgroundColor3 = opts.TopColor or Color3.fromRGB(40, 200, 40)
	btn.Text = opts.Text or ""
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.TextScaled = (opts.TextSize == nil)
	if opts.TextSize then btn.TextSize = opts.TextSize end
	btn.Font = opts.Font or Enum.Font.FredokaOne
	btn.TextStrokeTransparency = 0
	btn.TextStrokeColor3 = Color3.new(0, 0, 0)
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.ZIndex = 2
	btn.Parent = container
	local btnCorner = Instance.new("UICorner"); btnCorner.CornerRadius = UDim.new(0, CORNER_BTN); btnCorner.Parent = btn

	-- White semi-transparent shine along the top — the "candy gloss".
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.Size = UDim2.new(1, -10, 0.4, 0)
	shine.Position = UDim2.new(0, 5, 0, 3)
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.85
	shine.BorderSizePixel = 0
	shine.Active = false
	shine.ZIndex = 3
	shine.Parent = btn
	local shineCorner = Instance.new("UICorner"); shineCorner.CornerRadius = UDim.new(0, CORNER_SHINE); shineCorner.Parent = shine

	-- Subtle stud texture overlay (the dotted Roblox-stud pattern).
	StudsUI.apply(btn, CORNER_BTN)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 4)
	padding.Parent = btn

	-- Press: button drops + shrinks, springs back with Back ease-out.
	-- Bypass UI.tween here because we want the spring even when
	-- ReducedMotion is on (this is the affordance, not eye candy).
	btn.MouseButton1Down:Connect(function()
		UI.clickBurst(btn)
		TweenService:Create(btn, TweenInfo.new(0.05), {
			Position = UDim2.new(0, 0, 0, PRESS_DROP),
			Size = UDim2.new(1, 0, 1, -(BTN_INSET + PRESS_DROP)),
		}):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, 0, 0, 0),
			Size = UDim2.new(1, 0, 1, -BTN_INSET),
		}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.1), {
			Position = UDim2.new(0, 0, 0, 0),
			Size = UDim2.new(1, 0, 1, -BTN_INSET),
		}):Play()
	end)

	return btn, container, shadow
end

-- Click-burst: 2 expanding white rings + 6 colored sparks shooting outward
-- from the button's center. Lifted verbatim from the flip-a-coin source so
-- the timing matches Owen's reference. Suppressed under ReducedMotion.
function UI.clickBurst(btn: GuiObject)
	if UI.isReducedMotion() then return end
	for r = 1, 2 do
		local ring = Instance.new("Frame")
		ring.Size = UDim2.new(0, 10, 0, 10)
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.new(0.5, 0, 0.5, 0)
		ring.BackgroundTransparency = 1
		ring.BorderSizePixel = 0
		ring.ZIndex = 4
		ring.Parent = btn
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1, 0); rc.Parent = ring
		local ringStroke = Instance.new("UIStroke")
		ringStroke.Thickness = 3
		ringStroke.Color = Color3.new(1, 1, 1)
		ringStroke.Transparency = 0.3
		ringStroke.Parent = ring
		TweenService:Create(ring, TweenInfo.new(0.4 + r * 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 120, 0, 120),
		}):Play()
		TweenService:Create(ringStroke, TweenInfo.new(0.4 + r * 0.1), { Transparency = 1 }):Play()
		task.delay(0.5 + r * 0.1, function() ring:Destroy() end)
	end
	for p = 1, 6 do
		local spark = Instance.new("Frame")
		spark.Size = UDim2.new(0, 8, 0, 8)
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.Position = UDim2.new(0.5, 0, 0.5, 0)
		spark.BackgroundColor3 = Color3.fromRGB(255, 255, math.random(100, 255))
		spark.BorderSizePixel = 0
		spark.ZIndex = 4
		spark.Parent = btn
		local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(1, 0); sc.Parent = spark
		local angle = (p / 6) * math.pi * 2 + math.random() * 0.5
		local dist = math.random(40, 80)
		TweenService:Create(spark, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5 + math.cos(angle) * dist / 100, 0, 0.5 + math.sin(angle) * dist / 100, 0),
			Size = UDim2.new(0, 3, 0, 3),
			BackgroundTransparency = 1,
		}):Play()
		task.delay(0.4, function() spark:Destroy() end)
	end
end

-- Slide-up + fade-in entrance. Call after parenting the frame to its
-- ScreenGui. Cheap (one tween) and ReducedMotion-safe.
function UI.attachAppearFx(frame: GuiObject, options: { fromYOffset: number?, duration: number?, delay: number? }?)
	if UI.isReducedMotion() then return end
	options = options or {}
	local fromY = options.fromYOffset or 8
	local dur = options.duration or 0.22
	local delay = options.delay or 0

	local origPos = frame.Position
	local origBgT = frame.BackgroundTransparency
	frame.Position = origPos + UDim2.fromOffset(0, fromY)
	frame.BackgroundTransparency = 1

	task.delay(delay, function()
		if not frame.Parent then return end
		UI.tween(frame,
			TweenInfo.new(dur, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Position = origPos, BackgroundTransparency = origBgT })
	end)
end

------------------------------------------------------------
-- Layout helpers
------------------------------------------------------------
function UI.addVerticalList(parent: GuiObject, padding: number?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, padding or UI.Size.Gutter)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
	return l
end

function UI.addHorizontalList(parent: GuiObject, padding: number?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, padding or UI.Size.Gutter)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
	return l
end

function UI.addPadding(parent: GuiObject, px: number): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingTop    = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft   = UDim.new(0, px)
	p.PaddingRight  = UDim.new(0, px)
	p.Parent = parent
	return p
end

------------------------------------------------------------
-- Device detection — used to bias layout (mobile = build around native
-- Roblox jump thumbstick zone; desktop = free reign on bottom corners).
------------------------------------------------------------
function UI.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

return UI
