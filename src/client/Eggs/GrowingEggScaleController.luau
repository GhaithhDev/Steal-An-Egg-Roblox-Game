--//Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

--//Modules
local GrowingEggScale = require(ReplicatedStorage.Shared.Modules.GrowingEggScale)

local GrowingEggScaleController = {}

local trackedEggs: { [Model]: NumberValue } = {}

local function TrackEgg(eggModel: Model, scaleFractionValue: NumberValue)
	if trackedEggs[eggModel] then
		return
	end
	trackedEggs[eggModel] = scaleFractionValue

	-- Apply immediately: covers late joiners and eggs mid-tween on connect,
	-- since the server may have already advanced ScaleFraction.Value before
	-- this client ever saw the model.
	GrowingEggScale.Apply(eggModel, scaleFractionValue)

	scaleFractionValue:GetPropertyChangedSignal("Value"):Connect(function()
		GrowingEggScale.Apply(eggModel, scaleFractionValue)
	end)

	eggModel.Destroying:Connect(function()
		trackedEggs[eggModel] = nil
	end)
end

-- ScaleFraction is added a moment after the egg model is parented (see
-- GrowingEggsService.SpawnGrowingEgg), so a DescendantAdded pass may see the
-- Model before its NumberValue child exists - fall back to ChildAdded.
local function OnDescendantAdded(descendant: Instance)
	if not descendant:IsA("Model") then
		return
	end

	local scaleFractionValue = descendant:FindFirstChild("ScaleFraction")
	if scaleFractionValue then
		TrackEgg(descendant, scaleFractionValue :: NumberValue)
		return
	end

	local connection: RBXScriptConnection
	connection = descendant.ChildAdded:Connect(function(child)
		if child.Name == "ScaleFraction" and child:IsA("NumberValue") then
			connection:Disconnect()
			TrackEgg(descendant, child)
		end
	end)
end

function GrowingEggScaleController.Start()
	local plotsFolder = Workspace:WaitForChild("Functional"):WaitForChild("Spawns"):WaitForChild("Plots")

	for _, descendant in plotsFolder:GetDescendants() do
		OnDescendantAdded(descendant)
	end
	plotsFolder.DescendantAdded:Connect(OnDescendantAdded)
end

return GrowingEggScaleController
