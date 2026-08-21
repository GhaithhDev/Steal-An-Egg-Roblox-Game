--[[
	GrowingEggsService

	Lets a player take an egg out of their inventory and place it in their own
	base to grow. Growing eggs are never persisted as world Instances between
	sessions - only PlayerData.GrowingEggs (scale, start time, offset from the
	base's Root part) is saved, and SpawnGrowingEgg re-derives the world Model
	from that data every time a player's base is (re)assigned, exactly like
	InventoryService.GiveInventoryTools re-derives Backpack Tools from
	InventoryEggs on every CharacterAdded.
]]

--//Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

--//Configs
local EggsConfig = require(ReplicatedStorage.Shared.Configs.EggsConfig)
local GrowingEggsConfig = require(ReplicatedStorage.Shared.Configs.GrowingEggsConfig)
local PlotConfig = require(ReplicatedStorage.Shared.Configs.PlotConfig)
local RemoteConfig = require(ReplicatedStorage.Shared.Configs.RemoteConfig)

--//Packages
local Net = require(ReplicatedStorage.Shared.Packages.Net)
local ModelUtils = require(ReplicatedStorage.Shared.Packages.ModelUtils)

--//Modules
local ReplicatedTween = require(ReplicatedStorage.Shared.Modules.ReplicatedTween)

--//Services
local DataManager = require(ServerScriptService.Server.Data.Manager)
local InventoryService = require(ServerScriptService.Server.Inventory.InventoryService)

local EggModels = ReplicatedStorage.Shared.Assets.Eggs
local plotSpawns = Workspace:WaitForChild("Functional"):WaitForChild("Spawns"):WaitForChild("Plots")

-- Offset is stored as plain X/Y/Z numbers, not a Vector3 - DataStores can
-- only hold UTF-8/JSON-safe data (numbers, strings, booleans, nested tables
-- of those), so a raw Vector3 in the profile fails to save.
type GrowingEggData = {
	EggName: string,
	EggScale: number,
	StartTime: number,
	Offset: { X: number, Y: number, Z: number },
}

local GrowingEggsService = {}

local function FindOwnedPlotFolder(player: Player): Instance?
	for _, plotFolder in plotSpawns:GetChildren() do
		if plotFolder:GetAttribute(PlotConfig.OWNER_ATTRIBUTE) == player.UserId then
			return plotFolder
		end
	end
	return nil
end

local function GetBase(plotFolder: Instance): Model?
	return plotFolder:FindFirstChildWhichIsA("Model")
end

local function GetGrowingEggsFolder(plotFolder: Instance): Folder
	local folder = plotFolder:FindFirstChild("GrowingEggs")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "GrowingEggs"
		folder.Parent = plotFolder
	end
	return folder :: Folder
end

-- Is `position` inside `base`'s bounding box, kept back from the edge by
-- GrowingEggsConfig.EDGE_PADDING (X/Z only - placement is always
-- ground-snapped, see SnapToGround).
local function IsWithinBase(base: Model, position: Vector3): boolean
	local cframe, size = base:GetBoundingBox()
	local relative = cframe:PointToObjectSpace(position)
	return math.abs(relative.X) <= size.X / 2 - GrowingEggsConfig.EDGE_PADDING
		and math.abs(relative.Z) <= size.Z / 2 - GrowingEggsConfig.EDGE_PADDING
end

-- Never trust a client-supplied Y - raycast straight down from well above
-- the clicked spot to find the real floor there (same technique as
-- CarryEggsService.GetGroundPosition).
local function SnapToGround(position: Vector3, rig: Model): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rig }

	local origin = Vector3.new(position.X, position.Y + 50, position.Z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -100, 0), params)
	return result and result.Position or nil
end

local function GetRig(player: Player): Model?
	local rig = player.Character
	if not rig or not rig.Parent or not rig:FindFirstChild("Humanoid") or rig.Humanoid.Health <= 0 then
		return nil
	end
	return rig
end

-- Clones an egg template straight into the world at `position` (bottom
-- aligned there, not the fixed wild-area GroundHeight SpawnsEggsService uses -
-- plots sit at their own elevation) with no nest and no CarryPrompt: a
-- growing egg in a player's own base isn't meant to be stealable.
local function SpawnBareEgg(eggName: string, eggScale: number, position: Vector3): Model?
	local template = EggModels:FindFirstChild(eggName)
	if not template or not template:IsA("Model") then
		return nil
	end

	local eggModel = template:Clone()
	eggModel:ScaleTo(eggScale)
	eggModel:SetAttribute("EggName", eggName)
	eggModel:SetAttribute("EggScale", eggScale)
	ModelUtils.AlignModelBottom(eggModel, position)

	return eggModel
end

