--[[
	AnimalsService

	Spawns and wanders the animal a hatched egg turns into, inside the
	hatching player's own base. Animals are never persisted as world
	Instances between sessions - only PlayerData.BaseAnimals (species, scale,
	offset from the base's Root part) is saved, and SpawnBaseAnimal re-derives
	the world Model from that data every time a player's base is (re)assigned,
	exactly like GrowingEggsService.SpawnGrowingEgg re-derives growing eggs
	from PlayerData.GrowingEggs.

	Movement/spawn/despawn/loop plumbing lives in PathfindingAgent (shared
	with EggGuardsService and any future pathfinding NPC service); everything
	below is base-animal-specific: a plain 2-state Idle/Wandering FSM with a
	single Walk animation (there's deliberately no Run track wired up here at
	all - a base animal only ever walks).
]]

--//Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local PathfindingAgent = require(script.Parent.PathfindingAgent)

--//Configs
local AnimalsConfig = require(ReplicatedStorage.Shared.Configs.AnimalsConfig)
local GrowingEggsConfig = require(ReplicatedStorage.Shared.Configs.GrowingEggsConfig)
local PlotConfig = require(ReplicatedStorage.Shared.Configs.PlotConfig)
local RemoteConfig = require(ReplicatedStorage.Shared.Configs.RemoteConfig)

--//Packages
local ModelUtils = require(ReplicatedStorage.Shared.Packages.ModelUtils)
local Net = require(ReplicatedStorage.Shared.Packages.Net)

--//Modules
local ReplicatedTween = require(ReplicatedStorage.Shared.Modules.ReplicatedTween)

--//Services
local AnimationService = require(ServerScriptService.Server.Animation.AnimationService)
local DataManager = require(ServerScriptService.Server.Data.Manager)
local InventoryService = require(ServerScriptService.Server.Inventory.InventoryService)
local SpawnsEggsService = require(ServerScriptService.Server.Eggs.SpawnsEggsService)

local AnimalModels = ReplicatedStorage.Shared.Assets.Animals
local plotSpawns = Workspace:WaitForChild("Functional"):WaitForChild("Spawns"):WaitForChild("Plots")

-- Offset is stored as plain X/Y/Z numbers, not a Vector3 - DataStores can
-- only hold UTF-8/JSON-safe data, same reasoning as GrowingEggsService's
-- GrowingEggData.
type BaseAnimalData = {
	AnimalName: string,
	Scale: number,
	Offset: { X: number, Y: number, Z: number },
}

local AnimalsService = {}

local function GetBase(plotFolder: Instance): Model?
	return plotFolder:FindFirstChildWhichIsA("Model")
end

local function GetBaseAnimalsFolder(plotFolder: Instance): Folder
	local folder = plotFolder:FindFirstChild("BaseAnimals")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "BaseAnimals"
		folder.Parent = plotFolder
	end
	return folder :: Folder
end

-- Transient holding folder for a hatch showcase's temporary model - kept
-- separate from GetBaseAnimalsFolder/GrowingEggs so this throwaway prop is
-- never mistaken for a real growing egg or base animal by either's own scan
-- loop.
local function GetShowcaseFolder(plotFolder: Instance): Folder
	local folder = plotFolder:FindFirstChild("HatchShowcase")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "HatchShowcase"
		folder.Parent = plotFolder
	end
	return folder :: Folder
end

local function FindOwnedPlotFolder(player: Player): Instance?
	for _, plotFolder in plotSpawns:GetChildren() do
		if plotFolder:GetAttribute(PlotConfig.OWNER_ATTRIBUTE) == player.UserId then
			return plotFolder
		end
	end
	return nil
end

local function GetRig(player: Player): Model?
	local rig = player.Character
	if not rig or not rig.Parent or not rig:FindFirstChild("Humanoid") or rig.Humanoid.Health <= 0 then
		return nil
	end
	return rig
end

-- Is `position` inside `base`'s bounding box, kept back from the edge by
-- GrowingEggsConfig.EDGE_PADDING (X/Z only) - identical check to
-- GrowingEggsService.IsWithinBase, duplicated here rather than requiring
-- that service (which would create a require cycle, since GrowingEggsService
-- already requires AnimalsService).
local function IsWithinBase(base: Model, position: Vector3): boolean
	local cframe, size = base:GetBoundingBox()
	local relative = cframe:PointToObjectSpace(position)
	return math.abs(relative.X) <= size.X / 2 - GrowingEggsConfig.EDGE_PADDING
		and math.abs(relative.Z) <= size.Z / 2 - GrowingEggsConfig.EDGE_PADDING
end

-- Glues a Trail to `part` (own copy of GrowingEggsService.AddPartTrail's
-- Attachment+Trail technique - Attachments at its top/bottom so the trail
-- reads as a streak behind it, not a single point).
local function AddPartTrail(part: BasePart, lifetime: number): Trail
	local halfHeight = part.Size.Y / 2

	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "TrailAttachment0"
	attachment0.Position = Vector3.new(0, halfHeight, 0)
	attachment0.Parent = part

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "TrailAttachment1"
	attachment1.Position = Vector3.new(0, -halfHeight, 0)
	attachment1.Parent = part

	local trail = Instance.new("Trail")
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Lifetime = lifetime
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = part

	return trail
end

-- Chains `stepsLeft` partial Y-axis turns via ReplicatedTween (each covering
-- SHOWCASE_SPIN_SPEED * stepTime degrees), calling onDone() once they've all
-- played - see AnimalsConfig.SHOWCASE_SPIN_SPEED for why a single step's
-- rotation has to stay well under 360°. Position-preserving, same
-- "CFrame * CFrame.Angles(...)" trick GrowingEggsService's wiggle animations
-- already use.
local function SpinInPlace(primaryPart: BasePart, stepsLeft: number, stepTime: number, onDone: () -> ())
	if stepsLeft <= 0 or not primaryPart.Parent then
		onDone()
		return
	end

	local target = primaryPart.CFrame * CFrame.Angles(0, math.rad(AnimalsConfig.SHOWCASE_SPIN_SPEED * stepTime), 0)
	ReplicatedTween.Tween(primaryPart, TweenInfo.new(stepTime, Enum.EasingStyle.Linear), { CFrame = target })
	task.delay(stepTime, function()
		SpinInPlace(primaryPart, stepsLeft - 1, stepTime, onDone)
	end)
end

-- Never trust a computed wander point's raw Y - raycast straight down from
-- well above it to find the real floor there (same technique as
-- GrowingEggsService.SnapToGround / CarryEggsService.GetGroundPosition).
local function SnapToGround(position: Vector3, excludeModel: Instance): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { excludeModel }

	local origin = Vector3.new(position.X, position.Y + 50, position.Z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -100, 0), params)
	return result and result.Position or nil
