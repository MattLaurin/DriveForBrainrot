local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("FullGameGUI")
local template = gui:WaitForChild("TemplateEfect")

local speedRemotes = ReplicatedStorage:WaitForChild("SpeedRemotes", 30)
if not speedRemotes then
	warn("[SpeedEffectClient] SpeedRemotes missing")
	return
end

local speedGained = speedRemotes:WaitForChild("SpeedGained", 30)
if not speedGained then
	warn("[SpeedEffectClient] SpeedGained missing")
	return
end

local function showEffect(amount: number)
	local clone = template:Clone()
	clone.Name = "EfectActiv"
	clone.Parent = gui
	clone.Visible = true

	local value = math.max(1, math.floor(amount or 1))	
	clone.Text = "+" .. tostring(value) .. " SPEED"

	-- Make it much larger and brighter for readability
	clone.Size = UDim2.new(0, 420, 0, 130)
	clone.TextScaled = false
	clone.TextSize = 64
	clone.Font = Enum.Font.GothamBlack
	clone.TextColor3 = Color3.fromRGB(255, 255, 80) -- bright yellow
	clone.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	clone.TextStrokeTransparency = 0
	clone.TextTransparency = 0
	clone.BackgroundTransparency = 1
	clone.ZIndex = 999

	local randomX = math.random(38, 62) / 100
	local randomY = math.random(48, 58) / 100
	clone.Position = UDim2.new(randomX, -210, randomY, -65)
	clone:TweenPosition(
		UDim2.new(randomX, -210, randomY - 0.22, -65),
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Quart,
		0.95,
		true
	)

	Debris:AddItem(clone, 1.2)
end

speedGained.OnClientEvent:Connect(function(amount)
	showEffect(amount)
end)

print("[SpeedEffectClient] Ready!")
