-- ServerScriptService/PlotManager (ModuleScript)
local Players = game:GetService("Players")
local PlotManager = {}
local PlotsFolder = workspace.World.Plots
local plots = {}
local assignedPlots = {} -- [player] = plot

function PlotManager.Init()
	for _, plot in PlotsFolder:GetChildren() do
		if plot:IsA("Model") and plot:FindFirstChild("SpawnPoint") then
			table.insert(plots, plot)
		end
	end
	Players.PlayerAdded:Connect(PlotManager.AssignPlot)
	Players.PlayerRemoving:Connect(PlotManager.UnassignPlot)
end

function PlotManager.GetAvailablePlot()
	for _, plot in plots do
		local taken = false
		for _, assigned in assignedPlots do
			if assigned == plot then
				taken = true
				break
			end
		end
		if not taken then
			return plot
		end
	end
	return nil
end

function PlotManager.AssignPlot(player: Player)
	local plot = PlotManager.GetAvailablePlot()
	if not plot then
		warn("No available plots for", player.Name)
		return
	end
	assignedPlots[player] = plot
	plot:SetAttribute("OwnerId", player.UserId)
	plot:SetAttribute("OwnerName", player.Name)
	player:SetAttribute("AssignedPlot", plot.Name)

	local spawnPart = plot.SpawnPoint
	local function moveToSpawn(character: Model)
		local hrp = character:WaitForChild("HumanoidRootPart")
		hrp.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
	end
	if player.Character then
		moveToSpawn(player.Character)
	end
	player.CharacterAdded:Connect(moveToSpawn)
end

function PlotManager.UnassignPlot(player: Player)
	local plot = assignedPlots[player]
	if plot then
		plot:SetAttribute("OwnerId", nil)
		plot:SetAttribute("OwnerName", nil)
	end
	assignedPlots[player] = nil
	player:SetAttribute("AssignedPlot", nil)
end

function PlotManager.GetPlot(player: Player): Model?
	return assignedPlots[player]
end

function PlotManager.GetOwner(plot: Model): Player?
	for player, assignedPlot in assignedPlots do
		if assignedPlot == plot then
			return player
		end
	end
	return nil
end

return PlotManager