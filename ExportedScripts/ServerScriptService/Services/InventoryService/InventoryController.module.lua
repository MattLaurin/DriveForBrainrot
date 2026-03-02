--[[
	ServerScriptService/InventoryService/InventoryController.lua (ModuleScript)
	
	SOLE RESPONSIBILITY: Manage player brainrot inventory.
	Add, remove, query brainrots. Notify client of changes.
--]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerManager = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerManager"))
local DriveConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DriveConfig"))
local BrainrotConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BrainrotConfig"))

local InventoryController = {}

------------------------------------------------------------
-- REMOTES (created once here, other scripts WaitForChild)
------------------------------------------------------------
-- Ensure Remotes folder exists (single source of truth)
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

-- Server → Client: inventory changed, sends full brainrot table
local InventoryUpdate = Instance.new("RemoteEvent")
InventoryUpdate.Name = "InventoryUpdate"
InventoryUpdate.Parent = Remotes

-- Client → Server: request current inventory
local GetInventory = Instance.new("RemoteFunction")
GetInventory.Name = "GetInventory"
GetInventory.Parent = Remotes

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------
function InventoryController.CountCarried(player: Player): number
	local data = PlayerManager.GetData(player)
	if not data then return 0 end

	local n = 0
	for _, b in data.Inventory.Brainrots do
		if b.PlacedStand == nil then
			n += 1
		end
	end
	return n
end

function InventoryController.CanCarryMore(player: Player): boolean
	local data = PlayerManager.GetData(player)
	if not data then return false end

	local maxCarry = DriveConfig.GetMaxCarry(data.CarryLevel)
	return InventoryController.CountCarried(player) < maxCarry
end

------------------------------------------------------------
-- ADD BRAINROT TO INVENTORY
-- Returns uuid if successful, nil if failed
------------------------------------------------------------
function InventoryController.AddBrainrot(player: Player, brainrotId: string, rarity: string, mutation: string?): string?
	local data = PlayerManager.GetData(player)
	if not data then return nil end

	-- Validate
	if not BrainrotConfig.IsValidBrainrot(brainrotId) then
		warn("[InventoryController] Invalid brainrotId:", brainrotId)
		return nil
	end

	if not BrainrotConfig.IsValidRarity(rarity) then
		warn("[InventoryController] Invalid rarity:", rarity)
		return nil
	end

	-- Check carry capacity
	if not InventoryController.CanCarryMore(player) then
		return nil
	end

	local uuid = HttpService:GenerateGUID(false)
	data.Inventory.Brainrots[uuid] = {
		Id = brainrotId,
		Rarity = rarity,
		Level = 1,
		Mutation = mutation,
		PlacedStand = nil,
	}

	-- Notify client
	InventoryController.SendUpdate(player)

	return uuid
end

------------------------------------------------------------
-- REMOVE BRAINROT FROM INVENTORY
------------------------------------------------------------
function InventoryController.RemoveBrainrot(player: Player, uuid: string): boolean
	local data = PlayerManager.GetData(player)
	if not data then return false end

	if not data.Inventory.Brainrots[uuid] then return false end

	data.Inventory.Brainrots[uuid] = nil
	InventoryController.SendUpdate(player)
	return true
end

------------------------------------------------------------
-- GET BRAINROT BY UUID
------------------------------------------------------------
function InventoryController.GetBrainrot(player: Player, uuid: string): { [string]: any }?
	local data = PlayerManager.GetData(player)
	if not data then return nil end
	return data.Inventory.Brainrots[uuid]
end

------------------------------------------------------------
-- GET ALL BRAINROTS
------------------------------------------------------------
function InventoryController.GetAllBrainrots(player: Player): { [string]: any }
	local data = PlayerManager.GetData(player)
	if not data then return {} end
	return data.Inventory.Brainrots
end

------------------------------------------------------------
-- SEND FULL INVENTORY TO CLIENT
------------------------------------------------------------
function InventoryController.SendUpdate(player: Player)
	local data = PlayerManager.GetData(player)
	if not data then return end
	InventoryUpdate:FireClient(player, data.Inventory.Brainrots)
end

------------------------------------------------------------
-- CLIENT REQUESTS
------------------------------------------------------------
GetInventory.OnServerInvoke = function(player: Player)
	local data = PlayerManager.GetData(player)
	if not data then return {} end
	return data.Inventory.Brainrots
end

------------------------------------------------------------
-- SEND INVENTORY ON JOIN
------------------------------------------------------------
function InventoryController.Init()
	Players.PlayerAdded:Connect(function(player)
		-- Wait for data to load, then send inventory
		task.spawn(function()
			while not PlayerManager.GetData(player) do
				task.wait(0.5)
			end
			InventoryController.SendUpdate(player)
		end)
	end)
end

return InventoryController