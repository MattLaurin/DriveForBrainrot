--[[
	ServerScriptService/Services/OfflineProductionService/OfflineProductionController.lua
	
	SOLE RESPONSIBILITY: Calculate offline earnings and add them to stand accumulation.
	Player collects via the same Button collect click as online earnings.
--]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerManager = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerManager"))
local DriveConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DriveConfig"))
local BrainrotConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BrainrotConfig"))

local OfflineProductionController = {}

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------
local OFFLINE_RATE = 0.25         -- 25% of normal income while offline
local MAX_OFFLINE_SECONDS = 43200 -- Cap at 12 hours

------------------------------------------------------------
-- AWARD OFFLINE EARNINGS INTO STAND ACCUMULATION
------------------------------------------------------------
function OfflineProductionController.AwardOfflineEarnings(player: Player)
	local data = PlayerManager.GetData(player)
	if not data then return end

	local lastOnline = data.LastOnline
	if not lastOnline or lastOnline == 0 then return end

	local now = os.time()
	local elapsed = math.min(now - lastOnline, MAX_OFFLINE_SECONDS)

	if elapsed < 60 then return end -- Less than a minute, skip

	local rebirthLevel = data.RebirthLevel or 0
	local rebirthMult = DriveConfig.GetRebirthMultiplier(rebirthLevel)

	local totalOffline = 0

	for _, brainrot in data.Inventory.Brainrots do
		if not brainrot.PlacedStand then continue end

		local income = BrainrotConfig.GetIncome(brainrot.Id, brainrot.Level, rebirthMult)
		local earned = income * elapsed * OFFLINE_RATE

		-- Add to that stand's accumulation (same key BrMoneyProduction uses)
		local accKey = "AccumulatedMoney_" .. brainrot.PlacedStand
		data[accKey] = (data[accKey] or 0) + earned

		totalOffline += earned
	end

	if totalOffline > 0 then
		print("[OfflineProduction]", player.Name, "accumulated",
			BrainrotConfig.FormatMoney(totalOffline), "offline across stands")
	end
end

------------------------------------------------------------
-- UPDATE LAST ONLINE TIMESTAMP
------------------------------------------------------------
local function stampLastOnline(player: Player)
	local data = PlayerManager.GetData(player)
	if data then
		data.LastOnline = os.time()
	end
end

------------------------------------------------------------
-- INIT
------------------------------------------------------------
function OfflineProductionController.Init()
	-- Stamp on leave
	Players.PlayerRemoving:Connect(stampLastOnline)

	-- Stamp periodically (crash protection)
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				stampLastOnline(player)
			end
		end
	end)
end

return OfflineProductionController