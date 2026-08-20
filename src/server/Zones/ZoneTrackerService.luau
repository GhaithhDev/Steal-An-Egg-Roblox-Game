--This service tracks which side of the map (Animals area or Bases area) each
--player is on, and notifies the inventory service when a player crosses from
--Animals into Bases while carrying an egg, so that egg gets claimed.

--//Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--//Configs
local ZoneConfig = require(ReplicatedStorage.Shared.Configs.ZoneConfig)

--//Services
local CarryEggsService = require(ServerScriptService.Server.Eggs.CarryEggsService)
local InventoryService = require(ServerScriptService.Server.Inventory.InventoryService)

local ZoneTrackerService = {}

local playerZones: { [Player]: string } = {}

local function GetZone(rootPart: BasePart, borderZ: number): string
	if rootPart.Position.Z < borderZ then
		return ZoneConfig.Zones.Animals
	end
	return ZoneConfig.Zones.Bases
end

-- claims whatever egg the rig is carrying (if any) into the player's
-- inventory instead of it staying carried/dropped
local function ClaimCarriedEggIfAny(player: Player, rig: Model)
	local egg = CarryEggsService.ClaimCarriedEgg(rig)
	if not egg then
		return
	end

	local eggName = egg:GetAttribute("EggName") or egg.Name
	local eggScale = egg:GetAttribute("EggScale") or 1
	egg:Destroy()

	InventoryService.GrantEgg(player, eggName, eggScale)
end

function ZoneTrackerService.Start(Services)
	local borderPart = workspace.Functional.ZoneBorders:WaitForChild("AnimalsBasesAreas") :: BasePart

	Players.PlayerRemoving:Connect(function(player)
		playerZones[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(ZoneConfig.CHECK_INTERVAL)

			local borderZ = borderPart.Position.Z
			for _, player in Players:GetPlayers() do
				local rig = player.Character
				local rootPart = rig and rig:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not rig or not rootPart then
					continue
				end

				local newZone = GetZone(rootPart, borderZ)
				local oldZone = playerZones[player]
				playerZones[player] = newZone

				if oldZone == ZoneConfig.Zones.Animals and newZone == ZoneConfig.Zones.Bases then
					ClaimCarriedEggIfAny(player, rig)
				end
			end
		end
	end)
end

return ZoneTrackerService
