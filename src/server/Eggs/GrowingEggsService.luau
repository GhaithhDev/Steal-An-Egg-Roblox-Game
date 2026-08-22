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
local Trove = require(ReplicatedStorage.Shared.Packages.Trove)

--//Modules
local GrowingEggScale = require(ReplicatedStorage.Shared.Modules.GrowingEggScale)
local ReplicatedTween = require(ReplicatedStorage.Shared.Modules.ReplicatedTween)

--//Services
local AnimalsService = require(ServerScriptService.Server.NPCs.AnimalsService)
local DataManager = require(ServerScriptService.Server.Data.Manager)
local InventoryService = require(ServerScriptService.Server.Inventory.InventoryService)
local SpawnsEggsService = require(ServerScriptService.Server.Eggs.SpawnsEggsService)

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

-- Rejects a placement closer than GrowingEggsConfig.MIN_EGG_GAP (edge to edge)
-- to any egg already growing in this base - radii are computed from each
-- egg's full-grown EggScale, not its current (possibly still-baby) rendered
-- size, since a growing egg's footprint only ever gets bigger from here.
local function IsFreeInBase(growingEggsFolder: Instance, position: Vector3, radius: number): boolean
	for _, eggModel in growingEggsFolder:GetChildren() do
		local otherEggName = eggModel:GetAttribute("EggName")
		local otherEggScale = eggModel:GetAttribute("EggScale")
		local otherPosition = eggModel:GetAttribute("RestPosition")
		if not (otherEggName and otherEggScale and otherPosition) then
			continue
		end

		local otherRadius = SpawnsEggsService.GetEggFootprintRadius(otherEggName, otherEggScale)
		if not otherRadius then
			continue
		end

		local minDistance = radius + otherRadius + GrowingEggsConfig.MIN_EGG_GAP
		local distance = (Vector2.new(position.X, position.Z) - Vector2.new(otherPosition.X, otherPosition.Z)).Magnitude
		if distance < minDistance then
			return false
		end
	end
	return true
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
-- growing egg in a player's own base isn't meant to be stealable. Spawns at
-- `eggScale * scaleFraction` - the growth-scale system re-scales it upward
-- from there over time (see SpawnGrowingEgg).
local function SpawnBareEgg(eggName: string, eggScale: number, position: Vector3, scaleFraction: number): Model?
	local template = EggModels:FindFirstChild(eggName)
	if not template or not template:IsA("Model") then
		return nil
	end

	local eggModel = template:Clone()
	eggModel:ScaleTo(eggScale * scaleFraction)
	eggModel:SetAttribute("EggName", eggName)
	eggModel:SetAttribute("EggScale", eggScale)
	ModelUtils.AlignModelBottom(eggModel, position)

	return eggModel
end

-- progress: how far through GrowTime we are, clamped to [0,1]. step: how many
-- GROWTH_STEP_SIZE-sized jumps of that progress have been earned (0..totalSteps).
-- fraction: the EggScale multiplier that step corresponds to.
local TOTAL_GROWTH_STEPS = math.floor((1 - EggsConfig.BABY_SCALE_FRACTION) / GrowingEggsConfig.GROWTH_STEP_SIZE + 0.5)

local function ComputeStep(startTime: number, readyTime: number): (number, number)
	local progress = math.clamp((Workspace:GetServerTimeNow() - startTime) / math.max(readyTime - startTime, 1e-6), 0, 1)
	local step = math.clamp(math.floor(progress * TOTAL_GROWTH_STEPS + 1e-6), 0, TOTAL_GROWTH_STEPS)
	local fraction = math.min(EggsConfig.BABY_SCALE_FRACTION + step * GrowingEggsConfig.GROWTH_STEP_SIZE, 1)
	return step, fraction
end

