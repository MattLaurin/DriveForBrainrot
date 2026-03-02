local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BrainrotConfig"))

local SKIP_REBIRTH_PRODUCT_ID = 3548596307

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local fullGui = playerGui:WaitForChild("FullGameGUI")
local rebirthFrame = fullGui:WaitForChild("Rebirth")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local rebirthRemotes = remotes:WaitForChild("RebirthRemotes")
local getRebirthData = rebirthRemotes:WaitForChild("GetRebirthData")
local requestRebirth = rebirthRemotes:WaitForChild("RequestRebirth")
local rebirthUpdated = rebirthRemotes:WaitForChild("RebirthUpdated")
local promptProduct = remotes:WaitForChild("PromptProduct")

local content = rebirthFrame:WaitForChild("Content")
local buttons = content:WaitForChild("Buttons")
local rebirthButton = buttons:WaitForChild("RebirthButton") :: ImageButton
local skipRebirthButton = buttons:WaitForChild("SkipRebirthButton"):WaitForChild("SkipButton") :: ImageButton

local rebirthInfo = content:WaitForChild("RebirthInfo")
local rewardBeforeLabel = rebirthInfo:WaitForChild("Before"):WaitForChild("Content"):WaitForChild("RewardBefore") :: TextLabel
local rewardAfterLabel = rebirthInfo:WaitForChild("After"):WaitForChild("Content"):WaitForChild("RewardAfter") :: TextLabel
local rebirthBeforeLabel = rebirthInfo:WaitForChild("Rebirthbefore") :: TextLabel
local rebirthAfterLabel = rebirthInfo:WaitForChild("RebirthAfter") :: TextLabel

local barProgression = content:WaitForChild("BarInfo"):WaitForChild("BarProgression")
local barFill = barProgression:WaitForChild("Bar") :: GuiObject
local uiLayout = barProgression:WaitForChild("Uilayout")
local progressText = uiLayout:FindFirstChild("$0/$100") :: TextLabel
if not progressText then
	for _, child in ipairs(uiLayout:GetChildren()) do
		if child:IsA("TextLabel") and child.Text:find("/") then
			progressText = child
			break
		end
	end
end

local rebirthButtonText: TextLabel? = rebirthButton:FindFirstChild("REBIRTH") :: TextLabel

local defaultBarSize = barFill.Size

local function formatMoney(n: number): string
	return "$" .. BrainrotConfig.FormatMoney(math.floor(n))
end

local function formatMult(n: number): string
	local rounded = math.floor(n * 100 + 0.5) / 100
	if rounded % 1 == 0 then
		return "x" .. tostring(math.floor(rounded))
	end
	return "x" .. string.format("%.2f", rounded)
end

local function applyState(state)
	if not state then return end

	local beforeMult = tonumber(state.BeforeMultiplier) or 1
	local afterMult = tonumber(state.AfterMultiplier) or 1
	local money = tonumber(state.Money) or 0
	local cost = math.max(1, tonumber(state.Cost) or 1)
	local canRebirth = state.CanRebirth == true
	local level = tonumber(state.RebirthLevel) or 0

	rewardBeforeLabel.Text = formatMult(beforeMult)
	rewardAfterLabel.Text = formatMult(afterMult)
	rebirthBeforeLabel.Text = "Rebirth " .. tostring(level)
	rebirthAfterLabel.Text = "Rebirth " .. tostring(level + 1)

	if progressText then
		progressText.Text = formatMoney(money) .. "/" .. formatMoney(cost)
	end

	local alpha = math.clamp(money / cost, 0, 1)
	barFill.Size = UDim2.new(alpha, defaultBarSize.X.Offset, defaultBarSize.Y.Scale, defaultBarSize.Y.Offset)

	rebirthButton.Active = canRebirth
	rebirthButton.AutoButtonColor = canRebirth
	rebirthButton.ImageTransparency = canRebirth and 0 or 0.35
	if rebirthButtonText then
		rebirthButtonText.TextTransparency = canRebirth and 0 or 0.25
	end
end

local function refresh()
	local ok, response = pcall(function()
		return getRebirthData:InvokeServer()
	end)
	if ok and type(response) == "table" and response.Success and response.State then
		applyState(response.State)
	end
end

rebirthButton.Activated:Connect(function()
	local ok, response = pcall(function()
		return requestRebirth:InvokeServer("Normal")
	end)
	if ok and type(response) == "table" then
		if response.Success and response.State then
			applyState(response.State)
		else
			refresh()
		end
	end
end)

skipRebirthButton.Activated:Connect(function()
	promptProduct:FireServer(SKIP_REBIRTH_PRODUCT_ID)
end)

rebirthUpdated.OnClientEvent:Connect(function(state)
	applyState(state)
end)

local leaderstats = player:WaitForChild("leaderstats")
local moneyValue = leaderstats:WaitForChild("Money")
local rebirthValue = leaderstats:WaitForChild("Rebirth")
moneyValue.Changed:Connect(refresh)
rebirthValue.Changed:Connect(refresh)

refresh()
print("[RebirthClient] Ready!")
