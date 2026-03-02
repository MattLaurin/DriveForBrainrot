--[[
	ReplicatedStorage/Shared/BrainrotConfig.lua (ModuleScript)
	
	SOLE RESPONSIBILITY: Define all brainrot types and their base stats.
	Referenced by server (InventoryController, PickupController) and client.
--]]

local BrainrotConfig = {}

------------------------------------------------------------
-- BRAINROT CATALOG
-- Each entry key = BrainrotId (matches the model name in BrainrotModels folder
-- and the BrainrotId attribute on world spawns).
------------------------------------------------------------
BrainrotConfig.Catalog = {
	["67"] = {
		DisplayName = "67",
		Rarity = "Common",
		BaseIncome = 1,        -- money/s at level 1 before rebirth mult
		MaxLevel = 100,
		Description = "The classic 67 brainrot.",
	},
}

------------------------------------------------------------
-- RARITY DEFINITIONS
------------------------------------------------------------
BrainrotConfig.Rarities = {
	Common     = { Color = Color3.fromRGB(200, 200, 200), Weight = 60, Order = 1 },
	Uncommon   = { Color = Color3.fromRGB(0, 200, 0),     Weight = 25, Order = 2 },
	Rare       = { Color = Color3.fromRGB(0, 100, 255),   Weight = 10, Order = 3 },
	Epic       = { Color = Color3.fromRGB(160, 0, 255),   Weight = 4,  Order = 4 },
	Legendary  = { Color = Color3.fromRGB(255, 200, 0),   Weight = 1,  Order = 5 },
}

------------------------------------------------------------
-- INCOME SCALING
------------------------------------------------------------
BrainrotConfig.BaseIncomeByRarity = {
	Common    = 1,
	Uncommon  = 3,
	Rare      = 8,
	Epic      = 20,
	Legendary = 50,
}

------------------------------------------------------------
-- NUMBER FORMATTING
------------------------------------------------------------
------------------------------------------------------------
-- NUMBER FORMATTING (handles infinite scaling)
------------------------------------------------------------
local SUFFIXES = {
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc",
	"No", "Dc", "UDc", "DDc", "TDc", "QaDc", "QiDc", "SxDc", "SpDc", "OcDc",
	"NoDc", "Vg", "UVg", "DVg", "TVg", "QaVg", "QiVg", "SxVg", "SpVg", "OcVg",
	"NoVg", "Tg", "UTg", "DTg", "TTg", "QaTg", "QiTg", "SxTg", "SpTg", "OcTg",
	"NoTg", "Qd", "UQd", "DQd", "TQd", "QaQd", "QiQd", "SxQd", "SpQd", "OcQd",
	"NoQd", "Qq", "UQq", "DQq", "TQq", "QaQq", "QiQq", "SxQq", "SpQq", "OcQq",
}

function BrainrotConfig.FormatMoney(amount: number): string
	if amount < 1000 then
		return "$" .. tostring(math.floor(amount))
	end

	local index = math.floor(math.log10(amount) / 3)
	index = math.min(index, #SUFFIXES)

	local divisor = 10 ^ (index * 3)
	local shortened = amount / divisor

	if shortened >= 100 then
		return "$" .. string.format("%.0f", shortened) .. SUFFIXES[index + 1]
	elseif shortened >= 10 then
		return "$" .. string.format("%.1f", shortened) .. SUFFIXES[index + 1]
	else
		return "$" .. string.format("%.2f", shortened) .. SUFFIXES[index + 1]
	end
end

function BrainrotConfig.GetBaseIncome(brainrotId: string): number
	local entry = BrainrotConfig.Catalog[brainrotId]
	if entry then return entry.BaseIncome end
	return 1
end

function BrainrotConfig.GetUpgradeCost(currentLevel: number, rarity: string): number
	local base = BrainrotConfig.BaseIncomeByRarity[rarity] or 1
	return math.floor(base * 15 * currentLevel ^ 1.3)
end

function BrainrotConfig.GetIncome(brainrotId: string, level: number, rebirthMultiplier: number): number
	local base = BrainrotConfig.GetBaseIncome(brainrotId)
	return base * level * rebirthMultiplier
end

------------------------------------------------------------
-- VALIDATION
------------------------------------------------------------
function BrainrotConfig.IsValidBrainrot(brainrotId: string): boolean
	return BrainrotConfig.Catalog[brainrotId] ~= nil
end

function BrainrotConfig.IsValidRarity(rarity: string): boolean
	return BrainrotConfig.Rarities[rarity] ~= nil
end

return BrainrotConfig