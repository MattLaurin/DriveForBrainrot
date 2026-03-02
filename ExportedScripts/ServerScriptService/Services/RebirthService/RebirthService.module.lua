-- ServerScriptService/Services/RebirthService/RebirthService.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerManager = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerManager"))
local DriveConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DriveConfig"))

local RebirthService = {}

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local RebirthRemotes = Remotes:FindFirstChild("RebirthRemotes")
if not RebirthRemotes then
	RebirthRemotes = Instance.new("Folder")
	RebirthRemotes.Name = "RebirthRemotes"
	RebirthRemotes.Parent = Remotes
end

local GetRebirthData = RebirthRemotes:FindFirstChild("GetRebirthData")
if not GetRebirthData then
	GetRebirthData = Instance.new("RemoteFunction")
	GetRebirthData.Name = "GetRebirthData"
	GetRebirthData.Parent = RebirthRemotes
end

local RequestRebirth = RebirthRemotes:FindFirstChild("RequestRebirth")
if not RequestRebirth then
	RequestRebirth = Instance.new("RemoteFunction")
	RequestRebirth.Name = "RequestRebirth"
	RequestRebirth.Parent = RebirthRemotes
end

local RebirthUpdated = RebirthRemotes:FindFirstChild("RebirthUpdated")
if not RebirthUpdated then
	RebirthUpdated = Instance.new("RemoteEvent")
	RebirthUpdated.Name = "RebirthUpdated"
	RebirthUpdated.Parent = RebirthRemotes
end

local function getMoney(player: Player, data: {[string]: any}): number
	local ls = player:FindFirstChild("leaderstats")
	local moneyValue = ls and ls:FindFirstChild("Money")
	if moneyValue then
		return moneyValue.Value
	end
	return data.Money or 0
end

local function setLeaderstat(player: Player, statName: string, value: number)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then return end
	local obj = ls:FindFirstChild(statName)
	if obj then obj.Value = value end
end

local function buildState(player: Player)
	local data = PlayerManager.GetData(player)
	if not data then return nil end

	local rebirthLevel = data.RebirthLevel or 0
	local money = getMoney(player, data)
	local cost = DriveConfig.GetRebirthCost(rebirthLevel)

	return {
		RebirthLevel = rebirthLevel,
		Money = money,
		Cost = cost,
		CanRebirth = money >= cost,
		BeforeMultiplier = DriveConfig.GetRebirthMultiplier(rebirthLevel),
		AfterMultiplier = DriveConfig.GetRebirthMultiplier(rebirthLevel + 1),
	}
end

local function applyRebirth(player: Player, keepCash: boolean)
	local data = PlayerManager.GetData(player)
	if not data then
		return false, "Data not loaded", nil
	end

	local rebirthLevel = data.RebirthLevel or 0
	local cost = DriveConfig.GetRebirthCost(rebirthLevel)
	local currentMoney = getMoney(player, data)

	if not keepCash and currentMoney < cost then
		return false, "Not enough money", buildState(player)
	end

	data.RebirthLevel = rebirthLevel + 1
	data.Rebirth = data.RebirthLevel

	data.SpeedLevel = 1
	data.Speed = DriveConfig.GetEffectiveSpeed(data.SpeedLevel)

	if keepCash then
		data.Money = currentMoney
	else
		data.Money = 0
	end

	setLeaderstat(player, "Rebirth", data.Rebirth)
	setLeaderstat(player, "Speed", data.Speed)
	setLeaderstat(player, "Money", data.Money)

	local char = player.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = data.Speed
		end
	end

	local state = buildState(player)
	RebirthUpdated:FireClient(player, state)
	return true, "Rebirth successful", state
end

function RebirthService.SkipRebirthKeepCash(player: Player)
	return applyRebirth(player, true)
end

function RebirthService.TryNormalRebirth(player: Player)
	return applyRebirth(player, false)
end

function RebirthService.GetState(player: Player)
	return buildState(player)
end

function RebirthService.Init()
	GetRebirthData.OnServerInvoke = function(player: Player)
		local state = buildState(player)
		if not state then
			return { Success = false, Message = "Data not loaded" }
		end
		return { Success = true, State = state }
	end

	RequestRebirth.OnServerInvoke = function(player: Player, mode: string)
		if mode == "Normal" then
			local ok, msg, state = applyRebirth(player, false)
			return { Success = ok, Message = msg, State = state }
		end
		return { Success = false, Message = "Unsupported rebirth mode" }
	end

	Players.PlayerAdded:Connect(function(player)
		task.delay(1.5, function()
			if player.Parent then
				local state = buildState(player)
				if state then
					RebirthUpdated:FireClient(player, state)
				end
			end
		end)
	end)

	print("[RebirthService] Initialized")
end

return RebirthService
