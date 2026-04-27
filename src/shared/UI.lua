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

-- Right-rail icon button. 44×44 visual rect, 48×48 hitbox, real icon
-- centered inside (or fallback text). Drop-in replacement for the
-- previous text-only newIconButton.
function UI.newRailButton(opts: {
	Icon: string,
	Fallback: string?,
	Color: Color3?,
	IconSize: number?,
}): (TextButton, Frame)
	local outer, inner = UI.newButton({
		Text = "",
		Color = opts.Color or UI.Colors.SurfaceHot,
		Visual = UI.Size.IconButton,
		Hitbox = Vector2.new(48, 48),
	})
	local icon = UI.newIcon(opts.Icon, opts.IconSize or 28, opts.Fallback)
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
