--[[
	HatchExplosionController

	Renders the hatch explosion's per-part flight (see GrowingEggsService.luau's
	ExplodeEgg) as a real quadratic bezier curve, evaluated locally every frame
	via RunService instead of ReplicatedTween. The server only decides and
	replicates three CFrame attributes per part (ExplodeStart/ExplodePeak/
	ExplodeGround) plus a shared ExplodeStartTime - this controller reacts to
	those appearing and drives part.CFrame purely as a client-side visual for
	the flight's duration (GrowingEggsConfig.HATCH_EXPLODE_ARC_TIME).
]]

--//Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--//Configs
local GrowingEggsConfig = require(ReplicatedStorage.Shared.Configs.GrowingEggsConfig)

local HatchExplosionController = {}

type Flight = {
	startCFrame: CFrame,
	peakCFrame: CFrame,
	groundCFrame: CFrame,
	startTime: number,
}

local activeFlights: { [BasePart]: Flight } = {}

local function StartFlight(part: BasePart)
	local startCFrame = part:GetAttribute("ExplodeStart")
	local peakCFrame = part:GetAttribute("ExplodePeak")
	local groundCFrame = part:GetAttribute("ExplodeGround")
	local startTime = part:GetAttribute("ExplodeStartTime")
	if not (startCFrame and peakCFrame and groundCFrame and startTime) then
		return
	end

	activeFlights[part] = {
		startCFrame = startCFrame,
		peakCFrame = peakCFrame,
		groundCFrame = groundCFrame,
		startTime = startTime,
	}
end

-- ExplodeStartTime is the last of the four attributes ExplodeEgg sets on a
-- part, so waiting on its changed signal (rather than the first-seen one)
-- guarantees the other three are already there once this fires.
local function OnDescendantAdded(descendant: Instance)
	if not descendant:IsA("BasePart") then
		return
	end

	if descendant:GetAttribute("ExplodeStartTime") then
		StartFlight(descendant)
	end

	descendant:GetAttributeChangedSignal("ExplodeStartTime"):Connect(function()
		StartFlight(descendant)
	end)
end

function HatchExplosionController.Start()
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

			local t = math.clamp((now - flight.startTime) / GrowingEggsConfig.HATCH_EXPLODE_ARC_TIME, 0, 1)
			local oneMinusT = 1 - t

			-- Real quadratic bezier: B(t) = (1-t)^2 P0 + 2(1-t)t P1 + t^2 P2.
			local position = flight.startCFrame.Position * (oneMinusT * oneMinusT)
				+ flight.peakCFrame.Position * (2 * oneMinusT * t)
				+ flight.groundCFrame.Position * (t * t)

			part.CFrame = CFrame.new(position) * (flight.startCFrame - flight.startCFrame.Position)

			if t >= 1 then
				activeFlights[part] = nil
			end
		end
	end)
end

return HatchExplosionController
