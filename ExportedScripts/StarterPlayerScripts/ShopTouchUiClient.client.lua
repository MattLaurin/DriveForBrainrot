local Players = game:GetService("Players")
local player = Players.LocalPlayer

local TOUCH_COOLDOWN = 0.6
local lastTouchAt = 0

local SHOP_TO_FRAME = {
	CarShop = "ItemShopFrame",
	CarryShop = "UpgradesFrame",
	FuelShop = "UpgradesFrame",
	SellShop = "SellShop",
}

local function isFromLocalCharacter(part: BasePart): boolean
	local character = player.Character
	if not character then return false end
	return part:IsDescendantOf(character)
end

local function getPlayerGui(): PlayerGui?
	return player:FindFirstChildOfClass("PlayerGui")
end

local function openFrame(frameName: string)
	local playerGui = getPlayerGui()
	if not playerGui then return end

	local target: GuiObject? = nil
	for _, inst in playerGui:GetDescendants() do
		if inst:IsA("GuiObject") and inst.Name == frameName then
			target = inst
			break
		end
	end
	if not target then return end

	-- Ensure all parent ScreenGuis are enabled.
	local ancestor = target.Parent
	while ancestor do
		if ancestor:IsA("ScreenGui") then
			ancestor.Enabled = true
		end
		ancestor = ancestor.Parent
	end

	target.Visible = true
end

local function onTouched(otherPart: BasePart, frameName: string)
	if not isFromLocalCharacter(otherPart) then return end

	local now = os.clock()
	if (now - lastTouchAt) < TOUCH_COOLDOWN then
		return
	end
	lastTouchAt = now

	openFrame(frameName)
end

local function bindMiscModel(miscModel: Instance, frameName: string)
	local function bindPart(part: Instance)
		if part:IsA("BasePart") then
			part.Touched:Connect(function(other)
				onTouched(other, frameName)
			end)
		end
	end

	for _, d in miscModel:GetDescendants() do
		bindPart(d)
	end

	miscModel.DescendantAdded:Connect(bindPart)
end

local function setup()
	local world = workspace:WaitForChild("World")
	local shops = world:WaitForChild("Shops")

	for shopName, frameName in SHOP_TO_FRAME do
		local shopModel = shops:FindFirstChild(shopName)
		if shopModel then
			local misc = shopModel:FindFirstChild("Misc")
			if misc then
				bindMiscModel(misc, frameName)
			end
		end
	end
end

setup()
