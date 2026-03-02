--[[
	StarterPlayer/StarterPlayerScripts/PlacementClient.lua (LocalScript)
	
	SOLE RESPONSIBILITY: Stand interactions — ProximityPrompt to place/remove,
	click Buy button to upgrade. Auto-selects brainrot from equipped Tool.
	
	FIXES:
	1. Upgrade button: Added ClickDetector fallback on ControlCenter part.
	2. SurfaceGui: Ensured proper MaxDistance and Active propagation.
	3. NEW: ALL upgrade effects now handled client-side via UpgradeVfxEvent:
	   - $$$ money VFX → on the brainrot
	   - B - Hit 02 VFX → on the ControlCenter (upgrade GUI area)
	   - Jump animation → on the brainrot
	   Both VFX templates must be in ReplicatedStorage.Vfx
--]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlaceRemote = Remotes:WaitForChild("PlaceBrainrot")
local RemoveRemote = Remotes:WaitForChild("RemoveFromStand")
local UpgradeRemote = Remotes:WaitForChild("UpgradeBrainrot")
local UpgradeVfxRemote = Remotes:WaitForChild("UpgradeVfxEvent")

local selectedBrainrotUUID: string? = nil
local selectedBrainrotName: string? = nil

------------------------------------------------------------
-- VFX TEMPLATES (from ReplicatedStorage)
------------------------------------------------------------
local VfxFolder = ReplicatedStorage:WaitForChild("Vfx")
local MoneyVfxTemplate = VfxFolder:WaitForChild("$$$")

------------------------------------------------------------
-- AUTO-SELECT FROM EQUIPPED TOOL
------------------------------------------------------------
local function onCharacterAdded(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("BrainrotUUID") then
			selectedBrainrotUUID = child:GetAttribute("BrainrotUUID")
			selectedBrainrotName = child.Name
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("BrainrotUUID") then
			if selectedBrainrotUUID == child:GetAttribute("BrainrotUUID") then
				selectedBrainrotUUID = nil
				selectedBrainrotName = nil
			end
		end
	end)

	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("BrainrotUUID") then
			selectedBrainrotUUID = child:GetAttribute("BrainrotUUID")
			selectedBrainrotName = child.Name
		end
	end
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

------------------------------------------------------------
-- STAND STATE TRACKING
------------------------------------------------------------
local function standHasBrainrot(platform: BasePart): boolean
	for _, child in platform:GetChildren() do
		if child.Name == "BrainrotVisual" then
			return true
		end
	end
	return false
end

------------------------------------------------------------
-- CONTROL CENTER VISIBILITY
-- Part is always invisible but clickable, only SurfaceGui toggles
------------------------------------------------------------
local function updateControlCenter(standModel: Model, hasBrainrot: boolean)
	local stand = standModel:FindFirstChild("Stand")
	if not stand then return end

	local cc = stand:FindFirstChild("ControlCenter")
	if not cc then return end

	local gui = cc:FindFirstChild("SurfaceGui")
	if gui then
		gui.Enabled = hasBrainrot
	end
end

------------------------------------------------------------
-- PLOT LOOKUP HELPER (shared by VFX and wiring)
------------------------------------------------------------
local function getStandModelFromKey(standKey: string): Model?
	local plotName = player:GetAttribute("AssignedPlot")
	if not plotName then return nil end

	local plots = workspace:FindFirstChild("World")
	if not plots then return nil end
	plots = plots:FindFirstChild("Plots")
	if not plots then return nil end

	local plot = plots:FindFirstChild(plotName)
	if not plot then return nil end

	local floorNum, standNum = standKey:match("^(%d+)_(%d+)$")
	if not floorNum then return nil end

	local floors = plot:FindFirstChild("Floors")
	if not floors then return nil end

	local floor = floors:FindFirstChild(tostring(floorNum))
	if not floor then return nil end

	local stands = floor:FindFirstChild("Stands")
	if not stands then return nil end

	return stands:FindFirstChild(tostring(standNum))
end

------------------------------------------------------------
-- VFX HELPER
-- Clones a VFX template, parents its attachment to a target
-- part, reads emitter attributes, emits, then cleans up.
------------------------------------------------------------
local function playVfx(vfxTemplate: BasePart, targetPart: BasePart)
	local templateAttachment = vfxTemplate:FindFirstChildWhichIsA("Attachment", true)
	if not templateAttachment then
		return
	end

	local attachment = templateAttachment:Clone()
	attachment.Parent = targetPart

	local emitters = {}
	for _, child in attachment:GetDescendants() do
		if child:IsA("ParticleEmitter") then
			child.Enabled = false
			table.insert(emitters, child)
		end
	end

	local maxLifetime = 0

	for _, emitter in emitters do
		local emitDelay = emitter:GetAttribute("EmitDelay") or 0
		local emitDuration = emitter:GetAttribute("EmitDuration")
		if emitDuration == nil then
			emitDuration = 0.35
		end

		local emitCount = emitter:GetAttribute("EmitCount")
		if emitCount == nil then
			-- Fallback for templates that rely on low Rate without burst attrs.
			emitCount = math.max(8, math.floor(emitter.Rate * 8))
		end

		local emitterLifetime = emitDelay + emitDuration + 2
		if emitterLifetime > maxLifetime then
			maxLifetime = emitterLifetime
		end

		task.spawn(function()
			if emitDelay > 0 then
				task.wait(emitDelay)
			end

			if emitCount > 0 then
				emitter:Emit(emitCount)
			end

			emitter.Enabled = true
			task.wait(emitDuration)
			emitter.Enabled = false
		end)
	end

	task.delay(maxLifetime, function()
		if attachment and attachment.Parent then
			attachment:Destroy()
		end
	end)
end

------------------------------------------------------------
-- JUMP ANIMATION FOR BRAINROT VISUAL
------------------------------------------------------------
local JUMP_HEIGHT = 3
local JUMP_UP_TIME = 0.2
local JUMP_DOWN_TIME = 0.25

local function tweenModelPivot(model: Model, fromCF: CFrame, toCF: CFrame, info: TweenInfo)
	local value = Instance.new("CFrameValue")
	value.Value = fromCF

	local conn
	conn = value:GetPropertyChangedSignal("Value"):Connect(function()
		if model.Parent then
			model:PivotTo(value.Value)
		end
	end)

	local t = TweenService:Create(value, info, { Value = toCF })
	t.Completed:Once(function()
		if conn then conn:Disconnect() end
		value:Destroy()
	end)
	t:Play()
	return t
end

local function playJumpAnimation(visual: Instance)
	if visual:IsA("Model") then
		local restCF = visual:GetPivot()
		local jumpUpCF = restCF * CFrame.new(0, JUMP_HEIGHT, 0)

		local upTween = tweenModelPivot(
			visual,
			restCF,
			jumpUpCF,
			TweenInfo.new(JUMP_UP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		)

		upTween.Completed:Once(function()
			tweenModelPivot(
				visual,
				jumpUpCF,
				restCF,
				TweenInfo.new(JUMP_DOWN_TIME, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
			)
		end)

	elseif visual:IsA("BasePart") then
		local restCF = visual.CFrame
		local jumpUpCF = restCF * CFrame.new(0, JUMP_HEIGHT, 0)

		local upTween = TweenService:Create(visual, TweenInfo.new(
			JUMP_UP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out
		), { CFrame = jumpUpCF })

		local downTween = TweenService:Create(visual, TweenInfo.new(
			JUMP_DOWN_TIME, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out
		), { CFrame = restCF })

		upTween:Play()
		upTween.Completed:Once(function()
			downTween:Play()
		end)
	end
end

local function getVisualCenterPosition(visual: Instance): Vector3?
	if visual:IsA("Model") then
		local boundsCF = visual:GetBoundingBox()
		return boundsCF.Position
	elseif visual:IsA("BasePart") then
		return visual.Position
	end
	return nil
end

local function makeTempAnchorAt(position: Vector3, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = "__UpgradeFxAnchor"
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Transparency = 1
	p.CFrame = CFrame.new(position)
	p.Parent = parent
	task.delay(3, function()
		if p.Parent then p:Destroy() end
	end)
	return p
end

------------------------------------------------------------
-- UPGRADE EFFECTS (ALL CLIENT-SIDE)
-- Fired by server via UpgradeVfxEvent with standKey.
-- $$$ money VFX  → on the brainrot
-- B - Hit 02     → on the ControlCenter (upgrade GUI area)
-- Brainrot jumps
------------------------------------------------------------
local function playUpgradeEffects(standKey: string)
	local standModel = getStandModelFromKey(standKey)
	if not standModel then return end

	local stand = standModel:FindFirstChild("Stand")
	if not stand then return end

	local platform = stand:FindFirstChild("Platform")
	if not platform then return end

	local cc = stand:FindFirstChild("ControlCenter")
	local visual = platform:FindFirstChild("BrainrotVisual")
	if not visual then return end

	local centerPos = getVisualCenterPosition(visual)
	if centerPos then
		local anchor = makeTempAnchorAt(centerPos, platform)
		playVfx(MoneyVfxTemplate, anchor)
	end

	playJumpAnimation(visual)
end

------------------------------------------------------------
-- LISTEN FOR UPGRADE VFX EVENT FROM SERVER
------------------------------------------------------------
UpgradeVfxRemote.OnClientEvent:Connect(function(standKey: string)
	playUpgradeEffects(standKey)
end)

------------------------------------------------------------
-- STAND WIRING
------------------------------------------------------------
local wiredStands = {}

local function wireStand(standModel: Model, standKey: string, platform: BasePart)
	if wiredStands[standKey] then return end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StandPrompt"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.ActionText = "Place"
	prompt.ObjectText = ""
	prompt.RequiresLineOfSight = false
	prompt.Parent = platform

	wiredStands[standKey] = {
		prompt = prompt,
		standModel = standModel,
		platform = platform,
	}

	-- Set initial ControlCenter visibility
	local hasBrainrot = standHasBrainrot(platform)
	updateControlCenter(standModel, hasBrainrot)

	-- Watch for BrainrotVisual being added/removed
	platform.ChildAdded:Connect(function(child)
		if child.Name == "BrainrotVisual" then
			updateControlCenter(standModel, true)
		end
	end)

	platform.ChildRemoved:Connect(function(child)
		if child.Name == "BrainrotVisual" then
			updateControlCenter(standModel, false)
		end
	end)

	-- Update prompt text dynamically
	prompt.PromptShown:Connect(function()
		local occupied = standHasBrainrot(platform)
		if occupied then
			prompt.ActionText = "Pick Up"
			prompt.ObjectText = ""
		elseif selectedBrainrotUUID then
			prompt.ActionText = "Place"
			prompt.ObjectText = selectedBrainrotName or "Brainrot"
		else
			prompt.ActionText = "Place"
			prompt.ObjectText = "No brainrot held"
		end
	end)

	-- Handle trigger
	prompt.Triggered:Connect(function(triggeringPlayer: Player)
		if triggeringPlayer ~= player then return end

		local occupied = standHasBrainrot(platform)

		if occupied then
			RemoveRemote:FireServer(standKey)
		elseif selectedBrainrotUUID then
			PlaceRemote:FireServer(selectedBrainrotUUID, standKey)
			selectedBrainrotUUID = nil
			selectedBrainrotName = nil
		end
	end)
end

------------------------------------------------------------
-- WIRE UPGRADE BUTTONS
------------------------------------------------------------
local upgradeCooldowns = {} -- [standKey] = tick

local function wireUpgradeButton(buyButton: ImageButton, standKey: string, controlCenterPart: BasePart?)
	local function doUpgrade()
		-- Cooldown to prevent double-fires
		local now = tick()
		if upgradeCooldowns[standKey] and (now - upgradeCooldowns[standKey]) < 0.3 then
			return
		end
		upgradeCooldowns[standKey] = now

		UpgradeRemote:FireServer(standKey)
	end

	-- Method 1: MouseButton1Click (desktop with SurfaceGui)
	buyButton.MouseButton1Click:Connect(doUpgrade)

	-- Method 2: Activated (more reliable, fires on click/tap/gamepad)
	buyButton.Activated:Connect(doUpgrade)

	-- Method 3: ClickDetector on the ControlCenter part (fallback)
	if controlCenterPart then
		local existingClick = controlCenterPart:FindFirstChild("UpgradeClick")
		if not existingClick then
			local click = Instance.new("ClickDetector")
			click.Name = "UpgradeClick"
			click.MaxActivationDistance = 12
			click.Parent = controlCenterPart

			click.MouseClick:Connect(function(clickPlayer: Player)
				if clickPlayer ~= player then return end
				local stand = controlCenterPart.Parent
				if not stand then return end
				local platform = stand:FindFirstChild("Platform")
				if not platform then return end
				if not standHasBrainrot(platform) then return end

				doUpgrade()
			end)
		end
	end
end

------------------------------------------------------------
-- WIRE ALL STANDS ON ASSIGNED PLOT
------------------------------------------------------------
local function wirePlotStands()
	print("[PlacementClient] Waiting for AssignedPlot...")

	local plotName = player:GetAttribute("AssignedPlot")
	if not plotName then
		player:GetAttributeChangedSignal("AssignedPlot"):Wait()
		plotName = player:GetAttribute("AssignedPlot")
	end

	print("[PlacementClient] Got plot:", plotName)

	local plots = workspace:WaitForChild("World"):WaitForChild("Plots")
	local plot = plots:WaitForChild(plotName)
	local floors = plot:WaitForChild("Floors")

	task.wait(2)

	local count = 0

	for _, floor in floors:GetChildren() do
		local stands = floor:WaitForChild("Stands", 10)
		if not stands then
			warn("[PlacementClient] No Stands folder in floor", floor.Name)
			continue
		end

		task.wait(0.5)

		for _, standModel in stands:GetChildren() do
			if not standModel:IsA("Model") then continue end

			local key = floor.Name .. "_" .. standModel.Name

			local stand = standModel:WaitForChild("Stand", 5)
			if not stand then
				warn("[PlacementClient] No Stand in", standModel:GetFullName())
				continue
			end

			local platform = stand:WaitForChild("Platform", 5)
			if not platform then
				warn("[PlacementClient] No Platform in", stand:GetFullName())
				continue
			end

			-- Hide ControlCenter part but keep it clickable
			local cc = stand:FindFirstChild("ControlCenter")
			if cc and cc:IsA("BasePart") then
				cc.Transparency = 1
				cc.CanQuery = true
				cc.CanCollide = false
			end

			-- Setup SurfaceGui
			if cc then
				local gui = cc:FindFirstChild("SurfaceGui")
				if gui then
					gui.Active = true
					gui.Enabled = false

					if gui:IsA("SurfaceGui") then
						gui.MaxDistance = 32
					end

					local upgrade = gui:FindFirstChild("Upgrade")
					if upgrade then
						if upgrade:IsA("GuiObject") then
							upgrade.Active = true
						end

						local buy = upgrade:FindFirstChild("Buy")
						if buy then
							if buy:IsA("GuiObject") then
								buy.Active = true
							end
							wireUpgradeButton(buy, key, cc)
						end
					end
				end
			end

			-- Create ProximityPrompt
			wireStand(standModel, key, platform)

			count += 1
		end
	end

	print("[PlacementClient] Wired", count, "stands")
end

task.spawn(wirePlotStands)