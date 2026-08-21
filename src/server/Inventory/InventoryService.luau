--//Services
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--//Configs
local InventoryConfig = require(ReplicatedStorage.Shared.Configs.InventoryConfig)

--//Packages
local Net = require(ReplicatedStorage.Shared.Packages.Net)

--//Services
local DataManager = require(ServerScriptService.Server.Data.Manager)
local SpawnsEggsService = require(ServerScriptService.Server.Eggs.SpawnsEggsService)

local InventoryService = {}

function InventoryService.SetupPlayer(player: Player)
	player:SetAttribute(InventoryConfig.ACTIVE_CATEGORY_ATTRIBUTE, InventoryConfig.DEFAULT_CATEGORY)

	if player.Character then
		InventoryService.GiveInventoryTools(player)
	end
	player.CharacterAdded:Connect(function()
		InventoryService.GiveInventoryTools(player)
	end)
	
end

function InventoryService.SwitchCategory(player: Player, category: string)
	if not InventoryConfig.Categories[category] then
		return
	end
	player:SetAttribute(InventoryConfig.ACTIVE_CATEGORY_ATTRIBUTE, category)
end

-- Grants a claimed egg to the player: recorded in their profile under
-- InventoryEggs keyed by a fresh id, and handed over as an equivalent Tool
-- sharing that same id, so any action performed on the Tool can be matched
-- back to its InventoryEggs entry.
function InventoryService.GrantEgg(player: Player, eggName: string, eggScale: number)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	local inventoryEggs = DataManager.Get(player, "InventoryEggs")
	if not inventoryEggs then
		return -- profile isn't loaded (yet)
	end

	local eggId = HttpService:GenerateGUID(false)

	local tool = SpawnsEggsService.CreateEggTool(eggName, eggScale, eggId)
	if not tool then
		return
	end

	inventoryEggs[eggId] = { EggName = eggName, EggScale = eggScale }
	tool.Parent = backpack
end

-- Mirror of GrantEgg: pulls an egg back out of the player's profile and
-- destroys its matching Tool - checking both the Backpack and the character
-- (a Tool being placed is typically still equipped, i.e. parented to the
-- character, not sitting in the Backpack). Returns the removed entry so the
-- caller knows what was taken (e.g. to spawn its world representation
-- elsewhere), or nil if eggId didn't match anything (already removed /
-- stale tool - up to the caller to treat that as a no-op).
function InventoryService.RemoveEgg(player: Player, eggId: string): { EggName: string, EggScale: number }?
	local inventoryEggs = DataManager.Get(player, "InventoryEggs")
	if not inventoryEggs or not inventoryEggs[eggId] then
		return nil
	end

	local removed = inventoryEggs[eggId]
	inventoryEggs[eggId] = nil

	local containers = { player:FindFirstChildOfClass("Backpack"), player.Character }
	for _, container in containers do
		if not container then
			continue
		end
		for _, tool in container:GetChildren() do
			if tool:IsA("Tool") and tool:GetAttribute("EggId") == eggId then
				tool:Destroy()
			end
		end
	end

	return removed
end

-- Backpack contents aren't guaranteed to survive a respawn, so every
-- CharacterAdded re-derives the player's Tools from their saved InventoryEggs
-- (the source of truth) instead of relying on the old Tools having stuck
-- around. Tools already present (matched by EggId) are left alone so this is
-- safe to call repeatedly without duplicating anything.
function InventoryService.GiveInventoryTools(player: Player)
	DataManager.YieldUntilLoadedOrReleased(player)
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	local inventoryEggs = DataManager.Get(player, "InventoryEggs")
	if not inventoryEggs then
		return
	end

	for _, tool in backpack:GetChildren() do
		if tool:IsA("Tool") and tool:GetAttribute("EggId") then
			tool:destroy()
		end
	end

	for eggId, eggData in inventoryEggs do
		local tool = SpawnsEggsService.CreateEggTool(eggData.EggName, eggData.EggScale, eggId)
		if tool then
			tool.Parent = backpack
		end
	end
end

function InventoryService.Start(Services)
	for _, player in Players:GetPlayers() do
		InventoryService.SetupPlayer(player)
	end
	Players.PlayerAdded:Connect(InventoryService.SetupPlayer)

	Net:Connect("SwitchCategory", function(player: Player, category: string)
		if typeof(category) ~= "string" then
			return
		end
		InventoryService.SwitchCategory(player, category)
	end)
end

return InventoryService
