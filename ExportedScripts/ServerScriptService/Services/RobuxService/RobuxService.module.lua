local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerManager = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerManager"))
local DriveConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DriveConfig"))
local RebirthService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("RebirthService"):WaitForChild("RebirthService"))
local SpinService = require(ServerScriptService:WaitForChild("Services"):WaitForChild("SpinService"):WaitForChild("SpinService"))

local RobuxService = {}

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
    Remotes = Instance.new("Folder")
    Remotes.Name = "Remotes"
    Remotes.Parent = ReplicatedStorage
end

local function ensureRemote(name, className)
    local remote = Remotes:FindFirstChild(name)
    if remote and remote.ClassName ~= className then
        remote:Destroy()
        remote = nil
    end
    if not remote then
        remote = Instance.new(className)
        remote.Name = name
        remote.Parent = Remotes
    end
    return remote
end

local PromptProduct = ensureRemote("PromptProduct", "RemoteEvent")
local PurchaseComplete = ensureRemote("PurchaseComplete", "RemoteEvent")
local HasGamepass = ensureRemote("HasGamepass", "RemoteFunction")

local function addSpeed(player, levels)
    local data = PlayerManager.GetData(player)
    if not data then return end
    data.SpeedLevel = math.min(data.SpeedLevel + levels, DriveConfig.MAX_SPEED_LEVEL)
    local ls = player:FindFirstChild("leaderstats")
    if ls then
        local s = ls:FindFirstChild("Speed")
        if s then
            s.Value = DriveConfig.GetEffectiveSpeed(data.SpeedLevel)
        end
    end
end

local function addFuel(player, levels)
    local data = PlayerManager.GetData(player)
    if not data then return end
    data.GasLevel = math.min(data.GasLevel + levels, DriveConfig.MAX_GAS_LEVEL)
end

local function addCarry(player, levels)
    local data = PlayerManager.GetData(player)
    if not data then return end
    data.CarryLevel = math.min(data.CarryLevel + levels, DriveConfig.MAX_CARRY_LEVEL)
end

local PRODUCTS = {
    [3548596307] = {
        Name = "Spin Pack",
        Handler = function(player)
            local pending = tonumber(player:GetAttribute("PendingSpinPurchaseAmount")) or 1
            local amount = (pending == 5) and 5 or 1
            player:SetAttribute("PendingSpinPurchaseAmount", nil)
            local total = SpinService.AddSpins(player, amount)
            print(string.format("[RobuxService] Granted %d spin(s) to %s from product 3548596307. Total=%d", amount, player.Name, total))
        end,
    },
}

local GAMEPASSES = {}
local gamepassCache = {}

local function processReceipt(receiptInfo)
    local playerId = receiptInfo.PlayerId
    local productId = receiptInfo.ProductId

    local player = Players:GetPlayerByUserId(playerId)
    if not player then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    local attempts = 0
    while not PlayerManager.GetData(player) and attempts < 20 do
        task.wait(0.5)
        attempts += 1
    end

    if not PlayerManager.GetData(player) then
        warn("[RobuxService] Data not loaded for " .. player.Name .. ", deferring receipt")
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    local product = PRODUCTS[productId]
    if not product then
        warn("[RobuxService] Unknown product ID: " .. tostring(productId))
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end

    local success, err = pcall(function()
        product.Handler(player)
    end)

    if success then
        print("[RobuxService] " .. player.Name .. " purchased: " .. product.Name)
        PurchaseComplete:FireClient(player, product.Name, productId)
        return Enum.ProductPurchaseDecision.PurchaseGranted
    else
        warn("[RobuxService] Failed to grant " .. product.Name .. " to " .. player.Name .. ": " .. tostring(err))
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
end

local function checkGamepassOwnership(player, gamepassId)
    local userId = player.UserId

    if gamepassCache[userId] and gamepassCache[userId][gamepassId] ~= nil then
        return gamepassCache[userId][gamepassId]
    end

    local success, owns = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(userId, gamepassId)
    end)

    if success then
        if not gamepassCache[userId] then
            gamepassCache[userId] = {}
        end
        gamepassCache[userId][gamepassId] = owns
        return owns
    end

    warn("[RobuxService] Failed to check gamepass " .. tostring(gamepassId) .. " for " .. player.Name)
    return false
end

function RobuxService.PlayerOwnsGamepass(player, gamepassId)
    return checkGamepassOwnership(player, gamepassId)
end

function RobuxService.PlayerHasPerk(player, perkKey)
    for gamepassId, info in pairs(GAMEPASSES) do
        if info.Perk == perkKey then
            return checkGamepassOwnership(player, gamepassId)
        end
    end
    return false
end

function RobuxService.PromptProduct(player, productId)
    pcall(function()
        MarketplaceService:PromptProductPurchase(player, productId)
    end)
end

function RobuxService.PromptGamepass(player, gamepassId)
    pcall(function()
        MarketplaceService:PromptGamePassPurchase(player, gamepassId)
    end)
end

function RobuxService.Init()
    MarketplaceService.ProcessReceipt = processReceipt

    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, wasPurchased)
        if wasPurchased then
            if gamepassCache[player.UserId] then
                gamepassCache[player.UserId][gamepassId] = true
            end
            print("[RobuxService] " .. player.Name .. " bought gamepass: " .. tostring(gamepassId))
            PurchaseComplete:FireClient(player, "Gamepass", gamepassId)
        end
    end)

    PromptProduct.OnServerEvent:Connect(function(player, productId)
        if type(productId) ~= "number" then return end
        RobuxService.PromptProduct(player, productId)
    end)

    HasGamepass.OnServerInvoke = function(player, gamepassId)
        if type(gamepassId) ~= "number" then return false end
        return checkGamepassOwnership(player, gamepassId)
    end

    Players.PlayerRemoving:Connect(function(player)
        gamepassCache[player.UserId] = nil
        player:SetAttribute("PendingSpinPurchaseAmount", nil)
    end)

    print("[RobuxService] Initialized")
end

return RobuxService
