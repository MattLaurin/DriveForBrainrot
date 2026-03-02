local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FALLBACK_ICON = "rbxassetid://113016590802205"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BrainrotConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BrainrotConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local getIndexData = remotes:WaitForChild("GetIndexData")
local indexUpdated = remotes:WaitForChild("IndexUpdated")

local fullGui = playerGui:WaitForChild("FullGameGUI")
local indexFrame = fullGui:WaitForChild("IndexFrame")
local content = indexFrame:WaitForChild("Content")
local contentScroll = content:WaitForChild("ContentScrl"):WaitForChild("Content")
local template = contentScroll:WaitForChild("Common")
local listLayout = contentScroll:FindFirstChildOfClass("UIListLayout")

local progressRoot = content:WaitForChild("Progress")
local progressBar = progressRoot:WaitForChild("ProgressBar")
local valueLabel = progressRoot:WaitForChild("Uilistlayout"):WaitForChild("Value"):FindFirstChildOfClass("TextLabel")
local collectLabel = progressRoot:WaitForChild("Details"):WaitForChild("CollectNumber"):FindFirstChildOfClass("TextLabel")

local header = indexFrame:WaitForChild("Header")
local numbersA = header:WaitForChild("IndexOutof"):FindFirstChild("Numbersmth")
local numbersB = header:WaitForChild("IndexOutof"):FindFirstChild("Numbersmthb")

local baseProgressSize = progressBar.Size
local cardsById = {}
local seenMap = {}

local function sortedCatalogIds()
    local ids = {}
    for id, _ in pairs(BrainrotConfig.Catalog) do
        table.insert(ids, id)
    end

    table.sort(ids, function(a, b)
        local na = tonumber(a)
        local nb = tonumber(b)
        if na and nb then
            return na < nb
        end
        return a < b
    end)

    return ids
end

local function getImageForBrainrot(id, entry)
    local image = entry and (entry.Image or entry.Icon or entry.ImageId)
    if type(image) == "string" and image ~= "" then
        return image
    end
    return FALLBACK_ICON
end

local function setCardSeenState(card, isSeen)
    local icon = card:FindFirstChild("IconPlaceholder")
    if icon and icon:IsA("ImageLabel") then
        icon.ImageColor3 = isSeen and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(0, 0, 0)
    end
end

local function setCardData(card, id, entry)
    local rarity = entry.Rarity or "Common"
    local displayName = entry.DisplayName or id

    card.Name = "Card_" .. id

    local icon = card:FindFirstChild("IconPlaceholder")
    if icon and icon:IsA("ImageLabel") then
        icon.Image = getImageForBrainrot(id, entry)
    end

    local moneyLabel = card:FindFirstChild("MoneyMaking")
    if moneyLabel and moneyLabel:IsA("TextLabel") then
        moneyLabel.Text = BrainrotConfig.FormatMoney(entry.BaseIncome or 0) .. "/s"
    end

    local variants = card:FindFirstChild("ColourVarients")
    if variants and variants:IsA("Frame") then
        for _, variantFrame in ipairs(variants:GetChildren()) do
            if variantFrame:IsA("Frame") then
                local isTarget = string.lower(variantFrame.Name) == string.lower(rarity)
                variantFrame.Visible = isTarget

                if isTarget then
                    for _, desc in ipairs(variantFrame:GetDescendants()) do
                        if desc:IsA("TextLabel") and string.find(string.upper(desc.Name), "NAME") then
                            desc.Text = displayName
                        end
                    end
                end
            end
        end
    end
end

local function updateHeaderProgress()
    local total = 0
    local seen = 0

    for id, _ in pairs(BrainrotConfig.Catalog) do
        total += 1
        if seenMap[id] then
            seen += 1
        end
    end

    local text = string.format("%d/%d", seen, total)

    if valueLabel then
        valueLabel.Text = text
    end
    if collectLabel then
        collectLabel.Text = "Collect " .. tostring(seen)
    end
    if numbersA and numbersA:IsA("TextLabel") then
        numbersA.Text = text
    end
    if numbersB and numbersB:IsA("TextLabel") then
        numbersB.Text = text
    end

    local ratio = (total > 0) and (seen / total) or 0
    progressBar.Size = UDim2.new(baseProgressSize.X.Scale * ratio, baseProgressSize.X.Offset * ratio, baseProgressSize.Y.Scale, baseProgressSize.Y.Offset)
end

local function rebuildCards()
    cardsById = {}

    for _, child in ipairs(contentScroll:GetChildren()) do
        if child:IsA("Frame") and child ~= template then
            child:Destroy()
        end
    end

    local ids = sortedCatalogIds()
    for _, id in ipairs(ids) do
        local entry = BrainrotConfig.Catalog[id]
        local card = template:Clone()
        card.Visible = true
        card.Parent = contentScroll
        setCardData(card, id, entry)
        setCardSeenState(card, seenMap[id] == true)
        cardsById[id] = card
    end

    template.Visible = false

    if listLayout then
        task.defer(function()
            contentScroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 8)
        end)
    end

    updateHeaderProgress()
end

local function applySeenUpdate(newSeen)
    if type(newSeen) ~= "table" then
        return
    end

    seenMap = {}
    for id, value in pairs(newSeen) do
        if value then
            seenMap[id] = true
        end
    end

    for id, card in pairs(cardsById) do
        if card and card.Parent then
            setCardSeenState(card, seenMap[id] == true)
        end
    end

    updateHeaderProgress()
end

local function initialLoad()
    local ok, payload = pcall(function()
        return getIndexData:InvokeServer()
    end)

    if not ok or type(payload) ~= "table" then
        warn("[IndexClient] Failed to get index data")
        rebuildCards()
        return
    end

    if type(payload.SeenBrainrots) == "table" then
        for id, value in pairs(payload.SeenBrainrots) do
            if value then
                seenMap[id] = true
            end
        end
    end

    rebuildCards()
end

indexUpdated.OnClientEvent:Connect(function(payload)
    if type(payload) == "table" and type(payload.SeenBrainrots) == "table" then
        applySeenUpdate(payload.SeenBrainrots)
    end
end)

if listLayout then
    listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        contentScroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 8)
    end)
end

initialLoad()
