local ServerScriptService = game:GetService("ServerScriptService")

local PlayerManager = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerManager"))
local PlacementController = require(
	ServerScriptService:WaitForChild("Services"):WaitForChild("PlacementService"):WaitForChild("PlacementController")
)

local PlotPersistenceController = {}

function PlotPersistenceController.RestorePlot(player: Player)
	local data = PlayerManager.GetData(player)
	if not data then return end

	for _, brainrot in data.Inventory.Brainrots do
		if brainrot.PlacedStand then
			PlacementController.SpawnVisual(player, brainrot.PlacedStand, brainrot)
			PlacementController.RefreshStandGUI(player, brainrot.PlacedStand, brainrot)
		end
	end
end

function PlotPersistenceController.Init() end

return PlotPersistenceController