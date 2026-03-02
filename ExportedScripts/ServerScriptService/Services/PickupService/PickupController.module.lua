--[[
	ServerScriptService/PickupService/PickupController.lua (ModuleScript)
	
	SOLE RESPONSIBILITY: Player picks up world brainrot -> inventory data + Tool in Backpack.
--]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local InventoryController = require(
	ServerScriptService:WaitForChild("Services"):WaitForChild("InventoryService"):WaitForChild("InventoryController")
)
local BrainrotConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BrainrotConfig"))
local IndexService = require(
	ServerScriptService:WaitForChild("Services"):WaitForChild("IndexService"):WaitForChild("IndexService")
)

local PickupController = {}

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local PickupRemote = Instance.new("RemoteEvent")
PickupRemote.Name = "PickupBrainrot"
PickupRemote.Parent = Remotes

------------------------------------------------------------
-- CREATE TOOL FOR SATCHEL
------------------------------------------------------------
local function createBrainrotTool(player: Player, uuid: string, brainrotId: string, rarity: string): Tool
	local config = BrainrotConfig.Catalog[brainrotId]
	local displayName = config and config.DisplayName or brainrotId

	local tool = Instance.new("Tool")
	tool.Name = displayName
	tool.CanBeDropped = false
	tool.RequiresHandle = false
	tool.ToolTip = rarity .. " Brainrot"

	-- Store the UUID so we can link it back to inventory data
	tool:SetAttribute("BrainrotUUID", uuid)
	tool:SetAttribute("BrainrotId", brainrotId)
	tool:SetAttribute("Rarity", rarity)

	-- Set icon from BrainrotModels template if it has a decal/texture
	local templates = ReplicatedStorage:FindFirstChild("BrainrotModels")
	if templates then
		local template = templates:FindFirstChild(brainrotId)
		if template then
			local decal = template:FindFirstChildWhichIsA("Decal", true)
				or template:FindFirstChildWhichIsA("Texture", true)
			if decal then
				tool.TextureId = decal.Texture
			end

			-- Also check for a TextureId attribute on the template
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
-- PICKUP HANDLER
------------------------------------------------------------
PickupRemote.OnServerEvent:Connect(function(player: Player, brainrotModel: Instance)
	if not brainrotModel or not brainrotModel:IsA("Model") then return end
	if not brainrotModel:IsDescendantOf(workspace) then return end
	if brainrotModel:GetAttribute("PickedUp") then return end

	local brainrotId = brainrotModel:GetAttribute("BrainrotId")
	if not brainrotId then return end

	local rarity = brainrotModel:GetAttribute("Rarity") or "Common"
	local mutation = brainrotModel:GetAttribute("Mutation")

	if not BrainrotConfig.IsValidBrainrot(brainrotId) then
		warn("[PickupController] Unknown brainrot:", brainrotId)
		return
	end

	brainrotModel:SetAttribute("PickedUp", true)

	local uuid = InventoryController.AddBrainrot(player, brainrotId, rarity, mutation)

	if uuid then
		print("[Pickup]", player.Name, "picked up", brainrotId, "(" .. rarity .. ") UUID:", uuid)
		createBrainrotTool(player, uuid, brainrotId, rarity)
		IndexService.MarkSeen(player, brainrotId)
		brainrotModel:Destroy()
	else
		print("[Pickup]", player.Name, "FAILED to pick up", brainrotId, "- inventory full")
		brainrotModel:SetAttribute("PickedUp", false)
	end
end)

------------------------------------------------------------
-- RESTORE TOOLS ON JOIN (for brainrots already in inventory but not placed)
------------------------------------------------------------
function PickupController.RestoreTools(player: Player)
	local data = InventoryController.GetAllBrainrots(player)
	for uuid, brainrot in data do
		if brainrot.PlacedStand == nil then
			createBrainrotTool(player, uuid, brainrot.Id, brainrot.Rarity)
		end
	end
end

function PickupController.Init() end

return PickupController