end

-- (egg's footprint radius / animal template's own footprint radius) *
-- SCALE_MULTIPLIER - same bounding-box-ratio technique
-- SpawnsEggsService.SpawnNest uses to size a nest to its egg.
local function ComputeAnimalScale(eggName: string, eggScale: number, animalName: string): number?
	local eggRadius = SpawnsEggsService.GetEggFootprintRadius(eggName, eggScale)
	local template = AnimalModels:FindFirstChild(animalName)
	if not (eggRadius and template and template:IsA("Model")) then
		return nil
	end

	local _, size = template:GetBoundingBox()
	local animalRadius = math.max(size.X, size.Z) / 2
	if animalRadius <= 0 then
		return nil
	end

	return (eggRadius / animalRadius) * AnimalsConfig.SCALE_MULTIPLIER
end

-- Picks a uniform-random point inside `base`'s own bounding box, inset by
-- GrowingEggsConfig.EDGE_PADDING on X/Z (the same "3 studs from the edge"
-- padding GrowingEggsService.IsWithinBase uses for egg placement) - a
-- bigger/upgraded base naturally gives more room to roam since this is
-- computed straight from the base's real bounding box, not a fixed radius.
-- Retries a few times if a pick fails to ground-snap (e.g. lands over a
-- hole/prop), falling back to `fallback` if every attempt fails.
local function PickWanderTarget(base: Model, excludeModel: Instance, fallback: Vector3): Vector3
	local cframe, size = base:GetBoundingBox()
	local halfX = math.max(size.X / 2 - GrowingEggsConfig.EDGE_PADDING, 0)
	local halfZ = math.max(size.Z / 2 - GrowingEggsConfig.EDGE_PADDING, 0)

	for _ = 1, AnimalsConfig.WANDER_MAX_ATTEMPTS do
		local localPoint = Vector3.new((math.random() * 2 - 1) * halfX, 0, (math.random() * 2 - 1) * halfZ)
		local worldPoint = cframe:PointToWorldSpace(localPoint)
		local grounded = SnapToGround(worldPoint, excludeModel)
		if grounded then
			return grounded
		end
	end

	return fallback
