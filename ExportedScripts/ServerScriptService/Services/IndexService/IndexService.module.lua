local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerManager = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerManager"))
local BrainrotConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BrainrotConfig"))

local IndexService = {}

local indexUpdatedRemote
local getIndexDataRemote

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

    return ensureRemote("IndexUpdated", "RemoteEvent"), ensureRemote("GetIndexData", "RemoteFunction")
end

local function getData(player)
    return PlayerManager.GetData(player)
end

local function ensureSeenTable(player)
    local data = getData(player)
    if not data then
        return nil
    end

    if type(data.SeenBrainrots) ~= "table" then
        data.SeenBrainrots = {}
    end

    return data.SeenBrainrots
end

function IndexService.GetSeenTable(player)
    return ensureSeenTable(player) or {}
end

function IndexService.MarkSeen(player, brainrotId)
    if type(brainrotId) ~= "string" then
        return false
    end

    if not BrainrotConfig.IsValidBrainrot(brainrotId) then
        return false
    end

    local seen = ensureSeenTable(player)
    if not seen then
        return false
    end

    if seen[brainrotId] then
        return false
    end

    seen[brainrotId] = true

    if indexUpdatedRemote then
        indexUpdatedRemote:FireClient(player, {
            SeenBrainrots = seen,
        })
    end

    return true
end

function IndexService.GetIndexData(player)
    local seen = IndexService.GetSeenTable(player)
    return {
        SeenBrainrots = seen,
        Catalog = BrainrotConfig.Catalog,
    }
end

function IndexService.Init()
    indexUpdatedRemote, getIndexDataRemote = ensureRemotes()

    getIndexDataRemote.OnServerInvoke = function(player)
        return IndexService.GetIndexData(player)
    end

    Players.PlayerAdded:Connect(function(player)
        task.spawn(function()
            while player.Parent == Players and not getData(player) do
                task.wait(0.25)
            end

            if player.Parent ~= Players then
                return
            end

            local data = getData(player)
            if not data then
                return
            end

            local seen = ensureSeenTable(player)

            if data.Inventory and type(data.Inventory.Brainrots) == "table" then
                for _, brainrot in pairs(data.Inventory.Brainrots) do
                    if type(brainrot) == "table" and type(brainrot.Id) == "string" and BrainrotConfig.IsValidBrainrot(brainrot.Id) then
                        seen[brainrot.Id] = true
                    end
                end
            end

            indexUpdatedRemote:FireClient(player, {
                SeenBrainrots = seen,
            })
        end)
    end)
end

return IndexService