-- Temporarily unanchors every non-primary part and welds it to PrimaryPart
-- (same technique CarryEggsService.CarryEgg uses) so tweening just
-- PrimaryPart.CFrame moves the whole model as one rigid piece. PrimaryPart
-- itself stays Anchored the whole time - CFrame assignment on an Anchored
-- part is a pure kinematic teleport with no physics involved, whereas an
-- Unanchored part is really simulated by gravity between the CFrame writes
-- ReplicatedTween makes (it only sets the real property once at the start
-- and once at the end, never every frame), which visibly sank the egg into
-- the floor mid-animation before this fix. Welding the followers to a
-- kinematic (Anchored) primary still drags them along rigidly with no sag.
-- Pair with ReanchorParts once the animation settles - a follower left
-- unanchored falls through the floor forever, since (unlike a carried egg)
-- nothing keeps steering it after this.
local function UnanchorAndWeldToPrimary(eggModel: Model): { BasePart }
	local primaryPart = eggModel.PrimaryPart
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
	return parts
end

local function ReanchorParts(parts: { BasePart }, primaryPart: BasePart, restCFrame: CFrame)
	if not primaryPart.Parent then
		return
	end

	primaryPart.CFrame = restCFrame
	for _, part in parts do
		if part.Parent then
			part.Anchored = true
		end
	end
end

-- Jump up then fall/jiggle into its resting CFrame.
local function PlayPlaceJuice(eggModel: Model)
	local primaryPart = eggModel.PrimaryPart
	if not primaryPart then
		return
	end

	local parts = UnanchorAndWeldToPrimary(eggModel)

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
			ReanchorParts(parts, primaryPart, restCFrame)
		end)
	end)
end

