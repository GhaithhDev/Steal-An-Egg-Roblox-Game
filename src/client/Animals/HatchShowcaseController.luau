--[[
	HatchShowcaseController

	Renders the hatch showcase's one-shot flight (see AnimalsService.luau's
	StartShowcaseFlight) as a real quadratic bezier curve, evaluated locally
	every frame via RunService - same technique as HatchExplosionController,
	just for one whole animal rig flying once (root only) instead of many
	scattering parts. The server only decides and replicates three CFrame
	attributes (ShowcaseStart/ShowcasePeak/ShowcaseTarget) plus a shared
	ShowcaseStartTime - this controller reacts to those appearing and drives
	the root part's CFrame purely as a client-side visual for the flight's
	duration (AnimalsConfig.SHOWCASE_FLIGHT_TIME); the rest of the rig
	follows automatically via its own Motor6D joint hierarchy.
]]

--//Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--//Configs
local AnimalsConfig = require(ReplicatedStorage.Shared.Configs.AnimalsConfig)

local HatchShowcaseController = {}

type Flight = {
	startCFrame: CFrame,
	peakCFrame: CFrame,
	targetCFrame: CFrame,
	startTime: number,
}

local activeFlights: { [BasePart]: Flight } = {}

local function StartFlight(part: BasePart)
	local startCFrame = part:GetAttribute("ShowcaseStart")
	local peakCFrame = part:GetAttribute("ShowcasePeak")
	local targetCFrame = part:GetAttribute("ShowcaseTarget")
	local startTime = part:GetAttribute("ShowcaseStartTime")
	if not (startCFrame and peakCFrame and targetCFrame and startTime) then
		return
	end

	activeFlights[part] = {
		startCFrame = startCFrame,
		peakCFrame = peakCFrame,
		targetCFrame = targetCFrame,
		startTime = startTime,
	}
end

-- ShowcaseStartTime is the last of the four attributes StartShowcaseFlight
-- sets, so waiting on its changed signal (rather than the first-seen one)
-- guarantees the other three are already there once this fires.
local function OnDescendantAdded(descendant: Instance)
	if not descendant:IsA("BasePart") then
		return
	end

	if descendant:GetAttribute("ShowcaseStartTime") then
		StartFlight(descendant)
	end

	descendant:GetAttributeChangedSignal("ShowcaseStartTime"):Connect(function()
		StartFlight(descendant)
	end)
end

function HatchShowcaseController.Start()
	local plotsFolder = Workspace:WaitForChild("Functional"):WaitForChild("Spawns"):WaitForChild("Plots")

	for _, descendant in plotsFolder:GetDescendants() do
		OnDescendantAdded(descendant)
	end
	plotsFolder.DescendantAdded:Connect(OnDescendantAdded)

	RunService.Heartbeat:Connect(function()
		local now = Workspace:GetServerTimeNow()

		for part, flight in activeFlights do
			if not part.Parent then
				activeFlights[part] = nil
				continue
			end

			local t = math.clamp((now - flight.startTime) / AnimalsConfig.SHOWCASE_FLIGHT_TIME, 0, 1)
			local oneMinusT = 1 - t

			-- Real quadratic bezier: B(t) = (1-t)^2 P0 + 2(1-t)t P1 + t^2 P2.
			local position = flight.startCFrame.Position * (oneMinusT * oneMinusT)
				+ flight.peakCFrame.Position * (2 * oneMinusT * t)
				+ flight.targetCFrame.Position * (t * t)

			part.CFrame = CFrame.new(position) * (flight.startCFrame - flight.startCFrame.Position)

			if t >= 1 then
				activeFlights[part] = nil
			end
		end
	end)
end

return HatchShowcaseController
