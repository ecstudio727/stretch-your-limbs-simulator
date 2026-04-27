--!strict
-- Icons.lua
-- OWNER: OWEN.
--
-- Single source of truth for Roblox asset IDs used across the UI. Add a
-- key here and every screen that asks for it via `UI.newIcon(key, size)`
-- updates automatically. Missing keys fall back to a text badge so layouts
-- never break while art is being finalized.
--
-- Naming convention: PascalCase semantic name (what it represents), NOT
-- where it's used. The same icon can appear in multiple screens — that's
-- the whole point of this file.

local Icons = {
	-- Live icons (Owen-uploaded).
	Coin        = "rbxassetid://83766242709001",
	Rebirth     = "rbxassetid://121056119578624",
	Shop        = "rbxassetid://99023558124680",
	Skip        = "rbxassetid://114259531580832",
	Leaderboard = "rbxassetid://117691718999215",

	-- Reserved keys — drop the rbxassetid string in when ready and the UI
	-- will pick it up on next play. Listed here so the placement map and
	-- Owen-Ruben handoff stay aligned.
	-- BestGlide   = "rbxassetid://...",
	-- Wingspan    = "rbxassetid://...",
	-- JumpPower   = "rbxassetid://...",
	-- WalkSpeed   = "rbxassetid://...",
	-- Objective   = "rbxassetid://...",
	-- Glide       = "rbxassetid://...",
	-- Wing        = "rbxassetid://...",
	-- Pet         = "rbxassetid://...",
	-- Checkpoint  = "rbxassetid://...",
	-- Settings    = "rbxassetid://...",
	-- Notify      = "rbxassetid://...",
}

return Icons
