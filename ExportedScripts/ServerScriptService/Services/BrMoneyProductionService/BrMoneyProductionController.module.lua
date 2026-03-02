--[[
	ServerScriptService/Services/BrMoneyProductionService/BrMoneyProductionController.lua
	
	SOLE RESPONSIBILITY: Placed brainrots generate money per second.
	Updates the stand Button Cash label and the BrainrotVisual billboard.
	
	FIX: Added .Touched collection on the Touch part so players can
	     walk over the button to collect, in addition to ClickDetector.
--]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerManager = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerManager"))
local DriveConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DriveConfig"))
local BrainrotConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BrainrotConfig"))
local PlotManager = require(
	ServerScriptService:WaitForChild("Services"):WaitForChild("PlotService"):WaitForChild("PlotManager")
)

local BrMoneyProductionController = {}

------------------------------------------------------------
-- HELPERS: Find stand parts
------------------------------------------------------------
local function getStandModel(player: Player, standKey: string): Model?
	local plot = PlotManager.GetPlot(player)
	if not plot then return nil end

	local floorNum, standNum = standKey:match("^(%d+)_(%d+)$")
	if not floorNum then return nil end

	local floor = plot.Floors:FindFirstChild(tostring(floorNum))
	if not floor then return nil end

	local stands = floor:FindFirstChild("Stands")
	if not stands then return nil end

	return stands:FindFirstChild(tostring(standNum))
end

------------------------------------------------------------
-- UPDATE STAND CASH BUTTON LABEL
------------------------------------------------------------
local function updateCashLabel(player: Player, standKey: string, totalEarned: number)
	local standModel = getStandModel(player, standKey)
	if not standModel then return end

	local button = standModel:FindFirstChild("Button")
	if not button then return end

	local touch = button:FindFirstChild("Touch")
	if not touch then return end

	local gui = touch:FindFirstChild("SurfaceGui")
	if not gui then return end

	local frame = gui:FindFirstChild("Frame")
	if not frame then return end

	local cash = frame:FindFirstChild("Cash")
	if not cash then return end

	cash.Text = BrainrotConfig.FormatMoney(totalEarned)
end

------------------------------------------------------------
-- UPDATE BRAINROT BILLBOARD ON STAND
------------------------------------------------------------
local function updateBillboard(player: Player, standKey: string, brainrotData: { [string]: any }, income: number)
	local standModel = getStandModel(player, standKey)
	if not standModel then return end

	local stand = standModel:FindFirstChild("Stand")
	if not stand then return end

	local platform = stand:FindFirstChild("Platform")
	if not platform then return end

	local visual = platform:FindFirstChild("BrainrotVisual")
	if not visual then return end

	local billboard = visual:FindFirstChild("EntityTagBillboard")
	if not billboard then return end

	local root = billboard:FindFirstChild("Root")
	if not root then return end

	local nameLabel = root:FindFirstChild("Name")
	local typeLabel = root:FindFirstChild("Type")
	local rarityLabel = root:FindFirstChild("Rarity")
	local rateLabel = root:FindFirstChild("Rate")

	local config = BrainrotConfig.Catalog[brainrotData.Id]
	local displayName = config and config.DisplayName or brainrotData.Id

	if nameLabel then
		nameLabel.Text = displayName
	end

	if typeLabel then
		typeLabel.Text = "Lv." .. brainrotData.Level
	end

	if rarityLabel then
		rarityLabel.Text = brainrotData.Rarity
		local rarityInfo = BrainrotConfig.Rarities[brainrotData.Rarity]
		if rarityInfo then
			rarityLabel.TextColor3 = rarityInfo.Color
		end
	end

	if rateLabel then
		rateLabel.Text = BrainrotConfig.FormatMoney(income) .. "/s"
	end
end

------------------------------------------------------------
-- BUTTON PRESS ANIMATION
-- Dips the Touch part down then tweens it back up
------------------------------------------------------------
local PRESS_DEPTH = 0.35       -- studs to push down
local PRESS_DOWN_TIME = 0.08   -- seconds (fast snap down)
local PRESS_UP_TIME = 0.15     -- seconds (slightly slower return)

local originalPositions = {}   -- [touch part] = original CFrame
local animatingButtons = {}    -- [touch part] = true (prevent overlapping anims)

local function playPressAnimation(touch: BasePart)
	if animatingButtons[touch] then return end
	animatingButtons[touch] = true

	-- Cache the original position on first press
	if not originalPositions[touch] then
		originalPositions[touch] = touch.CFrame
	end

	local originCF = originalPositions[touch]
	local pressedCF = originCF - Vector3.new(0, PRESS_DEPTH, 0)

	-- Snap down
	local tweenDown = TweenService:Create(touch, TweenInfo.new(
		PRESS_DOWN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out
		), { CFrame = pressedCF })

	-- Bounce back up
	local tweenUp = TweenService:Create(touch, TweenInfo.new(
		PRESS_UP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out
		), { CFrame = originCF })

	tweenDown:Play()
	tweenDown.Completed:Once(function()
		tweenUp:Play()
		tweenUp.Completed:Once(function()
			animatingButtons[touch] = nil
		end)
	end)
end

------------------------------------------------------------
-- COLLECT LOGIC (shared by both Touched and ClickDetector)
------------------------------------------------------------
local collectCooldowns = {} -- [player_standKey] = tick

local function doCollect(player: Player, standKey: string)
	local cooldownKey = player.UserId .. "_" .. standKey
	local now = tick()
	if collectCooldowns[cooldownKey] and (now - collectCooldowns[cooldownKey]) < 0.5 then
		return -- cooldown
	end
	collectCooldowns[cooldownKey] = now

	local data = PlayerManager.GetData(player)
	if not data then return end

	-- Find the brainrot on this stand
	local brainrot = nil
	for _, b in data.Inventory.Brainrots do
		if b.PlacedStand == standKey then
			brainrot = b
			break
		end
	end
	if not brainrot then return end

	-- Calculate accumulated money (stored per stand)
	local accKey = "AccumulatedMoney_" .. standKey
	local accumulated = data[accKey] or 0

	if accumulated <= 0 then return end

	-- Play the button press animation
	local standModel = getStandModel(player, standKey)
	if standModel then
		local button = standModel:FindFirstChild("Button")
		if button then
			local touchPart = button:FindFirstChild("Touch")
			if touchPart then
				playPressAnimation(touchPart)
			end
		end
	end

	-- Give money
	local leaderstats = player:FindFirstChild("leaderstats")
	local moneyValue = leaderstats and leaderstats:FindFirstChild("Money")
	if moneyValue then
		moneyValue.Value += math.floor(accumulated)
	end

	-- Reset accumulated
	data[accKey] = 0
	updateCashLabel(player, standKey, 0)
end

------------------------------------------------------------
-- HELPER: Get the player who owns a plot from a part inside it
------------------------------------------------------------
local function getPlotOwnerFromPart(part: BasePart): Player?
	-- Walk up from the Touch part to find the Plot model,
	-- then match it to the player whose plot it is.
	local current = part.Parent
	while current and current ~= workspace do
		-- Check if this is a plot assigned to any player
		for _, p in Players:GetPlayers() do
			local plot = PlotManager.GetPlot(p)
			if plot and current == plot then
				return p
			end
		end
		current = current.Parent
	end
	return nil
end

------------------------------------------------------------
-- COLLECT BUTTON SETUP (Touch part)
-- FIX: Now wires BOTH .Touched (walk-over) AND ClickDetector (click)
------------------------------------------------------------
local function setupCollectButton(player: Player, standKey: string)
	local standModel = getStandModel(player, standKey)
	if not standModel then return end

	local button = standModel:FindFirstChild("Button")
	if not button then return end

	local touch = button:FindFirstChild("Touch")
	if not touch then return end

	-- Prevent double-wiring
	local existing = touch:FindFirstChild("CollectClick")
	if existing then return end -- already wired

	-- Make sure Touch part can be touched by characters
	touch.CanTouch = true

	----------------------------------------------------
	-- METHOD 1: ClickDetector (click-to-collect, works on desktop)
	----------------------------------------------------
	local click = Instance.new("ClickDetector")
	click.Name = "CollectClick"
	click.MaxActivationDistance = 15
	click.Parent = touch

	click.MouseClick:Connect(function(clickPlayer: Player)
		if clickPlayer ~= player then return end
		doCollect(player, standKey)
	end)

	----------------------------------------------------
	-- METHOD 2: .Touched (walk-over collection, works on all platforms)
	----------------------------------------------------
	touch.Touched:Connect(function(hit: BasePart)
		-- Check if the touching part belongs to a character
		local character = hit.Parent
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end

		-- Find which player this character belongs to
		local touchPlayer = Players:GetPlayerFromCharacter(character)
		if not touchPlayer then return end

		-- Only the plot owner can collect
		if touchPlayer ~= player then return end

		doCollect(player, standKey)
	end)
end

------------------------------------------------------------
-- PRODUCTION LOOP: Every second, accumulate money for placed brainrots
------------------------------------------------------------
local TICK_RATE = 1 -- seconds

local function productionTick()
	for _, player in Players:GetPlayers() do
		local data = PlayerManager.GetData(player)
		if not data then continue end

		local rebirthLevel = data.RebirthLevel or 0

		for _, brainrot in data.Inventory.Brainrots do
			if not brainrot.PlacedStand then continue end

			local income = BrainrotConfig.GetIncome(brainrot.Id, brainrot.Level, 
				DriveConfig.GetRebirthMultiplier(rebirthLevel))

			-- Accumulate
			local accKey = "AccumulatedMoney_" .. brainrot.PlacedStand
			data[accKey] = (data[accKey] or 0) + income

			-- Update visuals
			updateCashLabel(player, brainrot.PlacedStand, data[accKey])
			updateBillboard(player, brainrot.PlacedStand, brainrot, income)
		end
	end
end

------------------------------------------------------------
-- SETUP COLLECT BUTTONS FOR A PLAYER'S PLOT
------------------------------------------------------------
function BrMoneyProductionController.SetupPlot(player: Player)
	local data = PlayerManager.GetData(player)
	if not data then return end

	local plot = PlotManager.GetPlot(player)
	if not plot then return end

	local floors = plot:FindFirstChild("Floors")
	if not floors then return end

	for _, floor in floors:GetChildren() do
		local stands = floor:FindFirstChild("Stands")
		if not stands then continue end

		for _, standModel in stands:GetChildren() do
			if not standModel:IsA("Model") then continue end
			local key = floor.Name .. "_" .. standModel.Name
			setupCollectButton(player, key)
		end
	end
end

------------------------------------------------------------
-- INIT
------------------------------------------------------------
function BrMoneyProductionController.Init()
	-- Production loop
	task.spawn(function()
		while true do
			task.wait(TICK_RATE)
			productionTick()
		end
	end)
end

return BrMoneyProductionController