local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local getSpinCount = remotes:WaitForChild("GetSpinCount")
local requestSpin = remotes:WaitForChild("RequestSpin")
local spinCountUpdated = remotes:WaitForChild("SpinCountUpdated")
local getSpinStatus = remotes:WaitForChild("GetSpinStatus")
local spinTimerUpdated = remotes:WaitForChild("SpinTimerUpdated")
local requestSpinPurchase = remotes:WaitForChild("RequestSpinPurchase")

local fullGui = playerGui:WaitForChild("FullGameGUI")
local spinFrame = fullGui:WaitForChild("SpinFrame")
local spinButtons = spinFrame:WaitForChild("SpinButtons")
local spinButton = spinButtons:WaitForChild("SpinButton")
local spinText = spinButton:WaitForChild("SpinText")
local wheelFrame = spinFrame:WaitForChild("WheelFrame")

local timeRoot = spinFrame:FindFirstChild("Time")
local timeInner = timeRoot and timeRoot:FindFirstChild("Time")
local timeA = timeInner and timeInner:FindFirstChild("TimeA")
local timeB = timeInner and timeInner:FindFirstChild("TimeB")

local HOVER_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(0.09, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local RELEASE_INFO = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DEFAULT_ROT = 0
local HOVER_ROT = -8
local PRESS_ROT = 12
local HOVER_SCALE = 1.12
local PRESS_SCALE = 0.92
local NORMAL_SCALE = 1

local function tween(instance, info, goals)
    local t = TweenService:Create(instance, info, goals)
    t:Play()
    return t
end

local function getWheelContainer()
    for _, child in ipairs(wheelFrame:GetChildren()) do
        if child.Name == "Background" and child:IsA("Frame") then
            return child
        end
    end

    local fallback = wheelFrame:FindFirstChild("Background")
    if fallback and fallback:IsA("GuiObject") then
        return fallback
    end

    return nil
end

local wheelContainer = getWheelContainer()
if not wheelContainer then
    warn("[SpinHud] Wheel container not found")
    return
end

local function getSectors()
    local sectors = {}
    for _, child in ipairs(wheelContainer:GetChildren()) do
        if child:IsA("GuiObject") and string.sub(child.Name, 1, 6) == "Sector" then
            table.insert(sectors, child)
        end
    end

    table.sort(sectors, function(a, b)
        return a.Name < b.Name
    end)

    return sectors
end

local sectors = getSectors()
local sectorCount = #sectors

local currentSpins = 0
local secondsToNextSpin = 30 * 60
local spinning = false
local timerAccumulator = 0

local function setSpinText(value)
    spinText.Text = string.format("SPIN! [%dx]", math.max(0, math.floor(value)))
end


local function setTimeText(seconds)
    local s = math.max(0, math.floor(seconds))
    local minutes = math.floor(s / 60)
    local secs = s % 60
    local formatted = string.format("%02d:%02d", minutes, secs)

    if timeA and timeA:IsA("TextLabel") then
        timeA.Text = formatted
    end
    if timeB and timeB:IsA("TextLabel") then
        timeB.Text = formatted
    end
end

local function applyStatus(spins, seconds)
    if type(spins) == "number" then
        currentSpins = spins
        setSpinText(currentSpins)
    end
    if type(seconds) == "number" then
        secondsToNextSpin = math.max(0, math.floor(seconds))
        setTimeText(secondsToNextSpin)
    end
end

local function refreshStatusFromServer()
    local ok, result = pcall(function()
        return getSpinStatus:InvokeServer()
    end)

    if ok and type(result) == "table" then
        applyStatus(result.Spins, result.SecondsToNext)
        return
    end

    local countOk, count = pcall(function()
        return getSpinCount:InvokeServer()
    end)
    if countOk and type(count) == "number" then
        applyStatus(count, secondsToNextSpin)
    else
        warn("[SpinHud] Failed to fetch spin status", result)
    end
end

spinCountUpdated.OnClientEvent:Connect(function(spins, seconds)
    applyStatus(spins, seconds)
end)

spinTimerUpdated.OnClientEvent:Connect(function(seconds)
    if type(seconds) == "number" then
        secondsToNextSpin = math.max(0, math.floor(seconds))
        setTimeText(secondsToNextSpin)
    end
end)

RunService.Heartbeat:Connect(function(dt)
    timerAccumulator += dt
    while timerAccumulator >= 1 do
        timerAccumulator -= 1
        if secondsToNextSpin > 0 then
            secondsToNextSpin -= 1
            setTimeText(secondsToNextSpin)
        end
    end
end)

local function spinWheelToIndex(landedIndex)
    if sectorCount <= 0 then
        warn("[SpinHud] No sectors found in wheel")
        return nil
    end

    local index = math.clamp(math.floor(landedIndex), 1, sectorCount)
    local segmentAngle = 360 / sectorCount
    local fullTurns = math.random(5, 8)

    local targetCenter = (index - 1) * segmentAngle + (segmentAngle / 2)
    local targetNormalized = -targetCenter

    local currentRotation = wheelContainer.Rotation
    local currentNormalized = currentRotation % 360
    local delta = targetNormalized - currentNormalized
    while delta <= 0 do
        delta += 360
    end

    local totalDelta = (fullTurns * 360) + delta
    local rotateTween = TweenService:Create(
        wheelContainer,
        TweenInfo.new(4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        { Rotation = currentRotation + totalDelta }
    )

    rotateTween:Play()
    rotateTween.Completed:Wait()

    return sectors[index], index
end

local function getOrMakeScale(guiObject)
    local scale = guiObject:FindFirstChildOfClass("UIScale")
    if not scale then
        scale = Instance.new("UIScale")
        scale.Scale = NORMAL_SCALE
        scale.Parent = guiObject
    end
    return scale
end

local function getIcon(guiObject)
    local byName = guiObject:FindFirstChild("icon67") or guiObject:FindFirstChild("Settings")
    if byName and byName:IsA("GuiObject") then
        return byName
    end

    for _, child in ipairs(guiObject:GetChildren()) do
        if child:IsA("ImageLabel") then
            local n = string.lower(child.Name)
            if not string.match(n, "^bg") and n ~= "background" and n ~= "gradient" and not string.find(n, "stroke") then
                return child
            end
        end
    end

    return nil
end

local function ensureHitbox(target)
    local hitbox = target:FindFirstChild("_SpinHitbox")
    if hitbox and hitbox:IsA("TextButton") then
        return hitbox
    end

    if hitbox then
        hitbox:Destroy()
    end

    hitbox = Instance.new("TextButton")
    hitbox.Name = "_SpinHitbox"
    hitbox.BackgroundTransparency = 1
    hitbox.Text = ""
    hitbox.AutoButtonColor = false
    hitbox.Size = UDim2.fromScale(1, 1)
    hitbox.Position = UDim2.fromScale(0, 0)
    hitbox.ZIndex = target.ZIndex + 10
    hitbox.Parent = target

    return hitbox
end

local function setupInteractiveButton(target, onActivated)
    if not target:IsA("GuiObject") then
        return
    end

    local hitbox = ensureHitbox(target)
    local scale = getOrMakeScale(target)
    local icon = getIcon(target)

    local hovering = false
    local pressing = false

    local function applyState()
        if pressing then
            if icon then
                tween(icon, PRESS_INFO, { Rotation = PRESS_ROT })
            end
            tween(scale, PRESS_INFO, { Scale = PRESS_SCALE })
        elseif hovering then
            if icon then
                tween(icon, HOVER_INFO, { Rotation = HOVER_ROT })
            end
            tween(scale, HOVER_INFO, { Scale = HOVER_SCALE })
        else
            if icon then
                tween(icon, RELEASE_INFO, { Rotation = DEFAULT_ROT })
            end
            tween(scale, RELEASE_INFO, { Scale = NORMAL_SCALE })
        end
    end

    hitbox.MouseEnter:Connect(function()
        hovering = true
        applyState()
    end)

    hitbox.MouseLeave:Connect(function()
        hovering = false
        pressing = false
        applyState()
    end)

    hitbox.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            pressing = true
            applyState()
        end
    end)

    hitbox.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            pressing = false
            applyState()
        end
    end)

    hitbox.Activated:Connect(function()
        tween(scale, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 0.88 })
        task.delay(0.07, applyState)
        if onActivated then
            onActivated()
        end
    end)
