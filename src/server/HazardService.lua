--!strict
-- HazardService.lua
-- Scans workspace.Map for tagged parts and wires up their behavior.
-- This keeps MapBuilder's job small (just place parts + set attributes),
-- while all the dynamic behavior lives here in one place.

local RunService = game:GetService("RunService")
local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local HazardService = {}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function getPlayerFromHit(hit: BasePart): (Player?, Humanoid?, BasePart?)
	local char = hit.Parent
	if not char then return nil, nil, nil end
	local humanoid = char:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then return nil, nil, nil end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local player = Players:GetPlayerFromCharacter(char)
	return player, humanoid, hrp
end

------------------------------------------------------------
-- Fading leaf — touch it, it colors from green to brown over 3 seconds, then drops.
-- After 6 seconds it respawns.
------------------------------------------------------------
local function bindFadingLeaf(part: BasePart)
	local originalColor = part.Color
	local originalTransparency = part.Transparency
	local originalCanCollide = part.CanCollide
	local triggered = false

	part.Touched:Connect(function(hit)
		if triggered then return end
		local _, humanoid = getPlayerFromHit(hit)
		if not humanoid or humanoid.Health <= 0 then return end
		triggered = true

		-- Color tween: green -> brown.
		local tween = TweenService:Create(part, TweenInfo.new(3, Enum.EasingStyle.Linear), {
			Color = Color3.fromRGB(120, 80, 40),
		})
		tween:Play()

		task.delay(3, function()
			-- Drop.
			part.Transparency = 1
			part.CanCollide = false
			task.delay(3, function()
				-- Respawn.
				part.Color = originalColor
				part.Transparency = originalTransparency
				part.CanCollide = originalCanCollide
				triggered = false
			end)
		end)
	end)
end

------------------------------------------------------------
-- Pendulum — CFrame-driven swinging log.
-- Attributes: PivotX, PivotY, PivotZ, ArmLength, Period, PhaseOffset
------------------------------------------------------------
local pendulums: { BasePart } = {}

local function bindPendulum(part: BasePart)
	table.insert(pendulums, part)

	-- Kill-on-touch behavior for the log.
	part.Touched:Connect(function(hit)
		local _, humanoid = getPlayerFromHit(hit)
		if humanoid and humanoid.Health > 0 then
			humanoid:TakeDamage(humanoid.MaxHealth) -- instant kill
		end
	end)
end

------------------------------------------------------------
-- Sap conveyor — pulls the player downward and slightly inward via AssemblyLinearVelocity.
-- Players must jump off to escape.
------------------------------------------------------------
local function bindSapConveyor(part: BasePart)
	-- Visual: gentle transparency pulse so it looks like flowing sap.
	task.spawn(function()
		local t = 0
		while part.Parent do
			t += RunService.Heartbeat:Wait()
			part.Transparency = 0.2 + 0.1 * math.sin(t * 3)
		end
	end)

	part.Touched:Connect(function(hit)
		local _, _, hrp = getPlayerFromHit(hit)
		if not hrp then return end
		-- Pull downward (sliding sap).
		local cur = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(cur.X * 0.4, -50, cur.Z * 0.4)
	end)
end

------------------------------------------------------------
-- Spore beam — rotates around the tree's central axis on a scripted timer.
-- Kills on touch. Attribute SpinSpeed (radians/sec).
------------------------------------------------------------
local sporeBeams: { BasePart } = {}

local function bindSporeBeam(part: BasePart)
	table.insert(sporeBeams, part)
	part.Touched:Connect(function(hit)
		local _, humanoid = getPlayerFromHit(hit)
		if humanoid and humanoid.Health > 0 then
			humanoid:TakeDamage(humanoid.MaxHealth)
		end
	end)
end

------------------------------------------------------------
-- Bounce pad — springs the player upward on touch.
-- Chain-jump replacement for the wallhop sequence.
------------------------------------------------------------
local function bindBouncePad(part: BasePart)
	part.Touched:Connect(function(hit)
		local _, _, hrp = getPlayerFromHit(hit)
		if not hrp then return end
		-- Preserve horizontal, boost upward.
		local v = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(v.X, 90, v.Z)
	end)