end

local function getAgentRadius(model: Model): number
	return model:GetExtentsSize().X / 2
end

local function getAgentHeight(model: Model): number
	return model:GetExtentsSize().Y
end

-- Ignores Y, same reasoning as EggGuardsService.horizontalDistance - the
-- animal's root sits at a different height than the ground target it's
-- walking toward.
local function horizontalDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

-- Stops the outgoing mode's animation and resumes the incoming one, via
-- state.animations (only "Wandering" has an entry - Idle plays nothing).
local function setMode(state, newMode: string)
	if state.mode == newMode then
		return
	end

	local previousAnimation = state.animations[state.mode]
	local nextAnimation = state.animations[newMode]
	state.mode = newMode

	if previousAnimation and previousAnimation ~= nextAnimation then
		AnimationService.Stop(state.model, previousAnimation)
	end
	if nextAnimation then
		AnimationService.Resume(state.model, nextAnimation)
	end
end

local function think(state)
	local root = state.root
	if not root or not root.Parent then
		return
	end

	if state.mode == "Wandering" then
		if horizontalDistance(root.Position, state.wanderTarget) <= AnimalsConfig.ARRIVE_EPSILON then
			setMode(state, "Idle")
			state.nextWanderAt = os.clock()
				+ AnimalsConfig.WANDER_INTERVAL_MIN
				+ math.random() * (AnimalsConfig.WANDER_INTERVAL_MAX - AnimalsConfig.WANDER_INTERVAL_MIN)
		end
		return
	end

	if os.clock() >= state.nextWanderAt then
		local base = GetBase(state.plotFolder)
		if not base then
			return
		end
		state.wanderTarget = PickWanderTarget(base, state.model, state.spawnCenter)
		setMode(state, "Wandering")
	end
end

local function locomote(state)
	local root = state.root
	if not root or not root.Parent then
		return
	end
	local humanoid = state.humanoid
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	if state.mode == "Wandering" then
		PathfindingAgent.MoveToward(state, state.wanderTarget, { repathDistance = AnimalsConfig.REPATH_DISTANCE })
	else
		PathfindingAgent.StopPath(state)
	end
end

