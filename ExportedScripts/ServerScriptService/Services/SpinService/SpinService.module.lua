local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerManager = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerManager"))

local SpinService = {}

local PLAYTIME_PER_SPIN = 30 * 60 -- 30 minutes
local SPIN_PRODUCT_ID = 3548596307

local playerState = {} -- [player] = { elapsed = number, secondAccumulator = number }
local heartbeatConn

local spinCountUpdatedRemote
local getSpinCountRemote
local requestSpinRemote
local getSpinStatusRemote
local spinTimerUpdatedRemote
local requestSpinPurchaseRemote

local function ensureRemotes()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then
        remotes = Instance.new("Folder")
        remotes.Name = "Remotes"
        remotes.Parent = ReplicatedStorage
    end

    local function ensureRemote(name, className)
        local remote = remotes:FindFirstChild(name)
        if remote and remote.ClassName ~= className then
            remote:Destroy()
            remote = nil
        end
        if not remote then
            remote = Instance.new(className)
            remote.Name = name
            remote.Parent = remotes
        end
        return remote
    end

    local spinCountUpdated = ensureRemote("SpinCountUpdated", "RemoteEvent")
    local getSpinCount = ensureRemote("GetSpinCount", "RemoteFunction")
    local requestSpin = ensureRemote("RequestSpin", "RemoteFunction")
    local getSpinStatus = ensureRemote("GetSpinStatus", "RemoteFunction")
    local spinTimerUpdated = ensureRemote("SpinTimerUpdated", "RemoteEvent")
    local requestSpinPurchase = ensureRemote("RequestSpinPurchase", "RemoteFunction")

    return spinCountUpdated, getSpinCount, requestSpin, getSpinStatus, spinTimerUpdated, requestSpinPurchase
end

local function getState(player)
    local state = playerState[player]
    if not state then
        state = {
            elapsed = 0,
            secondAccumulator = 0,
        }
        playerState[player] = state
    end
    return state
end

local function getData(player)
    return PlayerManager.GetData(player)
end

local function getSpinsFromData(player)
    local data = getData(player)
    if not data then
        return 0
    end

    if type(data.Spins) ~= "number" then
        data.Spins = 0
    end

    return math.max(0, math.floor(data.Spins))
end

local function setSpinsInData(player, value)
    local data = getData(player)
    if not data then
        return false
    end

    data.Spins = math.max(0, math.floor(tonumber(value) or 0))
    return true
end

local function getSecondsToNextSpinFromState(state)
    local remaining = PLAYTIME_PER_SPIN - state.elapsed
    remaining = math.clamp(math.ceil(remaining), 0, PLAYTIME_PER_SPIN)
    if remaining <= 0 then
        remaining = PLAYTIME_PER_SPIN
    end
    return remaining
end

function SpinService.GetSpins(player)
    return getSpinsFromData(player)
end

function SpinService.GetSecondsToNextSpin(player)
    return getSecondsToNextSpinFromState(getState(player))
end

function SpinService.AddSpins(player, amount)
    local grant = math.max(0, math.floor(tonumber(amount) or 0))
    local current = getSpinsFromData(player)
    local newTotal = current + grant

    if not setSpinsInData(player, newTotal) then
        return current
    end

    local secondsToNext = getSecondsToNextSpinFromState(getState(player))
    if spinCountUpdatedRemote then
        spinCountUpdatedRemote:FireClient(player, newTotal, secondsToNext)
    end

    return newTotal
end

function SpinService.Init()
    spinCountUpdatedRemote, getSpinCountRemote, requestSpinRemote, getSpinStatusRemote, spinTimerUpdatedRemote, requestSpinPurchaseRemote = ensureRemotes()

    getSpinCountRemote.OnServerInvoke = function(player)
        return SpinService.GetSpins(player)
    end

    getSpinStatusRemote.OnServerInvoke = function(player)
        local state = getState(player)
        return {
            Spins = SpinService.GetSpins(player),
            SecondsToNext = getSecondsToNextSpinFromState(state),
        }
    end

    requestSpinPurchaseRemote.OnServerInvoke = function(player, amount)
        local packAmount = math.floor(tonumber(amount) or 0)
        if packAmount ~= 1 and packAmount ~= 5 then
            return false, "Invalid spin pack amount"
        end

        player:SetAttribute("PendingSpinPurchaseAmount", packAmount)

        local ok, err = pcall(function()
            MarketplaceService:PromptProductPurchase(player, SPIN_PRODUCT_ID)
        end)

        if not ok then
            warn("[SpinService] PromptProductPurchase failed: " .. tostring(err))
            return false, "Prompt failed"
        end

        return true
    end

    requestSpinRemote.OnServerInvoke = function(player, sectorCount)
        local state = getState(player)
        local spins = SpinService.GetSpins(player)

        if spins <= 0 then
            return false, nil, spins, getSecondsToNextSpinFromState(state)
        end

        spins -= 1
        setSpinsInData(player, spins)

        local secondsToNext = getSecondsToNextSpinFromState(state)
        spinCountUpdatedRemote:FireClient(player, spins, secondsToNext)

        local count = tonumber(sectorCount) or 8
        count = math.clamp(math.floor(count), 1, 64)
        local landedIndex = math.random(1, count)

        print(string.format("[SpinService] %s spun: landed index=%d, spins left=%d", player.Name, landedIndex, spins))
        return true, landedIndex, spins, secondsToNext
    end

    Players.PlayerAdded:Connect(function(player)
        playerState[player] = {
            elapsed = 0,
            secondAccumulator = 0,
        }
    end)

    Players.PlayerRemoving:Connect(function(player)
        playerState[player] = nil
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        getState(player)
    end

    if heartbeatConn then
        heartbeatConn:Disconnect()
        heartbeatConn = nil
    end

    heartbeatConn = RunService.Heartbeat:Connect(function(dt)
        for _, player in ipairs(Players:GetPlayers()) do
            local data = getData(player)
            if data then
                local state = getState(player)
                state.elapsed += dt
                state.secondAccumulator += dt

                if state.elapsed >= PLAYTIME_PER_SPIN then
                    local granted = math.floor(state.elapsed / PLAYTIME_PER_SPIN)
                    state.elapsed -= granted * PLAYTIME_PER_SPIN

                    local total = SpinService.AddSpins(player, granted)
                    print(string.format("[SpinService] Granted %d spin(s) to %s. Total=%d", granted, player.Name, total))
                end

                if state.secondAccumulator >= 1 then
                    state.secondAccumulator -= math.floor(state.secondAccumulator)
                    spinTimerUpdatedRemote:FireClient(player, getSecondsToNextSpinFromState(state))
                end
            end
        end
    end)

    print("[SpinService] Initialized")
end

return SpinService
