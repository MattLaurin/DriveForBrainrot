local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local spinCountUpdated = remotes:WaitForChild("SpinCountUpdated")
local getSpinStatus = remotes:FindFirstChild("GetSpinStatus")
local getSpinCount = remotes:WaitForChild("GetSpinCount")

local fullGui = playerGui:WaitForChild("FullGameGUI")
local hudFrame = fullGui:WaitForChild("HUDFrame")
local spinButton = hudFrame:WaitForChild("SpinButton")
local spinText = spinButton:WaitForChild("SpinText")
local numberLabel = spinText:WaitForChild("Number")

local function setCount(count)
    numberLabel.Text = string.format("%dx", math.max(0, math.floor(tonumber(count) or 0)))
end

local function refreshFromServer()
    if getSpinStatus and getSpinStatus:IsA("RemoteFunction") then
        local ok, status = pcall(function()
            return getSpinStatus:InvokeServer()
        end)
        if ok and type(status) == "table" and type(status.Spins) == "number" then
            setCount(status.Spins)
            return
        end
    end

    local ok, count = pcall(function()
        return getSpinCount:InvokeServer()
    end)
    if ok and type(count) == "number" then
        setCount(count)
    end
end

spinCountUpdated.OnClientEvent:Connect(function(spins)
    if type(spins) == "number" then
        setCount(spins)
    end
end)

setCount(0)
refreshFromServer()