-- Reusable spawn function used both for a fresh hatch and session-restore.
-- `data.Offset` (base.PrimaryPart.Position - spawnPosition, captured once at
-- hatch time) is the sole source of truth for where the animal belongs, so
-- both call sites resolve to the same spot.
function AnimalsService.SpawnBaseAnimal(plotFolder: Instance, animalId: string, data: BaseAnimalData): Model?
	local base = GetBase(plotFolder)
	if not (base and base.PrimaryPart) then
		return nil
	end

	local template = AnimalModels:FindFirstChild(data.AnimalName)
	if not template or not template:IsA("Model") then
		warn(`AnimalsService: no template found for animal "{data.AnimalName}" - skipping`)
		return nil
	end

	local offset = Vector3.new(data.Offset.X, data.Offset.Y, data.Offset.Z)
	local spawnPosition = base.PrimaryPart.Position - offset

	local model = template:Clone()
	model:ScaleTo(data.Scale)
	ModelUtils.AlignModelBottom(model, spawnPosition)

	local agentParams = {
		AgentRadius = getAgentRadius(model),
		AgentHeight = getAgentHeight(model),
		AgentCanJump = true,
		AgentCanClimb = false,
		WaypointSpacing = 4,
	}

	local state = PathfindingAgent.SpawnNPC({
		model = model,
		name = data.AnimalName,
		parent = GetBaseAnimalsFolder(plotFolder),
		agentParams = agentParams,
	})

	model:SetAttribute("AnimalId", animalId)

	state.mode = "Idle"
	state.plotFolder = plotFolder
	state.spawnCenter = spawnPosition
	state.wanderTarget = spawnPosition
	state.nextWanderAt = os.clock()
		+ AnimalsConfig.WANDER_INTERVAL_MIN
		+ math.random() * (AnimalsConfig.WANDER_INTERVAL_MAX - AnimalsConfig.WANDER_INTERVAL_MIN)
	state.animations = {
		Wandering = data.AnimalName .. "Walk",
	}

	if state.humanoid then
		state.humanoid.WalkSpeed = AnimalsConfig.WALK_SPEED
	end

	-- Warm up the Walk track once (forces it to load, lets a late joiner
	-- replay it correctly) then immediately silence it - Idle intentionally
	-- has no animation of its own, so "walk not run" is structural: there is
	-- no Run track wired up for a base animal at all.
	AnimationService.Play(state.model, state.animations.Wandering, true, Enum.AnimationPriority.Movement)
	AnimationService.Stop(state.model, state.animations.Wandering)

	task.spawn(
		PathfindingAgent.RunLoop,
		state,
		think,
		locomote,
		AnimalsConfig.THINK_INTERVAL,
		AnimalsConfig.LOCOMOTION_STEP
	)

	return model
end

-- Flight phase of the showcase: replicates a bezier from the spot the
-- animal just finished spinning at to a point in front of the player's
-- torso (see HatchShowcaseController.luau for the client-side evaluator),
-- then once the flight's had time to finish, destroys the temporary model
-- and actually grants the animal - InventoryService.GrantAnimal, not
-- BaseAnimals, since it's the player's to place from their inventory now.
local function StartShowcaseFlight(model: Model, primaryPart: BasePart, player: Player, animalName: string, scale: number)
	if not model.Parent then
		return
	end

	local rig = player.Character
	local hrp = rig and rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	local startCFrame = primaryPart.CFrame
	local targetCFrame = if hrp
		then hrp.CFrame * CFrame.new(AnimalsConfig.SHOWCASE_TARGET_OFFSET)
		else startCFrame -- player left mid-animation; just hold in place, still finishes/grants below

	local peakPosition = (startCFrame.Position + targetCFrame.Position) / 2
		+ Vector3.new(0, AnimalsConfig.SHOWCASE_ARC_PEAK_HEIGHT, 0)
	local peakCFrame = CFrame.new(peakPosition) * (startCFrame - startCFrame.Position)

	AddPartTrail(primaryPart, AnimalsConfig.SHOWCASE_TRAIL_LIFETIME)

	primaryPart:SetAttribute("ShowcaseStart", startCFrame)
	primaryPart:SetAttribute("ShowcasePeak", peakCFrame)
	primaryPart:SetAttribute("ShowcaseTarget", targetCFrame)
	primaryPart:SetAttribute("ShowcaseStartTime", Workspace:GetServerTimeNow())

	task.delay(AnimalsConfig.SHOWCASE_FLIGHT_TIME, function()
		model:Destroy()
		InventoryService.GrantAnimal(player, animalName, scale)
	end)
end

