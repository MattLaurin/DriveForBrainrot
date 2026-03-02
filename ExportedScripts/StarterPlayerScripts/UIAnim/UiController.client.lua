--!strict
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local fullGui = playerGui:WaitForChild("FullGameGUI")
local hudFrame = fullGui:WaitForChild("HUDFrame")
local leftHUD = hudFrame:WaitForChild("LeftHUD")
local topHUD = hudFrame:WaitForChild("TopHUD")
local spinButton = hudFrame:WaitForChild("SpinButton")

local SLIDE_DISTANCE = 90
local STAGGER = 0.04

local SLIDE_INFO   = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local HOVER_INFO   = TweenInfo.new(0.16, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)
local PRESS_INFO   = TweenInfo.new(0.09, Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
local RELEASE_INFO = TweenInfo.new(0.14, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)

local DEFAULT_ROT  = 0
local HOVER_ROT    = -8
local PRESS_ROT    = 12
local HOVER_SCALE  = 1.12
local PRESS_SCALE  = 0.92
local NORMAL_SCALE = 1

local function tween(instance: Instance, info: TweenInfo, goals: {[string]: any})
	local t = TweenService:Create(instance, info, goals)
	t:Play()
	return t
end

local function getOrMakeScale(target: GuiObject): UIScale
	local scale = target:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Scale = NORMAL_SCALE
		scale.Parent = target
	end
	return scale
end

local function getIcon(button: GuiObject): GuiObject?
	local byName = button:FindFirstChild("icon67") or button:FindFirstChild("Settings")
	if byName and byName:IsA("GuiObject") then return byName end
	for _, child in ipairs(button:GetChildren()) do
		if child:IsA("ImageLabel") then
			local n = child.Name:lower()
			if not n:match("^bg") and n ~= "background" then
				return child
			end
		end
	end
	return nil
end

local function ensureHitbox(target: GuiObject): TextButton
	local existing = target:FindFirstChild("_UiFxHitbox")
	if existing and existing:IsA("TextButton") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local hitbox = Instance.new("TextButton")
	hitbox.Name = "_UiFxHitbox"
	hitbox.BackgroundTransparency = 1
	hitbox.Text = ""
	hitbox.AutoButtonColor = false
	hitbox.Size = UDim2.fromScale(1, 1)
	hitbox.Position = UDim2.fromScale(0, 0)
	hitbox.ZIndex = target.ZIndex + 10
	hitbox.Parent = target
	return hitbox
end

-- Standard effect: scale + icon tilt
local function setupButton(button: ImageButton)
	if button:GetAttribute("UiFxBound") then return end
	button:SetAttribute("UiFxBound", true)

	local icon = getIcon(button)
	local scale = getOrMakeScale(button)

	local hovering = false
	local pressing = false

	local function applyState()
		if pressing then
			if icon then tween(icon, PRESS_INFO, {Rotation = PRESS_ROT}) end
			tween(scale, PRESS_INFO, {Scale = PRESS_SCALE})
		elseif hovering then
			if icon then tween(icon, HOVER_INFO, {Rotation = HOVER_ROT}) end
			tween(scale, HOVER_INFO, {Scale = HOVER_SCALE})
		else
			if icon then tween(icon, RELEASE_INFO, {Rotation = DEFAULT_ROT}) end
			tween(scale, RELEASE_INFO, {Scale = NORMAL_SCALE})
		end
	end

	button.MouseEnter:Connect(function() hovering = true; applyState() end)
	button.MouseLeave:Connect(function() hovering = false; pressing = false; applyState() end)

	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			pressing = true; applyState()
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			pressing = false; applyState()
		end
	end)

	button.Activated:Connect(function()
		tween(scale, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 0.88})
		task.delay(0.07, applyState)
	end)
end

-- Scale-only effect (no icon): for BaseButton, SellButton, ShopButton
local function setupScaleOnlyButton(button: ImageButton)
	if button:GetAttribute("UiFxBound") then return end
	button:SetAttribute("UiFxBound", true)

	local scale = getOrMakeScale(button)

	local hovering = false
	local pressing = false

	local function applyState()
		if pressing then
			tween(scale, PRESS_INFO, {Scale = PRESS_SCALE})
		elseif hovering then
			tween(scale, HOVER_INFO, {Scale = HOVER_SCALE})
		else
			tween(scale, RELEASE_INFO, {Scale = NORMAL_SCALE})
		end
	end

	button.MouseEnter:Connect(function() hovering = true; applyState() end)
	button.MouseLeave:Connect(function() hovering = false; pressing = false; applyState() end)

	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			pressing = true; applyState()
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			pressing = false; applyState()
		end
	end)

	button.Activated:Connect(function()
		tween(scale, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 0.88})
		task.delay(0.07, applyState)
	end)
