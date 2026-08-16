local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Net = require(ReplicatedStorage.Shared.Packages.Net)
local SoundUtils = require(ReplicatedStorage.Shared.Packages.SoundUtils)
local MonetizationUtils = require(ReplicatedStorage.Shared.Utils.MonetizationUtils)
local ConfettiController = require(script.Parent.Parent.Confetti.ConfettiController)

local LocalPlayer = Players.LocalPlayer

local PurchaseLoadingController = {}

local BASE_DIM_TRANSPARENCY = 0.5
local PULSE_DIM_TRANSPARENCY = 0.6
local PULSE_PERIOD = 1 -- seconds per half-cycle; matches the spinner's rotation period

local ORBIT_PERIOD = 4 -- seconds per full revolution
local HUE_CYCLES_PER_SECOND = 0.15 -- speed of the RGB wave sweeping around the ring

local TRAIL_INTERVAL = 0.05 -- seconds between comet-trail ghost spawns
local TRAIL_FADE_TIME = 0.4

local overlay, spinner, orbitContainer, edgeGlow
local orbitParticles: { Frame } = {}
local edgeBars: { Frame } = {}
local spinTween: Tween?
local dimPulseTween: Tween?
local orbitTween: Tween?
local hueConnection: RBXScriptConnection?
local currentProductId: number?

local function ensureLoaded()
	if overlay then return end
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("Main")
	overlay = mainGui:WaitForChild("PurchaseLoadingOverlay")
	spinner = overlay:WaitForChild("Spinner")
	orbitContainer = overlay:WaitForChild("OrbitContainer")
	edgeGlow = overlay:WaitForChild("EdgeGlow")

	for _, child in orbitContainer:GetChildren() do
		if child:IsA("Frame") then
			table.insert(orbitParticles, child)
		end
	end

	for _, child in edgeGlow:GetChildren() do
		if child:IsA("Frame") then
			table.insert(edgeBars, child)
		end
	end
end

function PurchaseLoadingController.Show(productId: number)
	ensureLoaded()
	currentProductId = productId
	overlay.Visible = true
	overlay.BackgroundTransparency = BASE_DIM_TRANSPARENCY
	SoundUtils.PlayLocalSound(SoundService.SFX.Bell)

	spinner.Rotation = 0
	if spinTween then spinTween:Cancel() end
	spinTween = TweenService:Create(
		spinner,
		TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1, false),
		{ Rotation = 360 }
	)
	spinTween:Play()

	if dimPulseTween then dimPulseTween:Cancel() end
	local newDimPulseTween = TweenService:Create(
		overlay,
		TweenInfo.new(PULSE_PERIOD, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ BackgroundTransparency = PULSE_DIM_TRANSPARENCY }
	)
	newDimPulseTween:Play()
	dimPulseTween = newDimPulseTween

	orbitContainer.Rotation = 0
	if orbitTween then orbitTween:Cancel() end
	local newOrbitTween = TweenService:Create(
		orbitContainer,
		TweenInfo.new(ORBIT_PERIOD, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1, false),
		{ Rotation = 360 }
	)
	newOrbitTween:Play()
	orbitTween = newOrbitTween

	if hueConnection then hueConnection:Disconnect() end
	local hueTime = 0
	local trailAccumulator = 0
	hueConnection = RunService.Heartbeat:Connect(function(deltaTime)
		hueTime += deltaTime * HUE_CYCLES_PER_SECOND

		for i, particle in orbitParticles do
			local hue = (hueTime + (i - 1) / #orbitParticles) % 1
			particle.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
		end

		local edgeColor = Color3.fromHSV(hueTime % 1, 1, 1)
		for _, bar in edgeBars do
			bar.BackgroundColor3 = edgeColor
		end

		trailAccumulator += deltaTime
		if trailAccumulator >= TRAIL_INTERVAL then
			trailAccumulator -= TRAIL_INTERVAL
			for _, particle in orbitParticles do
				local trail = particle:Clone()
				trail.Name = "Trail"
				local relativePosition = particle.AbsolutePosition - overlay.AbsolutePosition + particle.AbsoluteSize / 2
				trail.Position = UDim2.fromOffset(relativePosition.X, relativePosition.Y)
				trail.Parent = overlay

				TweenService:Create(trail, TweenInfo.new(TRAIL_FADE_TIME, Enum.EasingStyle.Linear), {
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(particle.AbsoluteSize.X * 0.5, particle.AbsoluteSize.Y * 0.5),
				}):Play()
				Debris:AddItem(trail, TRAIL_FADE_TIME)
			end
		end
	end)
end

function PurchaseLoadingController.Hide()
	if not overlay then return end
	overlay.Visible = false
	overlay.BackgroundTransparency = BASE_DIM_TRANSPARENCY
	currentProductId = nil
	if spinTween then
		spinTween:Cancel()
		spinTween = nil
	end
	if dimPulseTween then
		dimPulseTween:Cancel()
		dimPulseTween = nil
	end
	if orbitTween then
		orbitTween:Cancel()
		orbitTween = nil
	end
	if hueConnection then
		hueConnection:Disconnect()
		hueConnection = nil
	end
end

function PurchaseLoadingController.Start()
	ensureLoaded()

	Net:Connect("ShowPurchaseLoading", function(productId)
		PurchaseLoadingController.Show(productId)
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
		if userId ~= LocalPlayer.UserId then return end
		if currentProductId ~= nil and productId ~= currentProductId then return end
		PurchaseLoadingController.Hide()

		if isPurchased then
			local displayName = MonetizationUtils.GetNameFromId(productId) or "item"
			ConfettiController.Play()
		end
	end)
end

return PurchaseLoadingController