-- "It hatched!": a temporary, non-wandering copy of the animal appears at
-- the egg's explosion point, spins in place, then flies to the player and
-- (once the flight's finished) is granted as an inventory Tool - see
-- StartShowcaseFlight. This model is never a real NPC (no PathfindingAgent,
-- no Humanoid) - it's a static prop being tweened/bezier-flown, exactly like
-- ExplodeEgg's own scattering parts.
local function PlayHatchShowcase(plotFolder: Instance, player: Player, animalName: string, scale: number, spawnPosition: Vector3)
	local template = AnimalModels:FindFirstChild(animalName)
	if not template or not template:IsA("Model") then
		warn(`AnimalsService: no template found for animal "{animalName}" - skipping showcase`)
		return
	end

	local model = template:Clone()
	model:ScaleTo(scale)

	local primaryPart = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not primaryPart then
		model:Destroy()
		return
	end
	model.PrimaryPart = primaryPart

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Destroy()
	end

	
	-- while it's mid-spin.
	ModelUtils.AlignModelCenter(model, spawnPosition)
	model.PrimaryPart.Anchored = true
	model.Parent = GetShowcaseFolder(plotFolder)

	local stepTime = AnimalsConfig.SHOWCASE_SPIN_TIME / AnimalsConfig.SHOWCASE_SPIN_STEPS
	SpinInPlace(primaryPart, AnimalsConfig.SHOWCASE_SPIN_STEPS, stepTime, function()
		StartShowcaseFlight(model, primaryPart, player, animalName, scale)
	end)
end

-- Kicks off the hatch showcase for a freshly-hatched egg - called from
-- GrowingEggsService.ExplodeEgg's reward hook - `eggModel` is still parented
-- at that point (about to fade), so its EggName/EggScale attributes are read
-- directly off it; `explodeCenter` is ExplodeEgg's own `center` local
-- (the egg's bounding-box center, captured before it scattered).
function AnimalsService.SpawnAnimalFromHatch(eggModel: Model, plotFolder: Instance, player: Player, explodeCenter: Vector3)
	local eggName = eggModel:GetAttribute("EggName")
	local eggScale = eggModel:GetAttribute("EggScale")
	local animalName = eggName and AnimalsConfig.PetForEgg[eggName]
	if not (animalName and eggScale) then
		warn(`AnimalsService: no pet configured for egg "{tostring(eggName)}" - skipping animal spawn`)
		return
	end

	local scale = ComputeAnimalScale(eggName, eggScale, animalName)
	if not scale then
		return
	end

	local spinPosition = explodeCenter + AnimalsConfig.SHOWCASE_SPIN_POSITION_OFFSET
	PlayHatchShowcase(plotFolder, player, animalName, scale, spinPosition)
end

-- Equip-tool-and-click-in-base transfer: the animal-side twin of
-- GrowingEggsService.ValidatePlaceEgg. Moves the animal from
-- PlayerData.InventoryAnimals (+ its Tool) to PlayerData.BaseAnimals (+ a
-- wandering NPC), reusing the same animalId across both so nothing new
-- needs generating.
function AnimalsService.ValidatePlaceAnimal(player: Player, clickedPosition: Vector3)
	if typeof(clickedPosition) ~= "Vector3" then
		return
	end

	local rig = GetRig(player)
	if not rig then
		return
	end

	local tool = rig:FindFirstChildOfClass("Tool")
	local animalId = tool and tool:GetAttribute("AnimalId")
	if not animalId then
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

	local removed = InventoryService.RemoveAnimal(player, animalId)
	if not removed then
		return -- stale tool / already placed elsewhere
	end

	local baseAnimals = DataManager.Get(player, "BaseAnimals")
	if not baseAnimals then
		return
	end

	local offset = base.PrimaryPart.Position - position
	local data: BaseAnimalData = {
		AnimalName = removed.AnimalName,
		Scale = removed.Scale,
		Offset = { X = offset.X, Y = offset.Y, Z = offset.Z },
	}
	baseAnimals[animalId] = data

	AnimalsService.SpawnBaseAnimal(plotFolder, animalId, data)
end

-- Re-spawns every base animal saved in this player's profile - called once
-- their plot/base is (re)assigned (join, respawn, rejoin).
function AnimalsService.RestoreBaseAnimals(plotFolder: Instance, player: Player)
	local baseAnimals = DataManager.Get(player, "BaseAnimals")
	if not baseAnimals then
		return
	end

	for animalId, data in baseAnimals do
		AnimalsService.SpawnBaseAnimal(plotFolder, animalId, data)
	end
end

function AnimalsService.Start(Services)
	Net:Connect(RemoteConfig.Animals.PlaceAnimal.Name, AnimalsService.ValidatePlaceAnimal)
end

return AnimalsService
