local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Shared.Packages.Net)
local InventoryStorage = require(ServerScriptService.Server.Inventory.InventoryStorage)

local InventoryStart = {}

function InventoryStart.Start(Services)
	InventoryStorage = Services.InventoryStorage

	for _, player in Players:GetPlayers() do
		InventoryStorage.SetupPlayer(player)
	end
	Players.PlayerAdded:Connect(InventoryStorage.SetupPlayer)

	Net:Connect("SwitchCategory", function(player: Player, category: string)
		if typeof(category) ~= "string" then
			return
		end
		InventoryStorage.SwitchCategory(player, category)
	end)
end

return InventoryStart
