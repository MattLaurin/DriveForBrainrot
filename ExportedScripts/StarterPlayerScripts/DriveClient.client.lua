--[[
	StarterPlayerScripts/DriveClient.lua (LocalScript)
	
	Handles:
	- GameZone + rarity subzone detection -> tells server when entering/leaving
	- DynoZone multiplier detection (1x/3x/9x/25x/100x)
	- Wheel spin animation (visual only, based on movement speed OR dyno idle)
	- Fuel bar HUD
	- Zone status indicator
	- Listens for morph/unmorph events from server
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer

------------------------------------------------------------
-- ZONEPLUS SETUP
------------------------------------------------------------
local Zone = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Zone"))

------------------------------------------------------------
-- WAIT FOR REMOTES
------------------------------------------------------------
local Remotes = ReplicatedStorage:WaitForChild("DriveRemotes")
local FuelUpdate = Remotes:WaitForChild("FuelUpdate")
local MorphEvent = Remotes:WaitForChild("MorphEvent")
local UnmorphEvent = Remotes:WaitForChild("UnmorphEvent")
local ZoneChanged = Remotes:WaitForChild("ZoneChanged")

------------------------------------------------------------
-- STATE
------------------------------------------------------------
local isMorphed = false
local currentFuel = 0
local maxFuel = 50

local wheelSpinConnection = nil
local driveConnection = nil

local activeGameRarityZones = {} -- [zonePart] = rarity
local activeDynoZones = {} -- [zonePart] = multiplier
local trackedZones = {} -- [zonePart] = true

local lastSentInGameZone = false
local lastSentInDynoZone = false
local lastSentRarity = "Common"
local lastSentDynoMult = 1

local updateZoneLabel

------------------------------------------------------------
-- CAR MOVEMENT TUNING
------------------------------------------------------------
local CAR_SETTINGS = {
	ROTATION_SPEED = 12,
	TILT_AMOUNT = 4,
	TILT_SPEED = 8,
	PITCH_AMOUNT = 2,
	PITCH_SPEED = 6,
}

local currentTilt = 0
local currentPitch = 0
local lastYaw = 0
local lastSpeed = 0

local function startDriveController()
	if driveConnection then return end

	local character = Player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then return end

	humanoid.AutoRotate = false

	lastYaw = math.atan2(-rootPart.CFrame.LookVector.X, -rootPart.CFrame.LookVector.Z)
	currentTilt = 0
	currentPitch = 0
	lastSpeed = 0

	driveConnection = RunService.Heartbeat:Connect(function(dt)
		if not isMorphed then return end

		character = Player.Character
		if not character then return end
		humanoid = character:FindFirstChildOfClass("Humanoid")
		rootPart = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not rootPart then return end

		local S = CAR_SETTINGS
		local vel = rootPart.AssemblyLinearVelocity
		local flatVel = Vector3.new(vel.X, 0, vel.Z)
		local speed = flatVel.Magnitude

		if speed > 1 then
			local desiredYaw = math.atan2(-flatVel.Unit.X, -flatVel.Unit.Z)
			local yawDiff = math.atan2(math.sin(desiredYaw - lastYaw), math.cos(desiredYaw - lastYaw))
			lastYaw = lastYaw + yawDiff * math.min(1, S.ROTATION_SPEED * dt)

			local targetTilt = math.clamp(yawDiff * 30, -S.TILT_AMOUNT, S.TILT_AMOUNT)
			currentTilt = currentTilt + (targetTilt - currentTilt) * math.min(1, S.TILT_SPEED * dt)

			local accel = speed - lastSpeed
			local targetPitch = math.clamp(-accel * 0.5, -S.PITCH_AMOUNT, S.PITCH_AMOUNT)
			currentPitch = currentPitch + (targetPitch - currentPitch) * math.min(1, S.PITCH_SPEED * dt)
		else
			currentTilt = currentTilt * (1 - math.min(1, 8 * dt))
			currentPitch = currentPitch * (1 - math.min(1, 8 * dt))
		end

		lastSpeed = speed

		local targetCF = CFrame.new(rootPart.Position)
			* CFrame.Angles(0, lastYaw, 0)
			* CFrame.Angles(math.rad(currentPitch), 0, math.rad(currentTilt))

		rootPart.CFrame = rootPart.CFrame:Lerp(targetCF, math.min(1, S.ROTATION_SPEED * dt))
	end)
end

local function stopDriveController()
	if driveConnection then
		driveConnection:Disconnect()
		driveConnection = nil
	end

	local character = Player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.AutoRotate = true
		end
	end

	currentTilt = 0
	currentPitch = 0
end

------------------------------------------------------------
-- ZONE DETECTION
------------------------------------------------------------
local function titleCase(s: string): string
	if #s == 0 then return s end
	return string.upper(string.sub(s, 1, 1)) .. string.lower(string.sub(s, 2))
end

local function getCurrentRarityFromActiveZones(): string
	local priority = {"Legendary", "Epic", "Rare", "Uncommon", "Common"}
	local found = {}
	for _, rarity in pairs(activeGameRarityZones) do
		found[rarity] = true
	end
	for _, rarity in ipairs(priority) do
		if found[rarity] then
			return rarity
		end
	end
	for _, rarity in pairs(activeGameRarityZones) do
		return rarity
	end
	return "Common"
end

local function getCurrentDynoMultiplier(): number
	local best = 0
	for _, mult in pairs(activeDynoZones) do
		if mult > best then best = mult end
	end
	return best
end

local function isInAnyGameZone(): boolean
	for _ in pairs(activeGameRarityZones) do
		return true
	end
	return false
end

local function isInAnyDynoZone(): boolean
	for _ in pairs(activeDynoZones) do
		return true
	end
	return false
end

local function pushZoneStateToServer()
	local inGameZone = isInAnyGameZone()
	local inDynoZone = isInAnyDynoZone()
	local rarity = getCurrentRarityFromActiveZones()
	local dynoMult = getCurrentDynoMultiplier()

	if inGameZone ~= lastSentInGameZone or inDynoZone ~= lastSentInDynoZone or rarity ~= lastSentRarity or dynoMult ~= lastSentDynoMult then
		lastSentInGameZone = inGameZone
		lastSentInDynoZone = inDynoZone
		lastSentRarity = rarity
		lastSentDynoMult = dynoMult
		ZoneChanged:FireServer(inGameZone, rarity, dynoMult, inDynoZone)
	end
end

local function hasAncestorNamed(inst: Instance, targetName: string): boolean
	local p = inst.Parent
	while p do
		if p.Name == targetName then
			return true
		end
		p = p.Parent
	end
	return false
end

local function inferRarityFromZonePart(part: BasePart): string?
	local attr = part:GetAttribute("Rarity")
	if type(attr) == "string" and attr ~= "DynoZone" then
		return titleCase(attr)
	end

	local n = string.lower(part.Name)
	if string.sub(n, -4) == "zone" then
		local base = string.sub(part.Name, 1, #part.Name - 4)
		if base ~= "" and string.lower(base) ~= "dyno" and not string.find(string.lower(base), "dyno") then
			return titleCase(base)
		end
	end

	return nil
end

local function inferDynoMultiplierFromPart(part: BasePart): number?
	local m = part:GetAttribute("SpeedMultiplier")
	if type(m) == "number" and m >= 1 then
		return m
	end

	local n = string.lower(part.Name)
	if string.find(n, "dynozone") then
		local x = string.match(n, "(%d+)x")
		if x then
			return tonumber(x) or 1
		end
		return 1
	end

	return nil
end

local function trackZonePart(zonePart: BasePart)
	if trackedZones[zonePart] then return end
	trackedZones[zonePart] = true

	local rarity = inferRarityFromZonePart(zonePart)
	local dynoMult = inferDynoMultiplierFromPart(zonePart)

	if not rarity and not dynoMult then
		return
	end

	local zone = Zone.new(zonePart)

	zone.playerEntered:Connect(function(enteringPlayer)
		if enteringPlayer ~= Player then return end
		if rarity then
			activeGameRarityZones[zonePart] = rarity
		end
		if dynoMult then
			activeDynoZones[zonePart] = dynoMult
		end
		pushZoneStateToServer()
		if updateZoneLabel then updateZoneLabel() end
		updateFuelVisibility()
	end)

	zone.playerExited:Connect(function(exitingPlayer)
		if exitingPlayer ~= Player then return end
		activeGameRarityZones[zonePart] = nil
		activeDynoZones[zonePart] = nil
		pushZoneStateToServer()
		if updateZoneLabel then updateZoneLabel() end
		updateFuelVisibility()
	end)
end

local function setupZoneDetection()
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") then
			local isDyno = string.find(string.lower(obj.Name), "dynozone") ~= nil
			local isGameSubZone = hasAncestorNamed(obj, "GameZone")
			local isLegacyGameZonePart = obj.Name == "GameZone"
			if isDyno or isGameSubZone or isLegacyGameZonePart then
				trackZonePart(obj)
			end
		end
	end

	workspace.DescendantAdded:Connect(function(obj)
		if obj:IsA("BasePart") then
			local isDyno = string.find(string.lower(obj.Name), "dynozone") ~= nil
			local isGameSubZone = hasAncestorNamed(obj, "GameZone")
			local isLegacyGameZonePart = obj.Name == "GameZone"
			if isDyno or isGameSubZone or isLegacyGameZonePart then
				trackZonePart(obj)
			end
		end
	end)

	pushZoneStateToServer()
end

------------------------------------------------------------
-- WHEEL SPIN ANIMATION (movement + dyno idle spin)
------------------------------------------------------------
local WHEEL_SPIN_AXIS = "Z"
local WHEEL_SPIN_SPEED = 4
local DYNO_IDLE_SPIN_SPEED = 30  -- fast idle spin in dyno

local function startWheelSpin()
	if wheelSpinConnection then return end

	wheelSpinConnection = RunService.RenderStepped:Connect(function(dt)
		local character = Player.Character
		if not character then return end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end

		local truck = character:FindFirstChild("ActiveTruck")
		if not truck then return end

		local wheelsFolder = truck:FindFirstChild("Wheels")
		if not wheelsFolder then return end

		local speed = rootPart.AssemblyLinearVelocity.Magnitude

		-- In dyno zone: spin wheels even when stationary
		local inDyno = isInAnyDynoZone()
		local effectiveSpinSpeed = speed
		if inDyno and speed < 1 then
			effectiveSpinSpeed = DYNO_IDLE_SPIN_SPEED
		end

		if effectiveSpinSpeed > 0.5 then
			local spinAmount = effectiveSpinSpeed * dt * WHEEL_SPIN_SPEED
			local spinCF
			if WHEEL_SPIN_AXIS == "X" then
				spinCF = CFrame.Angles(spinAmount, 0, 0)
			elseif WHEEL_SPIN_AXIS == "Y" then
				spinCF = CFrame.Angles(0, spinAmount, 0)
			else
				spinCF = CFrame.Angles(0, 0, spinAmount)
			end

			for _, tireModel in wheelsFolder:GetChildren() do
				if tireModel:IsA("Model") then
					for _, part in tireModel:GetChildren() do
						if part:IsA("BasePart") then
							local weld = part:FindFirstChild("WheelWeld") or part:FindFirstChild("TruckWeld")
							if weld then
								weld.C1 = weld.C1 * spinCF
							end
						end
					end
				end
			end
		end
	end)
end

local function stopWheelSpin()
	if wheelSpinConnection then
		wheelSpinConnection:Disconnect()
		wheelSpinConnection = nil
	end
end

------------------------------------------------------------
-- UI: FUEL BAR + ZONE INDICATOR
------------------------------------------------------------
local screenGui, fuelFrame, fuelBar, fuelLabel, zoneLabel

local function createUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DriveHUD"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = Player.PlayerGui

	fuelFrame = Instance.new("Frame")
	fuelFrame.Name = "FuelFrame"
	fuelFrame.Size = UDim2.new(0, 280, 0, 28)
	fuelFrame.Position = UDim2.new(0.5, -140, 0, 12)
	fuelFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	fuelFrame.BorderSizePixel = 0
	fuelFrame.Visible = false
	fuelFrame.Parent = screenGui

	local fuelCorner = Instance.new("UICorner")
	fuelCorner.CornerRadius = UDim.new(0, 8)
	fuelCorner.Parent = fuelFrame

	local fuelStroke = Instance.new("UIStroke")
	fuelStroke.Thickness = 1.5
	fuelStroke.Color = Color3.fromRGB(80, 80, 100)
	fuelStroke.Parent = fuelFrame

	fuelBar = Instance.new("Frame")
	fuelBar.Name = "FuelFill"
	fuelBar.Size = UDim2.new(1, -6, 1, -6)
	fuelBar.Position = UDim2.new(0, 3, 0, 3)
	fuelBar.BackgroundColor3 = Color3.fromRGB(255, 170, 0)
	fuelBar.BorderSizePixel = 0
	fuelBar.Parent = fuelFrame

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fuelBar

	fuelLabel = Instance.new("TextLabel")
	fuelLabel.Name = "FuelText"
	fuelLabel.Size = UDim2.new(1, 0, 1, 0)
	fuelLabel.BackgroundTransparency = 1
	fuelLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	fuelLabel.Text = "FUEL: 50/50"
	fuelLabel.TextSize = 13
	fuelLabel.Font = Enum.Font.GothamBold
	fuelLabel.ZIndex = 5
	fuelLabel.Parent = fuelFrame

	zoneLabel = Instance.new("TextLabel")
	zoneLabel.Name = "ZoneStatus"
	zoneLabel.Size = UDim2.new(0, 280, 0, 22)
	zoneLabel.Position = UDim2.new(0.5, -140, 0, 44)
	zoneLabel.BackgroundTransparency = 1
	zoneLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
	zoneLabel.Text = ""
	zoneLabel.TextSize = 12
	zoneLabel.Font = Enum.Font.GothamMedium
	zoneLabel.Visible = false
	zoneLabel.Parent = screenGui
end

-- NEW: Fuel UI visibility depends on whether in DynoZone
function updateFuelVisibility()
	if not fuelFrame then return end
	local inDyno = isInAnyDynoZone()
	-- Show fuel ONLY when morphed AND NOT in a DynoZone
	fuelFrame.Visible = isMorphed and not inDyno
end

local function updateFuelUI(fuel, max)
	if not fuelFrame then return end

	currentFuel = fuel
	maxFuel = max

	-- Respect dyno hiding
	updateFuelVisibility()
	fuelLabel.Text = string.format("FUEL: %d / %d", math.floor(fuel), max)

	local pct = math.clamp(fuel / max, 0, 1)
	TweenService:Create(fuelBar, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
		Size = UDim2.new(pct, -6 + (6 * (1 - pct)), 1, -6)
	}):Play()

	if pct > 0.5 then
		fuelBar.BackgroundColor3 = Color3.fromRGB(80, 210, 80)
	elseif pct > 0.2 then
		fuelBar.BackgroundColor3 = Color3.fromRGB(255, 180, 30)
	else
		fuelBar.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	end
end

updateZoneLabel = function()
	if not zoneLabel then return end

	zoneLabel.Visible = isMorphed
	if not isMorphed then return end

	local inGame = isInAnyGameZone()
	local inDyno = isInAnyDynoZone()
	local rarity = getCurrentRarityFromActiveZones()
	local dynoMult = getCurrentDynoMultiplier()

	if inDyno then
		local label = dynoMult > 1 and (dynoMult .. "x") or "1x"
		zoneLabel.Text = "DYNO " .. label .. " | SPEED BOOST ACTIVE"
		zoneLabel.TextColor3 = Color3.fromRGB(255, 100, 255)
	elseif inGame then
		zoneLabel.Text = string.format("%s ZONE", string.upper(rarity))
		zoneLabel.TextColor3 = Color3.fromRGB(255, 180, 120)
	else
		zoneLabel.Text = "OUT OF ZONE"
		zoneLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
	end
end

------------------------------------------------------------
-- EVENT HANDLERS
------------------------------------------------------------
MorphEvent.OnClientEvent:Connect(function()
	isMorphed = true
	startWheelSpin()
	startDriveController()
	updateFuelVisibility()
	updateZoneLabel()
end)

UnmorphEvent.OnClientEvent:Connect(function()
	isMorphed = false
	stopWheelSpin()
	stopDriveController()
	if fuelFrame then fuelFrame.Visible = false end
	if zoneLabel then zoneLabel.Visible = false end
	updateZoneLabel()
end)

FuelUpdate.OnClientEvent:Connect(function(fuel, max)
	updateFuelUI(fuel, max)
end)

Player.CharacterAdded:Connect(function()
	isMorphed = false
	activeGameRarityZones = {}
	activeDynoZones = {}
	lastSentInGameZone = false
	lastSentInDynoZone = false
	lastSentRarity = "Common"
	lastSentDynoMult = 1
	stopWheelSpin()
	stopDriveController()
	if fuelFrame then fuelFrame.Visible = false end
	if zoneLabel then zoneLabel.Visible = false end
	pushZoneStateToServer()
end)

createUI()
setupZoneDetection()

print("[DriveClient] Loaded!")
