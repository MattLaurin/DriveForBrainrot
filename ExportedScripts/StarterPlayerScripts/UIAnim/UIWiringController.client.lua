local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SocialService = game:GetService("SocialService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("FullGameGUI")
local hudFrame = gui:WaitForChild("HUDFrame")
local leftHUD = hudFrame:WaitForChild("LeftHUD")
local topHUD = hudFrame:WaitForChild("TopHUD")

local OPEN_INFO  = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local CLOSE_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)

local openFrame: Frame? = nil

local function closeFrame(frame: Frame)
	local t = TweenService:Create(frame, CLOSE_INFO, {Size = UDim2.fromScale(0, 0)})
	local originalSize = frame.Size
	t:Play()
	t.Completed:Connect(function()
		frame.Visible = false
		frame.Size = originalSize
	end)
end

local function openFrameAnim(frame: Frame)
	local targetSize = frame.Size
	frame.Size = UDim2.fromScale(0, 0)
	frame.Visible = true
	TweenService:Create(frame, OPEN_INFO, {Size = targetSize}):Play()
end

local function toggleFrame(frame: Frame)
	if openFrame == frame then
		closeFrame(frame)
		openFrame = nil
	else
		if openFrame then closeFrame(openFrame) end
		openFrame = frame
		openFrameAnim(frame)
	end
end

local function teleportTo(position: Vector3)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = CFrame.new(position + Vector3.new(0, 5, 0))
	end
end

local function wireExitButton(frame: Frame, path: string)
	local cur: Instance = frame
	for _, part in ipairs(string.split(path, ".")) do
		cur = cur:FindFirstChild(part)
		if not cur then return end
	end
	local clickable = cur
	if not (clickable:IsA("ImageButton") or clickable:IsA("TextButton")) then
		clickable = cur:FindFirstChildOfClass("ImageButton") 
			or cur:FindFirstChildOfClass("TextButton")
			or cur
	end
	if clickable then
		if clickable:IsA("ImageButton") or clickable:IsA("TextButton") then
			clickable.Activated:Connect(function()
				closeFrame(frame)
				if openFrame == frame then openFrame = nil end
			end)
		else
			clickable.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch then
					closeFrame(frame)
					if openFrame == frame then openFrame = nil end
				end
			end)
		end
	end
end

local frameWires = {
	{ button = leftHUD:WaitForChild("ConfigButton"),  frame = gui:WaitForChild("SettingsFrame"), exit = "Header.ExitButton" },
	{ button = leftHUD:WaitForChild("GiftsButton"),   frame = gui:WaitForChild("Dailrewards"),   exit = "Header.ExitButton" },
	{ button = leftHUD:WaitForChild("IndexButton"),   frame = gui:WaitForChild("IndexFrame"),    exit = "Header.ExitButton" },
	{ button = leftHUD:WaitForChild("RebirthButton"), frame = gui:WaitForChild("Rebirth"),       exit = "Header.ExitButton" },
	{ button = leftHUD:WaitForChild("StoreButton"),   frame = gui:WaitForChild("ShopFrame"),     exit = "Header.ExitButton" },
	{ button = hudFrame:WaitForChild("SpinButton"),   frame = gui:WaitForChild("SpinFrame"),     exit = "Exitbutton" },
}

for _, wire in ipairs(frameWires) do
	wire.frame.Visible = false
end

for _, wire in ipairs(frameWires) do
	wire.button.Activated:Connect(function()
		toggleFrame(wire.frame)
	end)
	wireExitButton(wire.frame, wire.exit)
end

-- InviteButton: Roblox invite prompt
leftHUD:WaitForChild("InviteButton").Activated:Connect(function()
	local success, err = pcall(function()
		SocialService:PromptGameInvite(player)
	end)
	if not success then
		warn("InvitePrompt failed: " .. tostring(err))
	end
end)

-- SellButton: teleport to SellShop
topHUD:WaitForChild("SellButton").Activated:Connect(function()
	teleportTo(Vector3.new(293.5, 8.75, -11.45))
end)

-- ShopButton: teleport to CarShop
topHUD:WaitForChild("ShopButton").Activated:Connect(function()
	teleportTo(Vector3.new(293.5, 8.75, -127.45))
end)
