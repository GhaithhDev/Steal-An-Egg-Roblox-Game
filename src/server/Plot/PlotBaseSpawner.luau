local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local PlotConfig = require(ReplicatedStorage.Shared.Configs.PlotConfig)

local plotAssets = ServerStorage:WaitForChild("ServerAssets"):WaitForChild("Plots")
local functionalFolder = Workspace:WaitForChild("Functional")
local spawnLocations = functionalFolder:WaitForChild("PlotSpawnLocations")
local plotSpawns = functionalFolder:WaitForChild("Spawns"):WaitForChild("Plots")

local PlotBaseSpawner = {}

function PlotBaseSpawner.GetPlotNumber(plotFolder: Instance): string?
	return plotFolder.Name:match("%d+")
end

function PlotBaseSpawner.GetSpawnLocation(plotNumber: string): BasePart?
	return spawnLocations:FindFirstChild(plotNumber) :: BasePart?
end

-- Clears the plot's current contents and clones in the base model matching `upgradeLevel`,
-- positioned at `spawnLocation`. Reused for both the initial server-start reset and
-- per-player upgrade-level assignment.
function PlotBaseSpawner.SpawnBase(plotFolder: Instance, spawnLocation: BasePart, upgradeLevel: string): Model?
	local baseAsset = plotAssets:FindFirstChild(upgradeLevel)
	if not baseAsset then
		warn(("PlotBaseSpawner: no base asset found for upgrade level '%s'"):format(upgradeLevel))
		return nil
	end

	plotFolder:ClearAllChildren()

	local base = baseAsset:Clone()
	base:PivotTo(spawnLocation.CFrame)
	base.Parent = plotFolder

	return base :: Model
end

function PlotBaseSpawner.ResetAllPlots()
	for _, plotFolder in plotSpawns:GetChildren() do
		local plotNumber = PlotBaseSpawner.GetPlotNumber(plotFolder)
		local spawnLocation = plotNumber and PlotBaseSpawner.GetSpawnLocation(plotNumber)

		if not spawnLocation then
			warn(("PlotBaseSpawner: no spawn location found for '%s'"):format(plotFolder.Name))
			continue
		end

		PlotBaseSpawner.SpawnBase(plotFolder, spawnLocation, PlotConfig.DEFAULT_UPGRADE_LEVEL)
	end
end

return PlotBaseSpawner
