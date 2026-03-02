--[[
	ServerScriptService/Controllers/DriveController.lua (ModuleScript)
	
	Handles:
	- Spawning player's truck at Garage
	- Morphing player into truck when entering GameZone or DynoZone
	- Unmorphing when leaving all zones or fuel runs out
	- DynoZone: morph but lock movement (WalkSpeed=0), wheels spin idle
	- Zone rarity -> speed penalty
	- Fuel drain (only in GameZone, not DynoZone)
	- Upgrades: Speed, Gas, Carry
	
	DATA KEYS: SpeedLevel, GasLevel, CarryLevel, Money
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local PlayerManager = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerManager"))
local PlotManager = require(ServerScriptService:WaitForChild("Services"):WaitForChild("PlotService"):WaitForChild("PlotManager"))
local DriveConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DriveConfig"))

local DriveController = {}

------------------------------------------------------------
-- TRUCK TEMPLATE
------------------------------------------------------------
local TruckTemplate = workspace:WaitForChild("SmallTruck")

------------------------------------------------------------
-- REMOTES
------------------------------------------------------------
local Remotes = ReplicatedStorage:FindFirstChild("DriveRemotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "DriveRemotes"
	Remotes.Parent = ReplicatedStorage
end

local function ensureRemote(name: string, className: string)
	local remote = Remotes:FindFirstChild(name)
	if remote and remote.ClassName ~= className then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = Remotes
	end
	return remote
end

local UpgradeStat = ensureRemote("UpgradeStat", "RemoteFunction")
local GetDriveData = ensureRemote("GetDriveData", "RemoteFunction")
local FuelUpdate = ensureRemote("FuelUpdate", "RemoteEvent")
local MorphEvent = ensureRemote("MorphEvent", "RemoteEvent")
local UnmorphEvent = ensureRemote("UnmorphEvent", "RemoteEvent")
local ZoneChanged = ensureRemote("ZoneChanged", "RemoteEvent")

------------------------------------------------------------
-- DATA HELPERS
------------------------------------------------------------
local function getData(player): { [string]: any }?
	return PlayerManager.GetData(player)
end

local function getMoney(player): number
	local ls = player:FindFirstChild("leaderstats")
	local m = ls and ls:FindFirstChild("Money")
	return m and m.Value or 0
end

local function setMoney(player, amount: number)
	local ls = player:FindFirstChild("leaderstats")
	local m = ls and ls:FindFirstChild("Money")
	if m then m.Value = amount end
end

------------------------------------------------------------
-- PLAYER DRIVE STATE (runtime only)
------------------------------------------------------------
local DriveState = {}

local function initDriveState(player)
	local data = getData(player)
	local gasLevel = data and data.GasLevel or 1

	DriveState[player] = {
		IsCar = false,
		InGameZone = false,
		InDynoZone = false,
		CurrentZoneRarity = "Common",
		CurrentDynoMultiplier = 1,
		Fuel = DriveConfig.GetMaxFuel(gasLevel),
		GarageTruck = nil,
		ActiveTruck = nil,
		SitAnimTrack = nil,
	}
end

local function getPlayerEffectiveSpeed(player): number
	local data = getData(player)
	local speedLevel = data and data.SpeedLevel or 1
	return DriveConfig.GetEffectiveSpeed(speedLevel)
end

------------------------------------------------------------
-- APPLY SPEED
------------------------------------------------------------
local function applySpeed(player)
	local state = DriveState[player]
	if not state or not state.IsCar then return end

	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- In DynoZone: player can still drive around freely (speed gain is passive)
	-- No WalkSpeed lock — they can drive out whenever they want

	local effectiveSpeed = getPlayerEffectiveSpeed(player)
	local rarity = state.CurrentZoneRarity or "Common"

	humanoid.WalkSpeed = DriveConfig.GetZoneSpeed(effectiveSpeed, rarity)
end

------------------------------------------------------------
-- TRUCK SPAWNING AT GARAGE
------------------------------------------------------------
local function spawnGarageTruck(player)
	local state = DriveState[player]
	if not state then return end

	if state.GarageTruck then
		state.GarageTruck:Destroy()
		state.GarageTruck = nil
	end

	local plot = PlotManager.GetPlot(player)
	if not plot then return end

	local garage = plot:FindFirstChild("Garage")
	if not garage then return end

	local garagePart = garage:FindFirstChild("Main") or garage:FindFirstChild("Part") or garage.PrimaryPart
	if not garagePart then
		for _, child in garage:GetDescendants() do
			if child:IsA("BasePart") then
				garagePart = child
				break
			end
		end
	end
	if not garagePart then return end

	local truck = TruckTemplate:Clone()
	truck.Name = player.Name .. "_GarageTruck"

	local driveSeat = truck.Body:FindFirstChild("DriveSeat")
	if driveSeat then
		truck.PrimaryPart = driveSeat
	end

	if truck.PrimaryPart then
		truck:PivotTo(garagePart.CFrame * CFrame.new(0, 3, 0))
	end

	for _, part in truck:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end

	truck.Parent = workspace
	state.GarageTruck = truck
end

------------------------------------------------------------
-- MORPH
------------------------------------------------------------
local WELD_ALL_PARTS = true

local function morphPlayer(player)
	local state = DriveState[player]
	if not state or state.IsCar then return end

	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then return end

	state.IsCar = true

	local data = getData(player)
	local gasLevel = data and data.GasLevel or 1
	state.Fuel = DriveConfig.GetMaxFuel(gasLevel)

	if state.GarageTruck then
		state.GarageTruck:Destroy()
		state.GarageTruck = nil
	end

	local truck = TruckTemplate:Clone()
	truck.Name = "ActiveTruck"

	local driveSeat = truck.Body:FindFirstChild("DriveSeat")
	if not driveSeat then
		warn("[DriveController] No DriveSeat in truck!")
		state.IsCar = false
		return
	end

	for _, part in truck:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
		end
	end

	if WELD_ALL_PARTS then
		for _, part in truck.Body:GetChildren() do
			if part:IsA("BasePart") and part ~= driveSeat then
				local weld = Instance.new("Weld")
				weld.Name = "TruckWeld"
				weld.Part0 = driveSeat
				weld.Part1 = part
				weld.C0 = driveSeat.CFrame:ToObjectSpace(part.CFrame)
				weld.Parent = part
			end
		end

		for _, tireModel in truck.Wheels:GetChildren() do
			for _, part in tireModel:GetChildren() do
				if part:IsA("BasePart") then
					local weld = Instance.new("Weld")
					weld.Name = "WheelWeld"
					weld.Part0 = driveSeat
					weld.Part1 = part
					weld.C0 = driveSeat.CFrame:ToObjectSpace(part.CFrame)
					weld.Parent = part
				end
			end
		end
	end

	truck.Parent = character

	local TRUCK_Y_OFFSET = -0.1
	local TRUCK_FACING_FIX = 90

	local mainWeld = Instance.new("Weld")
	mainWeld.Name = "TruckRootWeld"
	mainWeld.Part0 = rootPart
	mainWeld.Part1 = driveSeat
	mainWeld.C0 = CFrame.new(0, TRUCK_Y_OFFSET, 0) * CFrame.Angles(0, math.rad(TRUCK_FACING_FIX), 0)
	mainWeld.Parent = driveSeat

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local sitAnim = Instance.new("Animation")
		sitAnim.AnimationId = "rbxassetid://2506281703"
		local track = animator:LoadAnimation(sitAnim)
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Action
		track:Play()
		state.SitAnimTrack = track
	end

	state.ActiveTruck = truck
	applySpeed(player)

	local maxFuel = DriveConfig.GetMaxFuel(gasLevel)
	MorphEvent:FireClient(player)
	FuelUpdate:FireClient(player, state.Fuel, maxFuel)
end

------------------------------------------------------------
-- UNMORPH
------------------------------------------------------------
local function unmorphPlayer(player)
	local state = DriveState[player]
	if not state or not state.IsCar then return end

	local character = player.Character
	if not character then return end

	state.IsCar = false
	state.InGameZone = false
	state.InDynoZone = false
	state.CurrentZoneRarity = "Common"
	state.CurrentDynoMultiplier = 1

	if state.SitAnimTrack then
		state.SitAnimTrack:Stop(0.2)
		state.SitAnimTrack = nil
	end

	if state.ActiveTruck then
		state.ActiveTruck:Destroy()
		state.ActiveTruck = nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 16
	end

	spawnGarageTruck(player)
	UnmorphEvent:FireClient(player)
end

------------------------------------------------------------
-- PUBLIC HELPERS FOR OTHER SERVICES
------------------------------------------------------------
function DriveController.IsPlayerInCar(player: Player): boolean
	local state = DriveState[player]
	return state ~= nil and state.IsCar == true
end

function DriveController.IsPlayerInDynoZone(player: Player): boolean
	local state = DriveState[player]
	return state ~= nil and state.InDynoZone == true
end

function DriveController.IsPlayerInGameZone(player: Player): boolean
	local state = DriveState[player]
	return state ~= nil and state.InGameZone == true
end

function DriveController.GetCurrentDynoMultiplier(player: Player): number
	local state = DriveState[player]
	if not state then return 1 end
	return state.CurrentDynoMultiplier or 1
end

function DriveController.GetCurrentZoneRarity(player: Player): string
	local state = DriveState[player]
	if not state then return "Common" end
	return state.CurrentZoneRarity or "Common"
end

function DriveController.ApplySpeed(player: Player)
	applySpeed(player)
end

------------------------------------------------------------
-- ZONE CHANGE (client -> server)
-- Now receives: inGameZone, rarity, dynoMultiplier, inDynoZone
------------------------------------------------------------
ZoneChanged.OnServerEvent:Connect(function(player, inGameZone, rarity, dynoMultiplier, inDynoZone)
	local state = DriveState[player]
	if not state then return end

	local targetRarity = tostring(rarity or "Common")
	if not DriveConfig.ZoneRarity[targetRarity] then
		targetRarity = "Common"
	end

	local dyno = tonumber(dynoMultiplier) or 0
	if dyno < 0 then dyno = 0 end
	state.CurrentDynoMultiplier = dyno

	local wasInAnyZone = state.InGameZone or state.InDynoZone
	local nowInDyno = (inDynoZone == true)
	local nowInGame = (inGameZone == true)
	local nowInAnyZone = nowInDyno or nowInGame

	state.InDynoZone = nowInDyno
	state.InGameZone = nowInGame
	state.CurrentZoneRarity = targetRarity

	if nowInAnyZone then
		if not wasInAnyZone then
			-- Just entered a zone: morph
			morphPlayer(player)
		else
			-- Already morphed, just update speed/state
			applySpeed(player)
		end
	else
		-- Left all zones: unmorph
		if state.IsCar then
			unmorphPlayer(player)
		end
	end
end)

------------------------------------------------------------
-- UPGRADE HANDLER
------------------------------------------------------------
UpgradeStat.OnServerInvoke = function(player, statName)
	local data = getData(player)
	if not data then return false, "No data" end

	local currentLevel, maxLevel, getCost, dataKey

	if statName == "Speed" then
		currentLevel = data.SpeedLevel
		maxLevel = DriveConfig.MAX_SPEED_LEVEL
		getCost = DriveConfig.GetSpeedCost
		dataKey = "SpeedLevel"
	elseif statName == "Gas" then
		currentLevel = data.GasLevel
		maxLevel = DriveConfig.MAX_GAS_LEVEL
		getCost = DriveConfig.GetGasCost
		dataKey = "GasLevel"
	elseif statName == "Carry" then
		currentLevel = data.CarryLevel
		maxLevel = DriveConfig.MAX_CARRY_LEVEL
		getCost = DriveConfig.GetCarryCost
		dataKey = "CarryLevel"
	else
		return false, "Invalid upgrade: " .. tostring(statName)
	end

	local nextLevel = currentLevel + 1
	if nextLevel > maxLevel then
		return false, "Already maxed!"
	end

	local cost = getCost(nextLevel)
	local money = getMoney(player)

	if money < cost then
		return false, "Need $" .. cost
	end

	setMoney(player, money - cost)
	data[dataKey] = nextLevel

	if statName == "Speed" then
		local ls = player:FindFirstChild("leaderstats")
		local speedVal = ls and ls:FindFirstChild("Speed")
		if speedVal then
			speedVal.Value = DriveConfig.GetEffectiveSpeed(nextLevel)
		end
	end

	local state = DriveState[player]
	if state and state.IsCar then
		if statName == "Speed" then
			applySpeed(player)
		elseif statName == "Gas" then
			state.Fuel = DriveConfig.GetMaxFuel(nextLevel)
			FuelUpdate:FireClient(player, state.Fuel, DriveConfig.GetMaxFuel(nextLevel))
		end
	end

	return true, statName .. " Level " .. nextLevel
end

------------------------------------------------------------
-- GET DRIVE DATA (for client UI)
------------------------------------------------------------
GetDriveData.OnServerInvoke = function(player)
	local state = DriveState[player]
	if not state then return nil end

	local data = getData(player)
	if not data then return nil end

	return {
		Money = getMoney(player),
		SpeedLevel = data.SpeedLevel,
		GasLevel = data.GasLevel,
		CarryLevel = data.CarryLevel,
		Fuel = state.Fuel,
		MaxFuel = DriveConfig.GetMaxFuel(data.GasLevel),
		EffectiveSpeed = getPlayerEffectiveSpeed(player),
		IsCar = state.IsCar,
		InDynoZone = state.InDynoZone,
		InGameZone = state.InGameZone,
		CurrentZoneRarity = state.CurrentZoneRarity,
		CurrentDynoMultiplier = state.CurrentDynoMultiplier,
	}
end

------------------------------------------------------------
-- FUEL DRAIN LOOP (only drains in GameZone, NOT in DynoZone)
------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	for player, state in pairs(DriveState) do
		if state.IsCar and state.InGameZone and not state.InDynoZone then
			local drainMult = DriveConfig.GetFuelDrainMult(state.CurrentZoneRarity)
			state.Fuel = math.max(0, state.Fuel - DriveConfig.FUEL_DRAIN_RATE * drainMult * dt)

			local data = getData(player)
			local gasLevel = data and data.GasLevel or 1
			local maxFuel = DriveConfig.GetMaxFuel(gasLevel)
			FuelUpdate:FireClient(player, state.Fuel, maxFuel)

			if state.Fuel <= 0 then
				unmorphPlayer(player)
			end
		end
	end
end)

------------------------------------------------------------
-- PLAYER LIFECYCLE
------------------------------------------------------------
function DriveController.Init()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(1)
			initDriveState(player)
			spawnGarageTruck(player)
		end)

		if player.Character then
			task.wait(1)
			initDriveState(player)
			spawnGarageTruck(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local state = DriveState[player]
		if state then
			if state.GarageTruck then state.GarageTruck:Destroy() end
			if state.ActiveTruck then state.ActiveTruck:Destroy() end
		end
		DriveState[player] = nil
	end)

	TruckTemplate.Parent = ServerScriptService
	print("[DriveController] Initialized!")
end

return DriveController
