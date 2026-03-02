-- ServerScriptService/Modules/DataAccessor.lua
--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local PlayerManager = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerManager"))

local DataAccessor = {}

-- Core access

function DataAccessor:GetProfile(player: Player)
	return PlayerManager.GetProfile(player)
end

function DataAccessor:GetData(player: Player): { [string]: any }?
	return PlayerManager.GetData(player)
end

function DataAccessor:Save(player: Player)
	local profile = PlayerManager.GetProfile(player)
	if profile then
		profile:Save()
	end
end

-- Generic key access

function DataAccessor:GetKey(player: Player, key: string): any?
	local data = self:GetData(player)
	return data and data[key]
end

function DataAccessor:SetKey(player: Player, key: string, value: any)
	local data = self:GetData(player)
	if data then
		data[key] = value
	end
end

-- Leaderstats helpers (updates both data and leaderstat object)

local function SetLeaderstat(player: Player, name: string, value: number)
	local data = PlayerManager.GetData(player)
	if not data then return end

	data[name] = value

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local obj = leaderstats:FindFirstChild(name)
		if obj then
			obj.Value = value
		end
	end
end

local function GetLeaderstat(player: Player, name: string): number
	local data = PlayerManager.GetData(player)
	return data and data[name] or 0
end

-- Money

function DataAccessor:GetMoney(player: Player): number
	return GetLeaderstat(player, "Money")
end

function DataAccessor:SetMoney(player: Player, amount: number)
	SetLeaderstat(player, "Money", amount)
end

function DataAccessor:AddMoney(player: Player, amount: number)
	self:SetMoney(player, self:GetMoney(player) + amount)
end

-- Speed

function DataAccessor:GetSpeed(player: Player): number
	return GetLeaderstat(player, "Speed")
end

function DataAccessor:SetSpeed(player: Player, value: number)
	SetLeaderstat(player, "Speed", value)
end

-- Rebirth

function DataAccessor:GetRebirth(player: Player): number
	return GetLeaderstat(player, "Rebirth")
end

function DataAccessor:SetRebirth(player: Player, value: number)
	SetLeaderstat(player, "Rebirth", value)
end

function DataAccessor:GetRebirthLevel(player: Player): number
	local data = self:GetData(player)
	return data and data.RebirthLevel or 0
end

function DataAccessor:SetRebirthLevel(player: Player, value: number)
	local data = self:GetData(player)
	if data then
		data.RebirthLevel = value
	end
end

-- Car upgrades

function DataAccessor:GetEngine(player: Player): number
	local data = self:GetData(player)
	return data and data.Engine or 1
end

function DataAccessor:SetEngine(player: Player, level: number)
	local data = self:GetData(player)
	if data then
		data.Engine = level
	end
end

function DataAccessor:GetFuelCapacity(player: Player): number
	local data = self:GetData(player)
	return data and data.FuelCapacity or 1
end

function DataAccessor:SetFuelCapacity(player: Player, level: number)
	local data = self:GetData(player)
	if data then
		data.FuelCapacity = level
	end
end

function DataAccessor:GetCarry(player: Player): number
	local data = self:GetData(player)
	return data and data.Carry or 1
end

function DataAccessor:SetCarry(player: Player, level: number)
	local data = self:GetData(player)
	if data then
		data.Carry = level
	end
end

-- Inventory

function DataAccessor:GetInventory(player: Player): { [string]: any }?
	local data = self:GetData(player)
	return data and data.Inventory
end

function DataAccessor:GetBrainrots(player: Player): { any }
	local inv = self:GetInventory(player)
	return inv and inv.Brainrots or {}
end

function DataAccessor:AddBrainrot(player: Player, id: string, mutation: string?, level: number?)
	local inv = self:GetInventory(player)
	if inv then
		table.insert(inv.Brainrots, {
			Id = id,
			Mutation = mutation or nil,
			Level = level or 1,
		})
	end
end

function DataAccessor:GetLuckyBlocks(player: Player): { any }
	local inv = self:GetInventory(player)
	return inv and inv.LuckyBlocks or {}
end

function DataAccessor:AddLuckyBlock(player: Player, rarity: string, level: number?)
	local inv = self:GetInventory(player)
	if inv then
		table.insert(inv.LuckyBlocks, {
			Rarity = rarity,
			Level = level or nil,
		})
	end
end

function DataAccessor:GetTruckSkins(player: Player): { string }
	local inv = self:GetInventory(player)
	return inv and inv.TruckSkins or {}
end

function DataAccessor:AddTruckSkin(player: Player, skinId: string)
	local inv = self:GetInventory(player)
	if inv and not table.find(inv.TruckSkins, skinId) then
		table.insert(inv.TruckSkins, skinId)
	end
end

function DataAccessor:GetPlotSkins(player: Player): { string }
	local inv = self:GetInventory(player)
	return inv and inv.PlotSkins or {}
end

function DataAccessor:AddPlotSkin(player: Player, skinId: string)
	local inv = self:GetInventory(player)
	if inv and not table.find(inv.PlotSkins, skinId) then
		table.insert(inv.PlotSkins, skinId)
	end
end

return DataAccessor