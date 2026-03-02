--[[
	ReplicatedStorage/Shared/DriveConfig.lua (ModuleScript)
	
	Shared config for tsunami escape drive system.
	No engine types. Speed = simple +1 per level.
--]]

local DriveConfig = {}

------------------------------------------------------------
-- BASE STATS
------------------------------------------------------------
DriveConfig.BASE_SPEED      = 10
DriveConfig.FUEL_DRAIN_RATE = 2
DriveConfig.BASE_FUEL       = 20
DriveConfig.BASE_CARRY      = 1

------------------------------------------------------------
-- MAX LEVELS
------------------------------------------------------------
DriveConfig.MAX_SPEED_LEVEL = 500
DriveConfig.MAX_CARRY_LEVEL = 50
DriveConfig.MAX_GAS_LEVEL   = 50

------------------------------------------------------------
-- SPEED (+1 per level)
------------------------------------------------------------
function DriveConfig.GetSpeedCost(level: number): number
	if level <= 1 then return 0 end
	return math.floor(10 * level ^ 1.4)
end

function DriveConfig.GetEffectiveSpeed(speedLevel: number): number
	return DriveConfig.BASE_SPEED + (speedLevel - 1)
end

------------------------------------------------------------
-- CARRY
------------------------------------------------------------
function DriveConfig.GetCarryCost(level: number): number
	if level <= 1 then return 0 end
	return math.floor(50 * level ^ 1.6)
end

function DriveConfig.GetMaxCarry(carryLevel: number): number
	return DriveConfig.BASE_CARRY + (carryLevel - 1)
end

------------------------------------------------------------
-- GAS TANK
------------------------------------------------------------
function DriveConfig.GetGasCost(level: number): number
	if level <= 1 then return 0 end
	return math.floor(40 * level ^ 1.5)
end

function DriveConfig.GetMaxFuel(gasLevel: number): number
	return DriveConfig.BASE_FUEL + (gasLevel - 1) * 5
end

------------------------------------------------------------
-- REBIRTH
------------------------------------------------------------
function DriveConfig.GetRebirthCost(rebirthLevel: number): number
	return math.floor(5000 * (rebirthLevel + 1) ^ 2)
end

function DriveConfig.GetRebirthMultiplier(rebirthLevel: number): number
	return 1 + rebirthLevel * 0.25
end

------------------------------------------------------------
-- ZONE RARITY (kept for zone speed penalties + fuel drain)
------------------------------------------------------------
DriveConfig.ZoneRarity = {
	Common = {
		MinSpeed = 0,
		SlowedSpeed = 0,
		FuelDrainMult = 1,
	},
	Uncommon = {
		MinSpeed = 25,
		SlowedSpeed = 8,
		FuelDrainMult = 1.2,
	},
	Rare = {
		MinSpeed = 45,
		SlowedSpeed = 10,
		FuelDrainMult = 1.5,
	},
	Epic = {
		MinSpeed = 70,
		SlowedSpeed = 12,
		FuelDrainMult = 2.0,
	},
	Legendary = {
		MinSpeed = 100,
		SlowedSpeed = 14,
		FuelDrainMult = 3.0,
	},
	DynoZone = {
		MinSpeed = 0,
		SlowedSpeed = 0,
		FuelDrainMult = 0,
	},
}

function DriveConfig.GetZoneSpeed(effectiveSpeed: number, rarity: string): number
	local zone = DriveConfig.ZoneRarity[rarity]
	if not zone then return effectiveSpeed end
	if effectiveSpeed >= zone.MinSpeed then
		return effectiveSpeed
	else
		return zone.SlowedSpeed
	end
end

function DriveConfig.GetFuelDrainMult(rarity: string): number
	local zone = DriveConfig.ZoneRarity[rarity]
	return zone and zone.FuelDrainMult or 1
end

------------------------------------------------------------
-- BRAINROT CONFIG
------------------------------------------------------------
DriveConfig.Rarities = {
	Common     = { Color = Color3.fromRGB(200, 200, 200), Weight = 60 },
	Uncommon   = { Color = Color3.fromRGB(0, 200, 0),     Weight = 25 },
	Rare       = { Color = Color3.fromRGB(0, 100, 255),   Weight = 10 },
	Epic       = { Color = Color3.fromRGB(160, 0, 255),   Weight = 4  },
	Legendary  = { Color = Color3.fromRGB(255, 200, 0),   Weight = 1  },
}

DriveConfig.BrainrotBaseIncome = {
	Common    = 1,
	Uncommon  = 3,
	Rare      = 8,
	Epic      = 20,
	Legendary = 50,
}

function DriveConfig.GetBrainrotUpgradeCost(currentLevel: number, rarity: string): number
	local base = DriveConfig.BrainrotBaseIncome[rarity] or 1
	return math.floor(base * 15 * currentLevel ^ 1.3)
end

function DriveConfig.GetBrainrotIncome(rarity: string, level: number, rebirthLevel: number): number
	local base = DriveConfig.BrainrotBaseIncome[rarity] or 1
	local rebirthMult = DriveConfig.GetRebirthMultiplier(rebirthLevel)
	return base * level * rebirthMult
end

return DriveConfig