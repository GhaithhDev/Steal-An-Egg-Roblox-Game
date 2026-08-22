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

local AnimalModels = ReplicatedStorage.Shared.Assets.Animals

local InventoryService = {}

-- Converts an animal template into a Tool a player can carry in their
-- Backpack - mirrors SpawnsEggsService.CreateEggTool, but animal rigs are
-- already jointed via Motor6D (unlike plain egg Models), so parts don't need
-- extra WeldConstraints - only Anchored/CanCollide/Massless need resetting
-- so the equipped/dropped Tool doesn't collide with the world. The clone's
-- Humanoid (and its Animator) is destroyed - nothing should drive it as a
-- held item, and an inert Humanoid on an unanchored rig risks looking broken
-- (trying to self-right, etc.); AnimalsService.SpawnBaseAnimal clones its
-- own separate copy with a live Humanoid once the animal is actually placed.
-- Kept local to this module (rather than delegated to AnimalsService, the
-- way CreateEggTool lives in SpawnsEggsService) specifically so
-- InventoryService never has to require AnimalsService, which would create a
-- cycle with AnimalsService's own require of InventoryService.
local function CreateAnimalTool(animalName: string, scale: number, animalId: string): Tool?
	local template = AnimalModels:FindFirstChild(animalName)
	if not template or not template:IsA("Model") then
		return nil
	end

	local animalModel = template:Clone()
	animalModel:ScaleTo(scale)

	local primaryPart = animalModel.PrimaryPart or animalModel:FindFirstChild("HumanoidRootPart")
	if not primaryPart then
		animalModel:Destroy()
		warn(`Animal {animalName} doesn't have a primary part therefore it can't be turned into a tool`)
		return nil
	end
	primaryPart.Name = "Handle"

	local humanoid = animalModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Destroy()
	end

	for _, part in animalModel:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
		end
	end

	local tool = Instance.new("Tool")
	tool.Name = animalName
	tool.RequiresHandle = true
	tool:SetAttribute("AnimalName", animalName)
	tool:SetAttribute("Scale", scale)
	tool:SetAttribute("AnimalId", animalId)
	tool:SetAttribute("Category", "Animals")

	for _, child in animalModel:GetChildren() do
		child.Parent = tool
	end
	animalModel:Destroy()

	return tool
end

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

-- Grants a hatched-and-showcased animal to the player: recorded in their
-- profile under InventoryAnimals keyed by a fresh id, and handed over as an
-- equivalent Tool sharing that same id - same shape as GrantEgg.
function InventoryService.GrantAnimal(player: Player, animalName: string, scale: number)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	local inventoryAnimals = DataManager.Get(player, "InventoryAnimals")
	if not inventoryAnimals then
		return -- profile isn't loaded (yet)
	end

	local animalId = HttpService:GenerateGUID(false)

	local tool = CreateAnimalTool(animalName, scale, animalId)
	if not tool then
		return
	end

	inventoryAnimals[animalId] = { AnimalName = animalName, Scale = scale }
	tool.Parent = backpack
end

-- Mirror of GrantAnimal: pulls an animal back out of the player's profile
-- and destroys its matching Tool - same shape as RemoveEgg.
function InventoryService.RemoveAnimal(player: Player, animalId: string): { AnimalName: string, Scale: number }?
	local inventoryAnimals = DataManager.Get(player, "InventoryAnimals")
	if not inventoryAnimals or not inventoryAnimals[animalId] then
		return nil
	end

	local removed = inventoryAnimals[animalId]
	inventoryAnimals[animalId] = nil

	local containers = { player:FindFirstChildOfClass("Backpack"), player.Character }
	for _, container in containers do
		if not container then
			continue
		end
		for _, tool in container:GetChildren() do
			if tool:IsA("Tool") and tool:GetAttribute("AnimalId") == animalId then
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
	local inventoryAnimals = DataManager.Get(player, "InventoryAnimals")
	if not inventoryEggs and not inventoryAnimals then
		return
	end

	for _, tool in backpack:GetChildren() do
		if tool:IsA("Tool") and (tool:GetAttribute("EggId") or tool:GetAttribute("AnimalId")) then
			tool:Destroy()
		end
	end

	if inventoryEggs then
		for eggId, eggData in inventoryEggs do
			local tool = SpawnsEggsService.CreateEggTool(eggData.EggName, eggData.EggScale, eggId)
			if tool then
				tool.Parent = backpack
			end
		end
	end

	if inventoryAnimals then
		for animalId, animalData in inventoryAnimals do
			local tool = CreateAnimalTool(animalData.AnimalName, animalData.Scale, animalId)
			if tool then
				tool.Parent = backpack
			end
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
