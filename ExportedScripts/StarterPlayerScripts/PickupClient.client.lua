--[[
	StarterPlayer/StarterPlayerScripts/PickupClient.lua (LocalScript)
	
	SOLE RESPONSIBILITY: Listen for ProximityPrompt "PickupPrompt" triggers
	on world brainrots, fire PickupBrainrot remote.
	
	Each world brainrot model needs:
	- Attribute "BrainrotId" (string) e.g. "67"
	- Attribute "Rarity" (string) e.g. "Common"
	- A ProximityPrompt named "PickupPrompt" inside any child part
--]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PickupRemote = Remotes:WaitForChild("PickupBrainrot")

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------
local function findBrainrotAncestor(inst: Instance): Model?
	local current = inst
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("BrainrotId") then
			return current :: Model
		end
		current = current.Parent
	end
	return nil
end

------------------------------------------------------------
-- WIRE PROXIMITY PROMPTS
------------------------------------------------------------
local wiredPrompts = {}

local function wirePrompt(prompt: ProximityPrompt)
	if wiredPrompts[prompt] then return end
	wiredPrompts[prompt] = true

	prompt.Triggered:Connect(function(triggeringPlayer: Player)
		if triggeringPlayer ~= player then return end

		local brainrotModel = findBrainrotAncestor(prompt)
		if not brainrotModel then return end

		PickupRemote:FireServer(brainrotModel)
	end)
end

local function isPickupPrompt(inst: Instance): boolean
	return inst:IsA("ProximityPrompt") and inst.Name == "PickupPrompt"
end

-- Wire existing
for _, desc in workspace:GetDescendants() do
	if isPickupPrompt(desc) then
		wirePrompt(desc :: ProximityPrompt)
	end
end

-- Wire future (spawned brainrots, streaming)
workspace.DescendantAdded:Connect(function(desc)
	if isPickupPrompt(desc) then
		wirePrompt(desc :: ProximityPrompt)
	end
end)

-- Cleanup
workspace.DescendantRemoving:Connect(function(desc)
	if wiredPrompts[desc] then
		wiredPrompts[desc] = nil
	end
end)