end

local function closeSpinFrame()
    spinFrame.Visible = false
end

local function promptSpinPack(amount)
    local ok, success, err = pcall(function()
        return requestSpinPurchase:InvokeServer(amount)
    end)

    if not ok then
        warn("[SpinHud] Failed to request spin purchase", success)
        return
    end

    if not success then
        warn("[SpinHud] Spin purchase rejected: " .. tostring(err))
    end
end

local function onSpinActivated()
    if spinning then
        return
    end

    if currentSpins <= 0 then
        print("[SpinHud] No spins available.")
        return
    end

    if sectorCount <= 0 then
        print("[SpinHud] Wheel has no sectors.")
        return
    end

    spinning = true

    local ok, success, landedIndex, spinsLeft, secondsLeft = pcall(function()
        return requestSpin:InvokeServer(sectorCount)
    end)

    if not ok then
        warn("[SpinHud] Spin request failed", success)
        spinning = false
        return
    end

    if not success then
        print("[SpinHud] Server denied spin request.")
        applyStatus(spinsLeft, secondsLeft)
        spinning = false
        return
    end

    applyStatus(spinsLeft, secondsLeft)

    local sector, index = spinWheelToIndex(tonumber(landedIndex) or 1)
    local landedName = sector and sector.Name or ("Sector" .. tostring(index or landedIndex or "?"))
    print(string.format("[SpinHud] Landed on %s", landedName))

    spinning = false
end

setSpinText(0)
setTimeText(secondsToNextSpin)
refreshStatusFromServer()

setupInteractiveButton(spinButton, onSpinActivated)

for _, child in ipairs(spinButtons:GetChildren()) do
    if child ~= spinButton and child:IsA("GuiObject") and string.find(string.lower(child.Name), "button") then
        setupInteractiveButton(child, nil)
    end
end

local plusOne = spinButtons:FindFirstChild("Spin+1Button")
if plusOne and plusOne:IsA("GuiObject") then
    setupInteractiveButton(plusOne, function()
        promptSpinPack(1)
    end)
end

local plusFive = spinButtons:FindFirstChild("Spin+5Button")
if plusFive and plusFive:IsA("GuiObject") then
    setupInteractiveButton(plusFive, function()
        promptSpinPack(5)
    end)
end

local exitButton = spinFrame:FindFirstChild("Exitbutton")
if exitButton and exitButton:IsA("GuiObject") then
    setupInteractiveButton(exitButton, closeSpinFrame)
end