-- "Come catch me": wiggle, pop up to READY_ANIM_SCALE_MULTIPLIER with a white
-- highlight, hold, then settle back down. Only called once the egg has fully
-- grown (see UpdateGrowingEgg). Reuses the same ScaleFraction NumberValue the
-- growth system drives - a value above 1 here is a deliberate, temporary
-- overshoot past "fully grown", not a new scale concept.
local function PlayReadyPulse(eggModel: Model)
	local primaryPart = eggModel.PrimaryPart
	local scaleFractionValue = eggModel:FindFirstChild("ScaleFraction")
	local highlight = eggModel:FindFirstChild("ReadyHighlight")
	if not (primaryPart and scaleFractionValue and highlight) then
		return
	end

	local parts = UnanchorAndWeldToPrimary(eggModel)
	local restCFrame = primaryPart.CFrame
	primaryPart.CFrame = restCFrame * CFrame.Angles(0, math.rad(GrowingEggsConfig.READY_ANIM_WIGGLE_ANGLE), 0)

	-- Elastic easing naturally overshoots side to side before settling - a
	-- single tween back to restCFrame reads as a wiggle, not just a snap.
	ReplicatedTween.Tween(
		primaryPart,
		TweenInfo.new(GrowingEggsConfig.READY_ANIM_WIGGLE_TIME, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
		{ CFrame = restCFrame }
	)

	task.delay(GrowingEggsConfig.READY_ANIM_WIGGLE_TIME, function()
		ReanchorParts(parts, primaryPart, restCFrame)
		if not eggModel.Parent then
			return
		end

		ReplicatedTween.Tween(
			scaleFractionValue,
			TweenInfo.new(GrowingEggsConfig.READY_ANIM_SCALE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Value = GrowingEggsConfig.READY_ANIM_SCALE_MULTIPLIER }
		)
		ReplicatedTween.Tween(
			highlight,
			TweenInfo.new(GrowingEggsConfig.READY_ANIM_SCALE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				FillTransparency = GrowingEggsConfig.READY_ANIM_HIGHLIGHT_FILL_TRANSPARENCY,
				OutlineTransparency = GrowingEggsConfig.READY_ANIM_HIGHLIGHT_OUTLINE_TRANSPARENCY,
			}
		)

		task.delay(GrowingEggsConfig.READY_ANIM_SCALE_TIME + GrowingEggsConfig.READY_ANIM_HOLD_TIME, function()
			if not eggModel.Parent then
				return
			end

			ReplicatedTween.Tween(
				scaleFractionValue,
				TweenInfo.new(GrowingEggsConfig.READY_ANIM_SCALE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Value = 1 }
			)
			ReplicatedTween.Tween(
				highlight,
				TweenInfo.new(GrowingEggsConfig.READY_ANIM_SCALE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ FillTransparency = 1, OutlineTransparency = 1 }
			)
		end)
	end)
end

-- Glues a Trail to `part` (Attachments at its top/bottom so the trail reads
-- as a streak behind the chunk, not a single point) for the explosion's arc.
-- Caller disables it once the part lands - Enabled = false stops emitting new
-- points and lets whatever's already emitted age out over TRAIL_LIFETIME,
-- instead of leaving a frozen streak on a part that's about to fade.
local function AddPartTrail(part: BasePart): Trail
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
	trail.Lifetime = GrowingEggsConfig.HATCH_EXPLODE_TRAIL_LIFETIME
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = part

	return trail
end

-- Every individual part flies outward from the model's center along a real
-- quadratic bezier curve (start -> outward-and-up peak -> a randomized
-- ground point), then fades out and the whole model is destroyed. The curve
-- itself is animated client-side via RunService, not ReplicatedTween (see
-- HatchExplosionController.luau) - it's a one-shot cosmetic with no gameplay
-- state riding on it, so the server just decides and replicates the three
-- curve points (as CFrame attributes) plus one shared start time, and every
-- client independently evaluates the same bezier each frame - no per-frame
-- server work, no tween-goal replication. Every part (including PrimaryPart,
-- unlike the rigid wiggle phases) goes fully independent here: any
-- WeldConstraint left over from the wiggle phases' UnanchorAndWeldToPrimary
-- is destroyed so followers stop rigidly tracking the primary, CanCollide is
-- dropped so flying debris can't shove the player, and every part stays
-- Anchored the whole time - moving an Unanchored part's CFrame between real
-- property writes gets it really physics-simulated in between, which
-- visibly sags/sinks it (see UnanchorAndWeldToPrimary's comment for the same
-- bug this project already hit once).
local function ExplodeEgg(eggModel: Model, plotFolder: Instance, player: Player)
	local primaryPart = eggModel.PrimaryPart
	if not primaryPart then
		return
	end

	local boundsCFrame = eggModel:GetBoundingBox()
	local center = boundsCFrame.Position

	local allParts: { BasePart } = {}
	for _, part in eggModel:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(allParts, part)
		end
	end

	local trails: { [BasePart]: Trail } = {}
	local groundCFrames: { [BasePart]: CFrame } = {}

	-- One shared start time for every part, so all of them begin their curve
	-- on the same frame instead of drifting apart tick by tick.
	local startTime = Workspace:GetServerTimeNow()

	for _, part in allParts do
		local weld = part:FindFirstChildWhichIsA("WeldConstraint")
		if weld then
			weld:Destroy()
		end
		part.Anchored = true
		part.CanCollide = false
		trails[part] = AddPartTrail(part)

		local startCFrame = part.CFrame
		-- Angle covers the full circle and distance is independently randomized
		-- per part (not shared across the whole egg), so parts scatter rather
		-- than fly out in a uniform ring.
		local angle = math.random() * math.pi * 2
		local distance = GrowingEggsConfig.HATCH_EXPLODE_MIN_DISTANCE
			+ math.random() * (GrowingEggsConfig.HATCH_EXPLODE_MAX_DISTANCE - GrowingEggsConfig.HATCH_EXPLODE_MIN_DISTANCE)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))

		local horizontalTarget = center + direction * distance
		local groundPosition = SnapToGround(horizontalTarget, eggModel)
			or Vector3.new(horizontalTarget.X, center.Y, horizontalTarget.Z)
		local peakPosition = startCFrame.Position
			+ direction * (distance * 0.5)
			+ Vector3.new(0, GrowingEggsConfig.HATCH_EXPLODE_ARC_PEAK_HEIGHT, 0)

		-- Position-only change across the curve; keep whatever rotation the
		-- part already has (CFrame.new(newPos) * (startCFrame - startCFrame.Position)
		-- strips the old position but keeps the old rotation component).
		local peakCFrame = CFrame.new(peakPosition) * (startCFrame - startCFrame.Position)
		local groundCFrame = CFrame.new(groundPosition) * (startCFrame - startCFrame.Position)
		groundCFrames[part] = groundCFrame

		-- The whole handoff to the client: the three bezier control points
		-- plus a shared start time (duration lives in GrowingEggsConfig,
		-- already available client-side - no need to replicate it too).
		part:SetAttribute("ExplodeStart", startCFrame)
		part:SetAttribute("ExplodePeak", peakCFrame)
		part:SetAttribute("ExplodeGround", groundCFrame)
		part:SetAttribute("ExplodeStartTime", startTime)
	end

	task.delay(GrowingEggsConfig.HATCH_EXPLODE_ARC_TIME, function()
		if not eggModel.Parent then
			return
		end

		-- Remove from PlayerData.GrowingEggs now that parts have visually
		-- landed, before the fade starts - a mid-animation server crash can
		-- never leave a duplicated/lost egg, since nothing past this point
		-- still depends on the profile entry.
		local eggId = eggModel:GetAttribute("EggId")
		if eggId then
			local growingEggs = DataManager.Get(player, "GrowingEggs")
			if growingEggs then
				growingEggs[eggId] = nil
			end
		end

		-- Spawn the pet this egg hatches into in the player's base before the
		-- fade/destroy below - reads EggName/EggScale/RestPosition straight off
		-- eggModel (still parented here) and saves it into PlayerData.BaseAnimals.
		AnimalsService.SpawnAnimalFromHatch(eggModel, plotFolder, player, center)

		for _, trail in trails do
			trail.Enabled = false
		end

		for _, part in allParts do
			if part.Parent then
				-- Snap the server's own authoritative CFrame to where every
				-- client's local curve just landed - plain assignment, not a
				-- tween, since the flight itself is already over; purely for
				-- tidiness (nothing server-side reads it again before the
				-- Destroy below).
				part.CFrame = groundCFrames[part]
				ReplicatedTween.Tween(
					part,
					TweenInfo.new(GrowingEggsConfig.HATCH_EXPLODE_FADE_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
					{ Transparency = 1 }
				)
			end
		end

		task.delay(GrowingEggsConfig.HATCH_EXPLODE_FADE_TIME, function()
			if eggModel.Parent then
				eggModel:Destroy()
			end
		end)
	end)
end

-- Scales the egg up (same visual as PlayReadyPulse's scale+highlight step,
-- but held rather than settled back down since the egg is about to explode)
-- then hands off to ExplodeEgg once the scale tween has actually committed.
local function PlayHatchScaleAndExplode(
	eggModel: Model,
	plotFolder: Instance,
	player: Player,
	scaleFractionValue: NumberValue,
	highlight: Highlight
)
	if not eggModel.Parent then
		return
	end

	ReplicatedTween.Tween(
		scaleFractionValue,
		TweenInfo.new(GrowingEggsConfig.READY_ANIM_SCALE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = GrowingEggsConfig.READY_ANIM_SCALE_MULTIPLIER }
	)
	ReplicatedTween.Tween(
		highlight,
		TweenInfo.new(GrowingEggsConfig.READY_ANIM_SCALE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			FillTransparency = GrowingEggsConfig.READY_ANIM_HIGHLIGHT_FILL_TRANSPARENCY,
			OutlineTransparency = GrowingEggsConfig.READY_ANIM_HIGHLIGHT_OUTLINE_TRANSPARENCY,
		}
	)

	-- Scale tween must fully finish before ExplodeEgg starts moving parts
	-- independently - GrowingEggScale.Apply (the ScaleFraction listener)
	-- calls eggModel:ScaleTo() + ModelUtils.AlignModelBottom on every value
	-- change, which would clobber any part already mid-flight if it fired
	-- during the explosion. Since ScaleFraction never changes again after
	-- this (it stays parked at READY_ANIM_SCALE_MULTIPLIER), there's no risk
	-- once this single tween settles.
	task.delay(GrowingEggsConfig.READY_ANIM_SCALE_TIME, function()
		if not eggModel.Parent then
			return
		end
		ExplodeEgg(eggModel, plotFolder, player)
	end)
end

-- "It's hatching!": wiggle three times with escalating intensity (pausing
-- between each), then scale up + highlight (held, not settled back down),
-- then explode. Sets IsHatching so UpdateGrowingEgg's growth/ready-pulse
-- logic leaves this egg alone for the rest of the sequence, and so
-- GrowingEggGuiController can hide its "Ready!" countdown billboard.
local function PlayHatchSequence(eggModel: Model, plotFolder: Instance, player: Player)
	local primaryPart = eggModel.PrimaryPart
	local scaleFractionValue = eggModel:FindFirstChild("ScaleFraction")
	local highlight = eggModel:FindFirstChild("ReadyHighlight")
	if not (primaryPart and scaleFractionValue and highlight) then
		return
	end

	eggModel:SetAttribute("IsHatching", true)

	local parts = UnanchorAndWeldToPrimary(eggModel)
	local restCFrame = primaryPart.CFrame

	local function PlayWiggle(angleDegrees: number, onDone: () -> ())
		if not primaryPart.Parent then
			return
		end
		primaryPart.CFrame = restCFrame * CFrame.Angles(0, math.rad(angleDegrees), 0)
		ReplicatedTween.Tween(
			primaryPart,
			TweenInfo.new(GrowingEggsConfig.HATCH_WIGGLE_TIME, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
			{ CFrame = restCFrame }
		)
		task.delay(GrowingEggsConfig.HATCH_WIGGLE_TIME + GrowingEggsConfig.HATCH_WIGGLE_PAUSE_TIME, onDone)
	end

	local angles = GrowingEggsConfig.HATCH_WIGGLE_ANGLES
	PlayWiggle(angles[1], function()
		PlayWiggle(angles[2], function()
			PlayWiggle(angles[3], function()
				if not eggModel.Parent then
					return
				end
				ReanchorParts(parts, primaryPart, restCFrame)
				PlayHatchScaleAndExplode(eggModel, plotFolder, player, scaleFractionValue, highlight)
			end)
		end)
	end)
end

-- "It's ready - come hatch it": mirrors AddCarryPrompt's convention
-- (SpawnsEggsService.luau), but triggers PlayHatchSequence and destroys
-- itself immediately on first valid trigger so a second in-flight Triggered
-- fire can never start the sequence twice.
local function AddHatchPrompt(eggModel: Model, plotFolder: Instance)
	local primaryPart = eggModel.PrimaryPart
	if not primaryPart then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HatchPrompt"
	prompt.ActionText = GrowingEggsConfig.HATCH_PROMPT_ACTION_TEXT
	prompt.ObjectText = eggModel.Name
	prompt.HoldDuration = GrowingEggsConfig.HATCH_PROMPT_HOLD_DURATION
	prompt.MaxActivationDistance = GrowingEggsConfig.HATCH_PROMPT_MAX_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = primaryPart

	local hatchPromptTrove = Trove.new()
	hatchPromptTrove:Add(prompt.Triggered:Connect(function(player: Player)
		if eggModel:GetAttribute("IsHatching") then
			return -- already hatching (race between two rapid triggers)
		end
		if plotFolder:GetAttribute(PlotConfig.OWNER_ATTRIBUTE) ~= player.UserId then
			return -- plot changed owner since the prompt was created
		end

		prompt:Destroy()
		PlayHatchSequence(eggModel, plotFolder, player)
	end))

	local function clearPromptTrove()
		hatchPromptTrove:Destroy()
	end
	eggModel.Destroying:Connect(clearPromptTrove)
	prompt.Destroying:Connect(clearPromptTrove)
end

local function RandomReadyInterval(): number
	return GrowingEggsConfig.READY_ANIM_MIN_INTERVAL
		+ math.random() * (GrowingEggsConfig.READY_ANIM_MAX_INTERVAL - GrowingEggsConfig.READY_ANIM_MIN_INTERVAL)
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

	local readyTime = eggData.StartTime + growTime
	local step, fraction = ComputeStep(eggData.StartTime, readyTime)

	local eggModel = SpawnBareEgg(eggData.EggName, eggData.EggScale, restPosition, fraction)
	if not eggModel then
		return nil
	end

	eggModel.Parent = GetGrowingEggsFolder(plotFolder)
	eggModel:SetAttribute("EggId", eggId)
	eggModel:SetAttribute("StartTime", eggData.StartTime)
	eggModel:SetAttribute("ReadyTime", readyTime)
	eggModel:SetAttribute("GrowthStep", step)
	eggModel:SetAttribute("RestPosition", restPosition)

	local scaleFractionValue = Instance.new("NumberValue")
	scaleFractionValue.Name = "ScaleFraction"
	scaleFractionValue.Value = fraction
	scaleFractionValue.Parent = eggModel

	scaleFractionValue:GetPropertyChangedSignal("Value"):Connect(function()
		GrowingEggScale.Apply(eggModel, scaleFractionValue)
	end)

	local highlight = Instance.new("Highlight")
	highlight.Name = "ReadyHighlight"
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = eggModel

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

	local eggName = tool:GetAttribute("EggName")
	local eggScale = tool:GetAttribute("EggScale")
	local radius = eggName and eggScale and SpawnsEggsService.GetEggFootprintRadius(eggName, eggScale)
	if not radius then
		return
	end

	if not IsFreeInBase(GetGrowingEggsFolder(plotFolder), position, radius) then
		return -- too close to an already-growing egg
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

-- Bumps `eggModel`'s GrowthStep the moment real elapsed time crosses a new
-- GROWTH_STEP_SIZE threshold, animating the pop via ReplicatedTween. The
-- attribute is bumped synchronously (before the tween finishes) so this
-- doesn't fire the same step again next tick while the tween is still in
-- flight - the ScaleFraction NumberValue's real server-side value only
-- updates once ReplicatedTween's tween duration elapses. Once fully grown,
-- switches to scheduling/triggering the periodic ready-pulse instead - same
-- reasoning applies to NextReadyAnimAt (bumped synchronously so a pulse
-- already in flight, which briefly pushes ScaleFraction past 1.0, isn't
-- mistaken for a new step or re-triggered next tick).
local function UpdateGrowingEgg(eggModel: Model, plotFolder: Instance)
	if eggModel:GetAttribute("IsHatching") then
		return -- mid-hatch animation; growth/ready-pulse logic no longer applies
	end

	local startTime = eggModel:GetAttribute("StartTime")
	local readyTime = eggModel:GetAttribute("ReadyTime")
	local currentStep = eggModel:GetAttribute("GrowthStep")
	if not (startTime and readyTime and currentStep) then
		return
	end

	if currentStep < TOTAL_GROWTH_STEPS then
		local targetStep, targetFraction = ComputeStep(startTime, readyTime)
		if targetStep <= currentStep then
			return
		end

		local scaleFractionValue = eggModel:FindFirstChild("ScaleFraction")
		if not scaleFractionValue then
			return
		end

		eggModel:SetAttribute("GrowthStep", targetStep)
		ReplicatedTween.Tween(
			scaleFractionValue,
			TweenInfo.new(GrowingEggsConfig.GROWTH_STEP_TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Value = targetFraction }
		)
		return
	end

	local now = Workspace:GetServerTimeNow()
	local nextAnimAt = eggModel:GetAttribute("NextReadyAnimAt")
	if not nextAnimAt then
		eggModel:SetAttribute("NextReadyAnimAt", now + RandomReadyInterval())
		AddHatchPrompt(eggModel, plotFolder)
		return
	end

	if now >= nextAnimAt then
		eggModel:SetAttribute("NextReadyAnimAt", now + RandomReadyInterval())
		PlayReadyPulse(eggModel)
	end
end

local function StartGrowthLoop()
	task.spawn(function()
		while true do
			task.wait(GrowingEggsConfig.GROWTH_CHECK_INTERVAL)

			for _, plotFolder in plotSpawns:GetChildren() do
				local growingEggsFolder = plotFolder:FindFirstChild("GrowingEggs")
				if not growingEggsFolder then
					continue
				end

				for _, eggModel in growingEggsFolder:GetChildren() do
					UpdateGrowingEgg(eggModel, plotFolder)
				end
			end
		end
	end)
end

function GrowingEggsService.Start(Services)
	Net:Connect(RemoteConfig.Eggs.PlaceEgg.Name, ValidatePlaceEgg)
	StartGrowthLoop()
end

return GrowingEggsService