end

-- Exit buttons everywhere: works for ImageButton/TextButton/Frame-based buttons
local function setupExitButtonEffect(target: GuiObject)
	if target:GetAttribute("UiFxBound") then return end
	target:SetAttribute("UiFxBound", true)

	local scale = getOrMakeScale(target)
	local buttonLike: GuiButton
	if target:IsA("GuiButton") then
		buttonLike = target
	else
		buttonLike = ensureHitbox(target)
	end

	local hovering = false
	local pressing = false

	local function applyState()
		if pressing then
			tween(scale, PRESS_INFO, {Scale = PRESS_SCALE})
		elseif hovering then
			tween(scale, HOVER_INFO, {Scale = HOVER_SCALE})
		else
			tween(scale, RELEASE_INFO, {Scale = NORMAL_SCALE})
		end
	end

	buttonLike.MouseEnter:Connect(function() hovering = true; applyState() end)
	buttonLike.MouseLeave:Connect(function() hovering = false; pressing = false; applyState() end)

	buttonLike.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			pressing = true; applyState()
		end
	end)
	buttonLike.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			pressing = false; applyState()
		end
	end)

	buttonLike.Activated:Connect(function()
		tween(scale, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 0.88})
		task.delay(0.07, applyState)
	end)
end

-- SpinButton: scale + SpinWheel full spin on hover
local function setupSpinButton(button: ImageButton)
	if button:GetAttribute("UiFxBound") then return end
	button:SetAttribute("UiFxBound", true)

	local wheel = button:FindFirstChild("SpinWheel") :: ImageLabel
	local scale = getOrMakeScale(button)

	local spinning = false
	local hovering = false
	local pressing = false

	local function spinWheel()
		if spinning or not wheel then return end
		spinning = true
		wheel.Rotation = 0
		tween(wheel, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = 360})
		task.delay(0.45, function()
			wheel.Rotation = 0
			spinning = false
		end)
	end

	local function applyState()
		if pressing then
			tween(scale, PRESS_INFO, {Scale = PRESS_SCALE})
		elseif hovering then
			tween(scale, HOVER_INFO, {Scale = HOVER_SCALE})
		else
			tween(scale, RELEASE_INFO, {Scale = NORMAL_SCALE})
		end
	end

	button.MouseEnter:Connect(function()
		hovering = true
		applyState()
		spinWheel()
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		pressing = false
		applyState()
	end)

	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			pressing = true; applyState()
			spinWheel()
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			pressing = false; applyState()
		end
	end)

	button.Activated:Connect(function()
		tween(scale, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 0.88})
		task.delay(0.07, applyState)
		spinWheel()
	end)
end

-- Slide-in entrance animation
local function slideIn(gui: GuiObject, index: number)
	local original = gui.Position
	gui.Position = UDim2.new(original.X.Scale, original.X.Offset - SLIDE_DISTANCE, original.Y.Scale, original.Y.Offset)
	task.delay((index - 1) * STAGGER, function()
		if gui.Parent then tween(gui, SLIDE_INFO, {Position = original}) end
	end)
end

local targets = {}
for _, child in ipairs(leftHUD:GetChildren()) do
	if child:IsA("GuiObject") then table.insert(targets, child) end
end
table.sort(targets, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
for i, gui in ipairs(targets) do slideIn(gui, i) end

-- Hook up LeftHUD buttons (icon + scale)
for _, desc in ipairs(leftHUD:GetDescendants()) do
	if desc:IsA("ImageButton") then setupButton(desc) end
end

-- Hook up TopHUD buttons (scale only)
local scaleOnlyNames = {"BaseButton", "SellButton", "ShopButton"}
for _, name in ipairs(scaleOnlyNames) do
	local btn = topHUD:FindFirstChild(name) :: ImageButton
	if btn then setupScaleOnlyButton(btn) end
end

-- Hook up SpinButton
setupSpinButton(spinButton)

-- Hook up ALL ExitButton/Exitbutton controls in FullGameGUI
for _, desc in ipairs(fullGui:GetDescendants()) do
	if desc:IsA("GuiObject") then
		local n = desc.Name:lower()
		if n == "exitbutton" then
			setupExitButtonEffect(desc)
		end
	end
end
