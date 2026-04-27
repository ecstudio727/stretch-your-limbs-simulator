--!strict
-- StudsUI.lua
-- OWNER: OWEN.
--
-- Tiny helper that overlays the classic Roblox-stud tile texture onto any
-- GUI element. Used by the 3D candy buttons (UI.new3DButton) so they get
-- that subtle gloss-and-grit pattern players associate with Pet Simulator-
-- adjacent UI. Lifted from the flip-a-coin-for-brainrots project so the
-- visual matches Owen's reference exactly.

local StudsUI = {}

function StudsUI.apply(guiObject: GuiObject, cornerRadius: number?): ImageLabel
	local studs = Instance.new("ImageLabel")
	studs.Name = "StudTexture"
	studs.Size = UDim2.new(1, 0, 1, 0)
	studs.BackgroundTransparency = 1
	studs.Image = "rbxassetid://137014639625779"
	studs.ScaleType = Enum.ScaleType.Tile
	studs.TileSize = UDim2.new(0, 50, 0, 50)
	studs.ImageTransparency = 0.55
	studs.ImageColor3 = Color3.new(1, 1, 1)
	studs.Active = false
	studs.ZIndex = 0
	studs.Parent = guiObject

	if cornerRadius then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, cornerRadius)
		c.Parent = studs
	end

	return studs
end

return StudsUI
