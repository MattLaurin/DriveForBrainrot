--[[
	StarterPlayer/StarterPlayerScripts/MoneyHUD.lua (LocalScript)
	
	Wires the FullGameGUI MoneyDisplay to the player's leaderstats.Money.
	Updates the MoneyCount TextLabel in real-time using BrainrotConfig.FormatMoney.
--]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BrainrotConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BrainrotConfig"))

------------------------------------------------------------
-- WAIT FOR UI ELEMENTS
------------------------------------------------------------
local fullGui = playerGui:WaitForChild("FullGameGUI")
local hudFrame = fullGui:WaitForChild("HUDFrame")
local bottomLeft = hudFrame:WaitForChild("BottomLeftInfo")
local moneyDisplay = bottomLeft:WaitForChild("MoneyDisplay")
local moneyCount = moneyDisplay:WaitForChild("MoneyCount")

------------------------------------------------------------
-- WAIT FOR LEADERSTATS
------------------------------------------------------------
local leaderstats = player:WaitForChild("leaderstats")
local moneyValue = leaderstats:WaitForChild("Money")

------------------------------------------------------------
-- UPDATE FUNCTION
------------------------------------------------------------
local function updateMoneyLabel()
	moneyCount.Text = BrainrotConfig.FormatMoney(moneyValue.Value)
end

-- Set initial value
updateMoneyLabel()

-- Update whenever money changes
moneyValue.Changed:Connect(updateMoneyLabel)