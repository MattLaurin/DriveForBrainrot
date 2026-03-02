local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerManager = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerManager"))
local DriveController = require(ServerScriptService:WaitForChild("Services"):WaitForChild("DriveService"):WaitForChild("DriveController"))
local DriveConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DriveConfig"))

local SpeedService = {}

local MOVE_THRESHOLD = 2
local BASE_GAIN_PER_SECOND = 1

local speedTickAccum = {} -- [player] = seconds

local function ensureRemotes()
	local speedRemotes = ReplicatedStorage:FindFirstChild("SpeedRemotes")
	if not speedRemotes then
		speedRemotes = Instance.new("Folder")
		speedRemotes.Name = "SpeedRemotes"
		speedRemotes.Parent = ReplicatedStorage
	end

	local speedGained = speedRemotes:FindFirstChild("SpeedGained")
	if speedGained and not speedGained:IsA("RemoteEvent") then
		speedGained:Destroy()
		speedGained = nil
	end
	if not speedGained then
		speedGained = Instance.new("RemoteEvent")
		speedGained.Name = "SpeedGained"
		speedGained.Parent = speedRemotes
	end

	return speedGained
end

local speedGainedRemote

local function getData(player)
	return PlayerManager.GetData(player)
end

local function getRebirthMultiplier(player, data)
	if data and type(data.RebirthLevel) == "number" then
		return DriveConfig.GetRebirthMultiplier(data.RebirthLevel)
	end
	return 1
end

local function addSpeedLevel(player, amount)
	local data = getData(player)
	if not data then
		return 0
	end

	data.SpeedLevel = math.max(1, math.floor((data.SpeedLevel or 1) + amount))

	local ls = player:FindFirstChild("leaderstats")
	local speedVal = ls and ls:FindFirstChild("Speed")
	if speedVal then
		speedVal.Value = DriveConfig.GetEffectiveSpeed(data.SpeedLevel)
	end

	return amount
end

local function playerIsMovingInCar(player)
	if not DriveController.IsPlayerInCar(player) then
		return false
	end

	local character = player.Character
	if not character then return false end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return false end

	local flatSpeed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
	return flatSpeed >= MOVE_THRESHOLD
end

-- NEW: Check if player is in a DynoZone (gains speed passively)
local function playerIsInDynoZone(player)
	return DriveController.IsPlayerInCar(player) and DriveController.IsPlayerInDynoZone(player)
end

function SpeedService.Init()
	speedGainedRemote = ensureRemotes()

	Players.PlayerAdded:Connect(function(player)
		speedTickAccum[player] = 0
	end)

	Players.PlayerRemoving:Connect(function(player)
		speedTickAccum[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		speedTickAccum[player] = 0
	end

	RunService.Heartbeat:Connect(function(dt)
		for _, player in ipairs(Players:GetPlayers()) do
			local data = getData(player)
			if data then
				-- Speed gain triggers if:
				-- 1) Player is moving in car (GameZone driving), OR
				-- 2) Player is in DynoZone (passive gain, no movement needed)
				local isMoving = playerIsMovingInCar(player)
				local inDyno = playerIsInDynoZone(player)

				if isMoving or inDyno then
					speedTickAccum[player] = (speedTickAccum[player] or 0) + dt

					if speedTickAccum[player] >= 1 then
						local ticks = math.floor(speedTickAccum[player])
						speedTickAccum[player] -= ticks

						local rebirthMult = getRebirthMultiplier(player, data)
						local dynoMult = DriveController.GetCurrentDynoMultiplier(player)

						-- In GameZone (not dyno), dynoMult is 0, so use 1
						local effectiveDynoMult = math.max(1, dynoMult)

						local gainPerTick = BASE_GAIN_PER_SECOND * effectiveDynoMult * rebirthMult
						local gain = math.max(1, math.floor(gainPerTick * ticks))

						local added = addSpeedLevel(player, gain)
						if added > 0 then
							DriveController.ApplySpeed(player)
							speedGainedRemote:FireClient(player, added)
						end
					end
				else
					speedTickAccum[player] = 0
				end
			end
		end
	end)

	print("[SpeedService] Initialized")
end

return SpeedService
