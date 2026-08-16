local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local PlotBaseSpawner = require(ServerScriptService.Server.Plot.PlotBaseSpawner)
local PlotAssignment = require(ServerScriptService.Server.Plot.PlotAssignment)

local PlotStart = {}

function PlotStart.Start(Services)
	PlotBaseSpawner = Services.PlotBaseSpawner
	PlotAssignment = Services.PlotAssignment

	PlotBaseSpawner.ResetAllPlots()

	for _, player in Players:GetPlayers() do
		task.spawn(PlotAssignment.AssignPlot, player)
	end

	Players.PlayerAdded:Connect(PlotAssignment.AssignPlot)
	Players.PlayerRemoving:Connect(PlotAssignment.ReleasePlot)
end

return PlotStart
