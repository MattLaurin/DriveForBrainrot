--[[
	ServerScriptService/Modules/PlayerManager.lua
--!strict
--]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ProfileStore = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("ProfileService"))

local PlayerManager = {}

local DATA_TEMPLATE = {
	-- Leaderstats
	Money = 0,
	Rebirth = 0,
	Speed = 1,

	-- Upgrades
	SpeedLevel = 1,
	CarryLevel = 1,
	GasLevel = 1,
	RebirthLevel = 0,

	-- Timestamps
	LastOnline = 0,

	-- Spins
	Spins = 0,

	-- Index
	SeenBrainrots = {},

	-- Inventory
	Inventory = {
		--[[
			Brainrots = {
				[uuid] = {
					Id = "SkibidiToilet",
					Rarity = "Rare",
					Level = 1,
					Mutation = nil,
					PlacedStand = nil,  -- "1_3" (floor_stand) or nil
				},
			}
		--]]
		Brainrots = {},
	},
}

local LEADERSTATS_KEYS = {
	{ Name = "Money",   Class = "IntValue" },
	{ Name = "Rebirth", Class = "IntValue" },
	{ Name = "Speed",   Class = "IntValue" },
}

local STORE_KEY = if RunService:IsStudio()
	then "DriveForStudio"
	else "DriveForBrainrots"

local Store = ProfileStore.New(STORE_KEY, DATA_TEMPLATE)
local Profiles: { [Player]: any } = {}

local function CreateLeaderstats(player: Player, data: { [string]: any })
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	for _, stat in LEADERSTATS_KEYS do
		local value = Instance.new(stat.Class)
		value.Name = stat.Name
		value.Value = data[stat.Name] or 0
		value.Parent = leaderstats
	end
	leaderstats.Parent = player
end

local function SyncLeaderstatsToData(player: Player, data: { [string]: any })
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end
	for _, stat in LEADERSTATS_KEYS do
		local obj = leaderstats:FindFirstChild(stat.Name)
		if obj then
			data[stat.Name] = obj.Value
		end
	end
end

function PlayerManager.Init()
	Players.PlayerAdded:Connect(function(player)
		PlayerManager.LoadProfile(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		PlayerManager.ReleaseProfile(player)
	end)
end

function PlayerManager.LoadProfile(player: Player)
	local profile = Store:StartSessionAsync("Player_" .. player.UserId)
	if not profile then
		warn("[PlayerManager]: Failed to load profile for", player.Name)
		player:Kick("Failed to load your data. Please rejoin.")
		return
	end

	if not player:IsDescendantOf(Players) then
		profile:EndSession()
		return
	end

	profile:Reconcile()
	profile:AddUserId(player.UserId)

	profile.OnSave:Connect(function()
		SyncLeaderstatsToData(player, profile.Data)
	end)

	profile.OnSessionEnd:Connect(function()
		Profiles[player] = nil
		if player:IsDescendantOf(Players) then
			player:Kick("Your session ended. Please rejoin.")
		end
	end)

	Profiles[player] = profile
	CreateLeaderstats(player, profile.Data)
end

function PlayerManager.ReleaseProfile(player: Player)
	local profile = Profiles[player]
	if profile then
		SyncLeaderstatsToData(player, profile.Data)
		profile:EndSession()
	end
end

function PlayerManager.GetProfile(player: Player)
	return Profiles[player]
end

function PlayerManager.GetData(player: Player): { [string]: any }?
	local profile = Profiles[player]
	return profile and profile.Data
end

return PlayerManager