-- Jump up then fall/jiggle into its resting CFrame. Non-primary parts are
-- temporarily unanchored and welded to PrimaryPart (same technique
-- CarryEggsService.CarryEgg uses) so tweening just PrimaryPart.CFrame moves
-- the whole model as one rigid piece. Every part is re-anchored once it
-- lands - left unanchored, gravity takes over the instant the tween ends
-- and the egg falls straight through the floor forever, since (unlike a
-- carried egg) nothing keeps steering it after this.
local function PlayPlaceJuice(eggModel: Model)
	local primaryPart = eggModel.PrimaryPart
	if not primaryPart then
		return
	end

	local parts: { BasePart } = {}
	for _, part in eggModel:GetDescendants() do
		if part:IsA("BasePart") and part ~= primaryPart then
			table.insert(parts, part)
			part.Anchored = false
			part.Massless = true
			local weld = part:FindFirstChildWhichIsA("WeldConstraint") or Instance.new("WeldConstraint")
			weld.Part0 = primaryPart
			weld.Part1 = part
			weld.Parent = part
		end
	end

	local restCFrame = primaryPart.CFrame
	primaryPart.CFrame = restCFrame + Vector3.new(0, GrowingEggsConfig.PLACE_JUMP_HEIGHT, 0)

	ReplicatedTween.Tween(
		primaryPart,
		TweenInfo.new(GrowingEggsConfig.PLACE_JUMP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = restCFrame + Vector3.new(0, GrowingEggsConfig.PLACE_JUMP_HEIGHT * 1.3, 0) }
	)

	task.delay(GrowingEggsConfig.PLACE_JUMP_TIME, function()
		if not primaryPart.Parent then
			return
		end

		ReplicatedTween.Tween(
			primaryPart,
			TweenInfo.new(GrowingEggsConfig.PLACE_LAND_TIME, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
			{ CFrame = restCFrame }
		)

		task.delay(GrowingEggsConfig.PLACE_LAND_TIME, function()
			if not primaryPart.Parent then
				return
			end

			primaryPart.CFrame = restCFrame
			for _, part in parts do
				if part.Parent then
					part.Anchored = true
				end
			end
		end)
	end)
end

-- Reusable spawn function used both for a fresh placement and for
-- session-restore. `eggData.Offset` (base.PrimaryPart.Position - restPosition,
-- captured once at placement time) is the sole source of truth for where the
-- egg belongs, so both call sites resolve to the same spot.
function GrowingEggsService.SpawnGrowingEgg(
	plotFolder: Instance,
	eggId: string,
	eggData: GrowingEggData,
	isPlacingNow: boolean
): Model?
	local base = GetBase(plotFolder)
	if not (base and base.PrimaryPart) then
		return nil
	end

	local growTime = EggsConfig.Eggs[eggData.EggName] and EggsConfig.Eggs[eggData.EggName].GrowTime
	if not growTime then
		warn(`GrowingEggsService: no GrowTime configured for egg "{eggData.EggName}"`)
		return nil
	end

	local offset = Vector3.new(eggData.Offset.X, eggData.Offset.Y, eggData.Offset.Z)
	local restPosition = base.PrimaryPart.Position - offset

	local eggModel = SpawnBareEgg(eggData.EggName, eggData.EggScale, restPosition)
	if not eggModel then
		return nil
	end

	eggModel.Parent = GetGrowingEggsFolder(plotFolder)
	eggModel:SetAttribute("EggId", eggId)
	eggModel:SetAttribute("ReadyTime", eggData.StartTime + growTime)

	if isPlacingNow then
		PlayPlaceJuice(eggModel)
	end

	return eggModel
end

-- Re-spawns every growing egg saved in this player's profile - called once
-- their plot/base is (re)assigned (join, respawn, rejoin).
function GrowingEggsService.RestoreGrowingEggs(plotFolder: Instance, player: Player)
	local growingEggs = DataManager.Get(player, "GrowingEggs")
	if not growingEggs then
		return
	end

	for eggId, eggData in growingEggs do
		GrowingEggsService.SpawnGrowingEgg(plotFolder, eggId, eggData, false)
	end
end

local function ValidatePlaceEgg(player: Player, clickedPosition: Vector3)
	if typeof(clickedPosition) ~= "Vector3" then
		return
	end

	local rig = GetRig(player)
	if not rig then
		return
	end

	local tool = rig:FindFirstChildOfClass("Tool")
	local eggId = tool and tool:GetAttribute("EggId")
	if not eggId then
		return
	end

	local plotFolder = FindOwnedPlotFolder(player)
	local base = plotFolder and GetBase(plotFolder)
	if not (plotFolder and base and base.PrimaryPart) then
		return
	end

	local position = SnapToGround(clickedPosition, rig)
	if not position or not IsWithinBase(base, position) then
		return -- outside the base, or too close to its edge
	end

	local removed = InventoryService.RemoveEgg(player, eggId)
	if not removed then
		return -- stale tool / already placed elsewhere
	end

	local growingEggs = DataManager.Get(player, "GrowingEggs")
	if not growingEggs then
		return
	end

	local offset = base.PrimaryPart.Position - position
	local eggData: GrowingEggData = {
		EggName = removed.EggName,
		EggScale = removed.EggScale,
		StartTime = Workspace:GetServerTimeNow(),
		Offset = { X = offset.X, Y = offset.Y, Z = offset.Z },
	}
	growingEggs[eggId] = eggData

	GrowingEggsService.SpawnGrowingEgg(plotFolder, eggId, eggData, true)
end

function GrowingEggsService.Start(Services)
	Net:Connect(RemoteConfig.Eggs.PlaceEgg.Name, ValidatePlaceEgg)
end

return GrowingEggsService
