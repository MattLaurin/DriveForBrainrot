-- ServerScriptService/GameManager (Script)
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

------------------------------------------------------------
-- PHASE 1: Boot modules in dependency order
------------------------------------------------------------
local bootOrder = {
	ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerManager"),
	ServerScriptService:WaitForChild("Services"):WaitForChild("PlotService"):WaitForChild("PlotManager"),
	ServerScriptService:WaitForChild("Services"):WaitForChild("DriveService"):WaitForChild("DriveController"),
	ServerScriptService:WaitForChild("Services"):WaitForChild("RebirthService"):WaitForChild("RebirthService"),
	ServerScriptService:WaitForChild("Services"):WaitForChild("InventoryService"):WaitForChild("InventoryController"),
	ServerScriptService:WaitForChild("Services"):WaitForChild("PickupService"):WaitForChild("PickupController"),
	ServerScriptService:WaitForChild("Services"):WaitForChild("PlacementService"):WaitForChild("PlacementController"),
	ServerScriptService:WaitForChild("Services"):WaitForChild("PlotPersistService"):WaitForChild("PlotPersistenceController"),
	ServerScriptService:WaitForChild("Services"):WaitForChild("BrMoneyProductionService"):WaitForChild("BrMoneyProductionController"),
	ServerScriptService:WaitForChild("Services"):WaitForChild("OfflineProductionService"):WaitForChild("OfflineProductionController"),
}

local loaded = {}
local modules = {}

for _, moduleScript in bootOrder do
	local success, result = pcall(require, moduleScript)
	if success then
		loaded[moduleScript] = true
		modules[moduleScript.Name] = result
		if type(result) == "table" and result.Init then
			result.Init()
			print("[GameManager] Initialized:", moduleScript:GetFullName())
		end
	else
		warn("[GameManager] Failed to load:", moduleScript:GetFullName(), result)
	end
end

------------------------------------------------------------
-- PHASE 2: Auto-load anything not in boot order
------------------------------------------------------------
local function loadRemaining(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("ModuleScript") and not loaded[child] then
			local success, result = pcall(require, child)
			if success then
				loaded[child] = true
				modules[child.Name] = result
				if type(result) == "table" and result.Init then
					result.Init()
					print("[GameManager] Late-initialized:", child:GetFullName())
				end
			else
				warn("[GameManager] Failed to load:", child:GetFullName(), result)
			end
		elseif child:IsA("Folder") then
			loadRemaining(child)
		end
	end
end

loadRemaining(ServerScriptService)

------------------------------------------------------------
-- PHASE 3: When a player joins and data is ready,
-- restore their tools, stand visuals, collect buttons,
-- and award offline earnings into their stands.
------------------------------------------------------------
local PlayerManager = modules["PlayerManager"]
local PickupController = modules["PickupController"]
local PlotPersistenceController = modules["PlotPersistenceController"]
local BrMoneyProductionController = modules["BrMoneyProductionController"]
local OfflineProductionController = modules["OfflineProductionController"]

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		-- Wait for profile data to load
		while not PlayerManager.GetData(player) do
			task.wait(0.5)
		end

		-- Wait for plot assignment
		task.wait(1)

		-- Restore backpack tools for carried brainrots
		if PickupController and PickupController.RestoreTools then
			PickupController.RestoreTools(player)
		end

		-- Restore stand visuals for placed brainrots
		if PlotPersistenceController and PlotPersistenceController.RestorePlot then
			PlotPersistenceController.RestorePlot(player)
		end

		-- Setup collect buttons on all stands
		if BrMoneyProductionController and BrMoneyProductionController.SetupPlot then
			BrMoneyProductionController.SetupPlot(player)
		end

		-- Award offline earnings into stand accumulation
		if OfflineProductionController and OfflineProductionController.AwardOfflineEarnings then
			OfflineProductionController.AwardOfflineEarnings(player)
		end
	end)
end)

print("[GameManager] All modules loaded!")