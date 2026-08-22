local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local AnimalsService = require(ServerScriptService.Server.NPCs.AnimalsService)
local DataManager = require(ServerScriptService.Server.Data.Manager)
local GrowingEggsService = require(ServerScriptService.Server.Eggs.GrowingEggsService)
local PlotConfig = require(ReplicatedStorage.Shared.Configs.PlotConfig)
local PlotBaseSpawner = require(script.Parent.PlotBaseSpawner)

local plotSpawns = Workspace:WaitForChild("Functional"):WaitForChild("Spawns"):WaitForChild("Plots")

local PlotAssignment = {}

local function FindEmptyPlot(): Instance?
	for _, plotFolder in plotSpawns:GetChildren() do
		local owner = plotFolder:GetAttribute(PlotConfig.OWNER_ATTRIBUTE)
		if owner == nil or owner == PlotConfig.UNOWNED_OWNER_ID then
			return plotFolder
		end
	end
	return nil
end

local function UpdatePlotBase(plotFolder: Instance, upgradeLevel: string): Model?
	local plotNumber = PlotBaseSpawner.GetPlotNumber(plotFolder)
	local spawnLocation = plotNumber and PlotBaseSpawner.GetSpawnLocation(plotNumber)
	if not spawnLocation then
		warn(("PlotAssignment: no spawn location found for '%s'"):format(plotFolder.Name))
		return nil
	end

	return PlotBaseSpawner.SpawnBase(plotFolder, spawnLocation, upgradeLevel)
end

local function SetupPlayerSign(base: Model, player: Player)
	local playerSign = base:FindFirstChild("PlayerSign")
	local billboard = playerSign and playerSign:FindFirstChild("BillboardGui")
	if not billboard then
		return
	end

	local playerName = billboard:FindFirstChild("PlayerName")
	if playerName then
		playerName.Text = player.DisplayName
	end

	local imageHolder = billboard:FindFirstChild("ImageHolder")
	if not imageHolder then
		return
	end

	imageHolder.Visible = true

	local playerImage = imageHolder:FindFirstChild("PlayerImage")
	if playerImage then
		task.spawn(function()
			local content = Players:GetUserThumbnailAsync(
				player.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
			if playerImage.Parent then
				playerImage.Image = content
			end
		end)
	end
end

local function DestroyPenDoor(base: Model)
	local penDoor = base:FindFirstChild("PenDoor")
	if penDoor then
		penDoor:Destroy()
	end
end

local function SpawnPlotNPCs(plotFolder: Instance, player: Player)
	-- TODO: spawn plot NPCs (out of scope for now)
end

function PlotAssignment.AssignPlot(player: Player)
	local plotFolder = FindEmptyPlot()
	if not plotFolder then
		warn(("PlotAssignment: no empty plot available for '%s'"):format(player.Name))
		player:Kick("No plots are available right now. Please rejoin.")
		return
	end

	plotFolder:SetAttribute(PlotConfig.OWNER_ATTRIBUTE, player.UserId)

	DataManager.YieldUntilLoadedOrReleased(player)
	if not player:IsDescendantOf(Players) then
		return
	end

	local upgradeLevel = DataManager.Get(player, "PlotUpgrade")
	local base = UpdatePlotBase(plotFolder, tostring(upgradeLevel))
	if base then
		SetupPlayerSign(base, player)
		DestroyPenDoor(base)
	end

	SpawnPlotNPCs(plotFolder, player)
	GrowingEggsService.RestoreGrowingEggs(plotFolder, player)
	AnimalsService.RestoreBaseAnimals(plotFolder, player)
end

function PlotAssignment.ReleasePlot(player: Player)
	for _, plotFolder in plotSpawns:GetChildren() do
		if plotFolder:GetAttribute(PlotConfig.OWNER_ATTRIBUTE) == player.UserId then
			plotFolder:SetAttribute(PlotConfig.OWNER_ATTRIBUTE, PlotConfig.UNOWNED_OWNER_ID)
			UpdatePlotBase(plotFolder, PlotConfig.DEFAULT_UPGRADE_LEVEL)
			break
		end
	end
end

return PlotAssignment
