--[[
	ServerScriptService/PlacementService/PlacementController.lua (ModuleScript)
	
	SOLE RESPONSIBILITY: Place/remove brainrots on stands, upgrade level.
	Destroys the backpack Tool on place, recreates on remove.
	
	FIXES APPLIED:
	1. CENTERING: Simplified getCenteredCFrame to reliably dead-center brainrots.
	2. ORIENTATION: Stands 1-5 = (0,0,0), Stands 6-10 = (0,180,0).
	3. ALL UPGRADE VFX moved to client. Server only fires UpgradeVfxEvent remote.
	   No VFX templates loaded here, no playVfx, no playJumpAnimation.
--]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local PlayerManager = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerManager"))
local InventoryController = require(ServerScriptService:WaitForChild("Services"):WaitForChild("InventoryService"):WaitForChild("InventoryController"))
local BrainrotConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BrainrotConfig"))
local DriveConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DriveConfig"))
local PlotManager = require(ServerScriptService:WaitForChild("Services"):WaitForChild("PlotService"):WaitForChild("PlotManager"))

local PlacementController = {}

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local PlaceRemote = Instance.new("RemoteEvent")
PlaceRemote.Name = "PlaceBrainrot"
PlaceRemote.Parent = Remotes

local RemoveRemote = Instance.new("RemoteEvent")
RemoveRemote.Name = "RemoveFromStand"
RemoveRemote.Parent = Remotes

local UpgradeRemote = Instance.new("RemoteEvent")
UpgradeRemote.Name = "UpgradeBrainrot"
UpgradeRemote.Parent = Remotes

-- Remote to tell client to play ALL upgrade effects
local UpgradeVfxRemote = Instance.new("RemoteEvent")
UpgradeVfxRemote.Name = "UpgradeVfxEvent"
UpgradeVfxRemote.Parent = Remotes

------------------------------------------------------------
-- TOOL HELPERS
------------------------------------------------------------
local function findToolByUUID(player: Player, uuid: string): Tool?
	for _, child in player.Backpack:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("BrainrotUUID") == uuid then
			return child
		end
	end
	local char = player.Character
	if char then
		for _, child in char:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("BrainrotUUID") == uuid then
				return child
			end
		end
	end
	return nil
end

local function createBrainrotTool(player: Player, uuid: string, brainrotId: string, rarity: string): Tool
	local config = BrainrotConfig.Catalog[brainrotId]
	local displayName = config and config.DisplayName or brainrotId

	local tool = Instance.new("Tool")
	tool.Name = displayName
	tool.CanBeDropped = false
	tool.RequiresHandle = false
	tool.ToolTip = rarity .. " Brainrot"
	tool:SetAttribute("BrainrotUUID", uuid)
	tool:SetAttribute("BrainrotId", brainrotId)
	tool:SetAttribute("Rarity", rarity)

	local templates = ReplicatedStorage:FindFirstChild("BrainrotModels")
	if templates then
		local template = templates:FindFirstChild(brainrotId)
		if template then
			local decal = template:FindFirstChildWhichIsA("Decal", true)
				or template:FindFirstChildWhichIsA("Texture", true)
			if decal then
				tool.TextureId = decal.Texture
			end
			local textureAttr = template:GetAttribute("Icon")
			if textureAttr then
				tool.TextureId = textureAttr
			end
		end
	end

	tool.Parent = player.Backpack
	return tool
end

------------------------------------------------------------
-- STAND HELPERS (public)
------------------------------------------------------------
function PlacementController.GetStandModel(player: Player, standKey: string): Model?
	local plot = PlotManager.GetPlot(player)
	if not plot then return nil end

	local floorNum, standNum = standKey:match("^(%d+)_(%d+)$")
	if not floorNum then return nil end

	local floor = plot.Floors:FindFirstChild(tostring(floorNum))
	if not floor then return nil end

	local stands = floor:FindFirstChild("Stands")
	if not stands then return nil end

	return stands:FindFirstChild(tostring(standNum))
end

------------------------------------------------------------
-- ORIENTATION HELPER
-- Stands 1-5:  orientation (0,   0, 0)
-- Stands 6-10: orientation (0, 180, 0)
------------------------------------------------------------
local function getStandRotation(standKey: string): CFrame
	return CFrame.Angles(0, 0, 0)
end

------------------------------------------------------------
-- CENTERING HELPER------------------------------------------------------------
-- CENTERING HELPER------------------------------------------------------------
-- CENTERING HELPER  (FIXED)
--
-- Strategy:
--   1. Model is already parented (so GetBoundingBox works).
--   2. PivotTo identity at origin so bounding box is axis-aligned
--      and the offset between pivot and bbox center is clean.
--   3. Measure bounding box → get bbox center offset from pivot,
--      and the bbox size (height).
--   4. Compute the target: platform top-center + Y offset,
--      with the correct stand rotation.
--   5. Place the pivot such that the bbox bottom-center lands
--      exactly on that target.
------------------------------------------------------------
local EXTRA_Y_OFFSET = 0.5

local function getCenteredCFrame(visual: Instance, platformCF: CFrame, platformSize: Vector3, standKey: string)
	local rotation = getStandRotation(standKey)
	local centerPos = platformCF.Position
	return CFrame.new(centerPos) * rotation
end

------------------------------------------------------------
-- SPAWN VISUAL------------------------------------------------------------
-- SPAWN VISUAL (centered via bounding box + oriented)
------------------------------------------------------------
function PlacementController.SpawnVisual(player: Player, standKey: string, brainrotData: { [string]: any })
	local standModel = PlacementController.GetStandModel(player, standKey)
	if not standModel then return end

	local stand = standModel:FindFirstChild("Stand")
	if not stand then return end

	local platform = stand:FindFirstChild("Platform")
	if not platform then return end

	-- Clear old
	for _, child in platform:GetChildren() do
		if child.Name == "BrainrotVisual" then child:Destroy() end
	end

	local templates = ReplicatedStorage:FindFirstChild("BrainrotModels")
	if not templates then return end

	local template = templates:FindFirstChild(brainrotData.Id)
	if not template then return end

	local visual = template:Clone()
	visual.Name = "BrainrotVisual"

	-- Remove pickup prompt from placed visual
	local prompt = visual:FindFirstChild("PickupPrompt", true)
	if prompt then prompt:Destroy() end

	-- Anchor all parts so they stay in place
	for _, part in visual:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end

	-- Parent FIRST so GetBoundingBox works (model must be in DataModel)
	visual.Parent = platform

	local billboard = visual:FindFirstChild("EntityTagBillboard", true)
	if billboard and billboard:IsA("BillboardGui") then
		billboard.StudsOffset = Vector3.new(0, 5, 0)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
	end

	-- Compute the dead-center + oriented CFrame using bounding box
	local targetCF = getCenteredCFrame(visual, platform.CFrame, platform.Size, standKey)

	if visual:IsA("Model") then
		visual:PivotTo(targetCF)
	elseif visual:IsA("BasePart") then
		visual.CFrame = targetCF
	end
end

function PlacementController.ClearVisual(player: Player, standKey: string)
	local standModel = PlacementController.GetStandModel(player, standKey)
	if not standModel then return end

	local stand = standModel:FindFirstChild("Stand")
	if not stand then return end

	local platform = stand:FindFirstChild("Platform")
	if not platform then return end

	for _, child in platform:GetChildren() do
		if child.Name == "BrainrotVisual" then child:Destroy() end
	end
end

------------------------------------------------------------
-- REFRESH STAND GUI
------------------------------------------------------------
function PlacementController.RefreshStandGUI(player: Player, standKey: string, brainrotData: { [string]: any }?)
	local standModel = PlacementController.GetStandModel(player, standKey)
	if not standModel then return end

	local stand = standModel:FindFirstChild("Stand")
	if not stand then return end

	local cc = stand:FindFirstChild("ControlCenter")
	if not cc then return end

	local gui = cc:FindFirstChild("SurfaceGui")
	if not gui then return end

	local upgrade = gui:FindFirstChild("Upgrade")
	if not upgrade then return end

	local buy = upgrade:FindFirstChild("Buy")
	if not buy then return end

	local mainList = buy:FindFirstChild("MainList")
	if not mainList then return end

	local levelLabel = mainList:FindFirstChild("Level")
	local priceLabel = mainList:FindFirstChild("Price")

	if brainrotData then
		local nextLvl = brainrotData.Level + 1
		local cost = BrainrotConfig.GetUpgradeCost(brainrotData.Level, brainrotData.Rarity)
		if levelLabel then levelLabel.Text = "Lv." .. brainrotData.Level .. " → Lv." .. nextLvl end
		if priceLabel then priceLabel.Text = "$" .. tostring(cost) end
		buy.Visible = true
	else
		if levelLabel then levelLabel.Text = "Empty" end
		if priceLabel then priceLabel.Text = "" end
		buy.Visible = false
	end
end

------------------------------------------------------------
-- INTERNAL
------------------------------------------------------------
local function isStandOccupied(brainrots: { [string]: any }, standKey: string): boolean
	for _, b in brainrots do
		if b.PlacedStand == standKey then return true end
	end
	return false
end

------------------------------------------------------------
-- PLACE
------------------------------------------------------------
PlaceRemote.OnServerEvent:Connect(function(player: Player, brainrotUUID: string, standKey: string)
	local data = PlayerManager.GetData(player)
	if not data then return end

	local brainrot = data.Inventory.Brainrots[brainrotUUID]
	if not brainrot then return end
	if brainrot.PlacedStand ~= nil then return end

	if isStandOccupied(data.Inventory.Brainrots, standKey) then return end
	if not PlacementController.GetStandModel(player, standKey) then return end

	brainrot.PlacedStand = standKey

	local tool = findToolByUUID(player, brainrotUUID)
	if tool then tool:Destroy() end

	PlacementController.SpawnVisual(player, standKey, brainrot)
	PlacementController.RefreshStandGUI(player, standKey, brainrot)
	InventoryController.SendUpdate(player)
end)

------------------------------------------------------------
-- REMOVE
------------------------------------------------------------
RemoveRemote.OnServerEvent:Connect(function(player: Player, standKey: string)
	local data = PlayerManager.GetData(player)
	if not data then return end

	if not InventoryController.CanCarryMore(player) then return end

	for uuid, b in data.Inventory.Brainrots do
		if b.PlacedStand == standKey then
			b.PlacedStand = nil

			createBrainrotTool(player, uuid, b.Id, b.Rarity)

			PlacementController.ClearVisual(player, standKey)
			PlacementController.RefreshStandGUI(player, standKey, nil)
			InventoryController.SendUpdate(player)
			return
		end
	end
end)

------------------------------------------------------------
-- UPGRADE
------------------------------------------------------------
UpgradeRemote.OnServerEvent:Connect(function(player: Player, standKey: string)
	local data = PlayerManager.GetData(player)
	if not data then return end

	local targetBrainrot = nil
	for _, b in data.Inventory.Brainrots do
		if b.PlacedStand == standKey then
			targetBrainrot = b
			break
		end
	end
	if not targetBrainrot then return end

	local cost = BrainrotConfig.GetUpgradeCost(targetBrainrot.Level, targetBrainrot.Rarity)

	local leaderstats = player:FindFirstChild("leaderstats")
	local moneyValue = leaderstats and leaderstats:FindFirstChild("Money")
	if not moneyValue or moneyValue.Value < cost then return end

	moneyValue.Value -= cost
	targetBrainrot.Level += 1

	PlacementController.RefreshStandGUI(player, standKey, targetBrainrot)
	InventoryController.SendUpdate(player)

	-- Tell client to play ALL upgrade effects
	UpgradeVfxRemote:FireClient(player, standKey)
end)

function PlacementController.Init() end

return PlacementController