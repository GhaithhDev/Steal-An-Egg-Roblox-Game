--//Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

--//Configs
local DangerCornersConfig = require(ReplicatedStorage.Shared.Configs.UIEffects.DangerCorners)

local localPlayer = Players.LocalPlayer

local DangerCornersController = {}

local cornersFolder: Instance
local isDanger = false
local activeTweens: { Tween } = {}

local PULSE_TWEEN_INFO = TweenInfo.new(
	DangerCornersConfig.PulseTime,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.InOut,
	-1, -- loop forever
	true -- reverse, so .5 -> .9 -> .5 repeats like a heartbeat
)

local function StopPulse()
	for _, tween in activeTweens do
		tween:Cancel()
	end
	table.clear(activeTweens)
end

local function StartPulse()
	StopPulse()

	for _, corner in cornersFolder:GetChildren() do
		if not corner:IsA("GuiObject") then
			continue
		end
		corner.Visible = true

		if corner:IsA("ImageLabel") or corner:IsA("ImageButton") then
			local image = corner :: ImageLabel | ImageButton
			image.ImageTransparency = DangerCornersConfig.MinTransparency

			local tween = TweenService:Create(image, PULSE_TWEEN_INFO, { ImageTransparency = DangerCornersConfig.MaxTransparency })
			tween:Play()
			table.insert(activeTweens, tween)
		end
	end
end

local function HideCorners()
	StopPulse()

	for _, corner in cornersFolder:GetChildren() do
		if corner:IsA("GuiObject") then
			corner.Visible = false
		end
	end
end

-- exposed so other controllers (e.g. CarryEggsController) can drive the danger state
function DangerCornersController.ToggleDangerCorners(isInDanger: boolean)
	if isInDanger == isDanger then
		return
	end
	isDanger = isInDanger

	if isDanger then
		StartPulse()
	else
		HideCorners()
	end
end

-- runs during the synchronous Init phase (not Start) so cornersFolder is
-- guaranteed to be set before any other controller's Start can call
-- ToggleDangerCorners
function DangerCornersController.Init()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("Main")
	cornersFolder = mainGui:WaitForChild("DangerCorners")

	HideCorners()
end

return DangerCornersController