end

------------------------------------------------------------
-- Speed pad — adds horizontal momentum in the direction the player is moving.
------------------------------------------------------------
local function bindSpeedPad(part: BasePart)
	part.Touched:Connect(function(hit)
		local _, humanoid, hrp = getPlayerFromHit(hit)
		if not hrp or not humanoid then return end
		local look = humanoid.MoveDirection
		if look.Magnitude < 0.1 then
			look = hrp.CFrame.LookVector
		end
		look = Vector3.new(look.X, 0, look.Z)
		if look.Magnitude < 0.01 then return end
		look = look.Unit
		hrp.AssemblyLinearVelocity = Vector3.new(look.X * 120, 70, look.Z * 120)
	end)
end

------------------------------------------------------------
-- Kill brick (hidden trap) — simple damage-on-touch.
------------------------------------------------------------
local function bindKillBrick(part: BasePart)
	part.Touched:Connect(function(hit)
		local _, humanoid = getPlayerFromHit(hit)
		if humanoid and humanoid.Health > 0 then
			humanoid:TakeDamage(humanoid.MaxHealth)
		end
	end)
end

------------------------------------------------------------
-- Pendulum + spore-beam Heartbeat loop
-- One loop updates all active CFrame-driven hazards deterministically.
------------------------------------------------------------
local function startHazardLoop()
	local startTime = os.clock()
	RunService.Heartbeat:Connect(function()
		local t = os.clock() - startTime

		-- Pendulums
		for _, p in ipairs(pendulums) do
			if not p.Parent then continue end
			local pivot = Vector3.new(
				p:GetAttribute("PivotX") or 0,
				p:GetAttribute("PivotY") or 0,
				p:GetAttribute("PivotZ") or 0
			)
			local arm = p:GetAttribute("ArmLength") or 10
			local period = p:GetAttribute("Period") or 2
			local phase = p:GetAttribute("PhaseOffset") or 0
			local angle = math.sin((t / period) * math.pi * 2 + phase) * math.rad(55)
			-- Swing in the X-Y plane relative to pivot.
			local offset = Vector3.new(math.sin(angle) * arm, -math.cos(angle) * arm, 0)
			p.CFrame = CFrame.new(pivot + offset) * CFrame.Angles(0, 0, angle)
		end

		-- Spore beams rotate around the tree's Y axis.
		for _, b in ipairs(sporeBeams) do
			if not b.Parent then continue end
			local spin = b:GetAttribute("SpinSpeed") or 1
			local center = Vector3.new(0, b.Position.Y, 0)
			local angle = t * spin
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle))
			b.CFrame = CFrame.new(center + offset * (b.Size.X / 2)) * CFrame.Angles(0, angle + math.pi / 2, 0)
		end
	end)
end

------------------------------------------------------------
-- Public
------------------------------------------------------------
function HazardService.init()
	local map = Workspace:WaitForChild("Map")

	local function wireIfTagged(part: Instance)
		if not part:IsA("BasePart") then return end
		if part:GetAttribute("FadingLeaf")  then bindFadingLeaf(part) end
		if part:GetAttribute("Pendulum")    then bindPendulum(part) end
		if part:GetAttribute("SapConveyor") then bindSapConveyor(part) end
		if part:GetAttribute("SporeBeam")   then bindSporeBeam(part) end
		if part:GetAttribute("BouncePad")   then bindBouncePad(part) end
		if part:GetAttribute("SpeedPad")    then bindSpeedPad(part) end
		if part:GetAttribute("IsKillBrick") then bindKillBrick(part) end
	end

	for _, descendant in ipairs(map:GetDescendants()) do
		wireIfTagged(descendant)
	end
	map.DescendantAdded:Connect(wireIfTagged)

	startHazardLoop()
	print("[HazardService] Wired up. pendulums=" .. #pendulums, "sporeBeams=" .. #sporeBeams)
end

return HazardService
