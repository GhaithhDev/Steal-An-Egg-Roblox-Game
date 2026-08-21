--//Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--//Configs
local RemoteConfig = require(ReplicatedStorage.Shared.Configs.RemoteConfig)
local EggsConfig = require(ReplicatedStorage.Shared.Configs.EggsConfig)
local ModelUtils = require(ReplicatedStorage.Shared.Packages.ModelUtils)

--//Packages
local Net = require(ReplicatedStorage.Shared.Packages.Net)
local Trove = require(ReplicatedStorage.Shared.Packages.Trove)

--//Eggs Services
local AreaEggsService = require(ServerScriptService.Server.Eggs.AreaEggsService)
local SpawnsEggsService = require(ServerScriptService.Server.Eggs.SpawnsEggsService)

local SpawnedEggsFolder = workspace.Functional.Spawns.Eggs

local caryringTroves = {}
local CarryEggsService = {}

local function clearCarryTrove(rig)
	if caryringTroves[rig] then
		caryringTroves[rig]:Destroy()
		caryringTroves[rig] = nil
	end
end

local function GetRig(player: Player): Model?
	local rig = player.Character
	if not rig or not rig.Parent or not rig:FindFirstChild("Humanoid") or rig.Humanoid.Health <= 0 then
		return nil
	end
	return rig
end

local function GetGroundPosition(rig: Model): Vector3
	local rootPart = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return rig:GetPivot().Position
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rig }

	local result = workspace:Raycast(rootPart.Position, Vector3.new(0, -50, 0), params)
	if result then
		return result.Position
	end

	local bottomY = ModelUtils.GetModelBottom(rig)
	return Vector3.new(rootPart.Position.X, bottomY, rootPart.Position.Z)
end

-- single source of truth for "stop carrying" - used for an explicit drop
-- request as well as death/CharacterRemoving/Destroying cleanup, so the egg
-- always ends up back on the ground exactly once no matter what triggered it
local function DropEgg(rig: Model, egg: Model?)
	egg = egg or AreaEggsService.CarriedEggs[rig]
	if not egg then
		return
	end

	AreaEggsService.CarriedEggs[rig] = nil
	clearCarryTrove(rig)

	local eggName = egg:GetAttribute("EggName") or egg.Name
	local eggScale = egg:GetAttribute("EggScale") or 1
	local eggArea = egg:GetAttribute("Area")
	local nestSlotIndex = egg:GetAttribute("NestSlotIndex")
	local dropPosition = GetGroundPosition(rig)

	egg:Destroy()

	local offset = rig:GetPivot().LookVector * EggsConfig.DropOffset
	local droppedEgg = SpawnsEggsService.SpawnEgg(eggName, eggScale, dropPosition + offset, false, eggArea)
	if droppedEgg then
		if nestSlotIndex then
			droppedEgg:SetAttribute("NestSlotIndex", nestSlotIndex)
		end
		AreaEggsService.DroppedEggs[droppedEgg] = true
	end
end

-- takes the rig off carrying duty and hands the egg model back to the caller
-- without respawning it on the ground - used when the egg is being claimed
-- into a player's inventory (see ZoneTrackerService) rather than dropped
function CarryEggsService.ClaimCarriedEgg(rig: Model): Model?
	local egg = AreaEggsService.CarriedEggs[rig]
	if not egg then
		return nil
	end

	AreaEggsService.CarriedEggs[rig] = nil
	clearCarryTrove(rig)

	return egg
end

-- forces whatever the rig is currently carrying back onto the ground, exactly
-- like an explicit player drop request - used by EggGuardsService when a
-- guard catches its target
function CarryEggsService.ForceDropEgg(rig: Model)
	DropEgg(rig)
end

function CarryEggsService.CarryEgg(rig: Model, egg: Model, isNPC: boolean?)
	-- rig may be player character or any other rig
	local rootPart = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid: Humanoid? = rig:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then
		warn(`Rig {rig.Name} doesn't have a humanoid, can't carry egg for it`)
		return
	end
	local eggPart = egg.PrimaryPart
	if not eggPart then
		warn(`Egg {egg.Name} doesn't have a primary part therefore it can't be carried`)
		return
	end
	if not rootPart or not eggPart then
		return
	end

	-- if rig is already carrying something else, drop that one properly
	-- first instead of ending up carrying two eggs at once
	local previousEgg = AreaEggsService.CarriedEggs[rig]
	if previousEgg and previousEgg ~= egg then
		DropEgg(rig, previousEgg)
	end

	local prompt = eggPart:FindFirstChild("CarryPrompt")
	if prompt then
		prompt:Destroy()
	end

	-- if the parent is a nest reparent it out of it
	local nest = egg.Parent
	if nest and nest:IsA("Model") then
		egg.Parent = SpawnedEggsFolder
	end

	for _, part in egg:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			if part ~= egg.PrimaryPart then
				local weldToPrimary = part:FindFirstChildWhichIsA("WeldConstraint")
					or Instance.new("WeldConstraint", part)
				weldToPrimary.Part1 = part
				weldToPrimary.Part0 = egg.PrimaryPart
			end
		end
	end

	egg:PivotTo(rootPart.CFrame * CFrame.new(EggsConfig.CARRY_OFFSET))

	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = rootPart
	weld.Part1 = eggPart
	weld.Parent = eggPart

	egg.Parent = rig

	AreaEggsService.CarriedEggs[rig] = egg

	clearCarryTrove(rig)
	local trove = Trove.new()
	caryringTroves[rig] = trove

	trove:Add(humanoid.Died:Connect(function()
		DropEgg(rig, egg)
	end))
	if not isNPC then
		local player: Player? = rig and Players:GetPlayerFromCharacter(rig)
		if player then
			trove:Add(player.CharacterRemoving:Connect(function()
				DropEgg(rig, egg)
			end))
		end
	end
	trove:Add(rig.Destroying:Connect(function()
		DropEgg(rig, egg)
	end))
end

function CarryEggsService.ValidatePlayerCarryEgg(player: Player, egg: Model?)
	if not egg then
		return
	end

	local rig = GetRig(player)
	if not rig then
		return
	end

	if AreaEggsService.CarriedEggs[rig] then
		return -- already carrying an egg
	end

	local rootPart = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	local eggPart = egg.PrimaryPart
	if not rootPart or not eggPart then
		return
	end
	if (rootPart.Position - eggPart.Position).Magnitude > EggsConfig.CARRY_PROMPT_MAX_DISTANCE * 1.5 then
		warn(`Player {player.Name} is too far away from the egg, can't carry it `)
		return -- too far away (e.g. player moved right as the prompt fired)
	end

	if AreaEggsService.DroppedEggs[egg] then
		AreaEggsService.DroppedEggs[egg] = nil
		CarryEggsService.CarryEgg(rig, egg)
		return
	end

	for _, placedEggs in AreaEggsService.EggsInNests do
		for _, placed in placedEggs do
			if placed.eggModel == egg then
				placed.eggModel = nil -- slot stays - the nest itself isn't going anywhere
				CarryEggsService.CarryEgg(rig, egg)
				return
			end
		end
	end

	-- not found in either table - already taken by someone else, ignore
end

local function ValidatePlayerDropEgg(player: Player)
	local rig = GetRig(player)
	if not rig then
		return
	end

	local egg = AreaEggsService.CarriedEggs[rig]
	if not egg then
		return
	end

	DropEgg(rig, egg)
end

function CarryEggsService.Start(Services)
	Net:Connect(RemoteConfig.Eggs.DropEgg.Name, ValidatePlayerDropEgg)
end

return CarryEggsService
