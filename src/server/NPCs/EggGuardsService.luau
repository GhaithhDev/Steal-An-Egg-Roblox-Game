--[[
	EggGuardsService

	Spawns one guard per Workspace.Functional.EggGuardsSpawnPositions part and
	runs a simple 4-state behavior on top of PathfindingAgent:

	  Idle             -> arrived back at the spawn position; sleeping.
	  WakingUp         -> just spotted a carrier from Idle; stands still
	                      playing a one-shot wake-up animation before it
	                      actually starts moving.
	  Chasing          -> some player is carrying an egg tagged with this
	                      guard's Area (anywhere on the map - no detection
	                      range); chase the closest such carrier.
	  ReturningToSpawn -> no matching carrier; walk back to the spawn position.

	Each mode has its own animation (state.animations, built per-guard at
	spawn as "<GuardName>Sleep"/"Wakeup"/"Run"/"Walk"); setMode swaps between
	them on every transition. A guard only passes through WakingUp coming
	from Idle - one already moving (ReturningToSpawn) that re-spots a carrier
	jumps straight to Chasing since it's already awake.

	Catching a carrier force-drops their egg (CarryEggsService.ForceDropEgg)
	and briefly stuns/knocks them back. Once the egg is gone - dropped here,
	or banked into inventory by ZoneTrackerService when the player escapes
	with it - AreaEggsService.CarriedEggs[rig] goes nil on its own, so the
	next think() naturally ends the chase; no extra state to unwind either way.

	Movement/spawn/despawn/loop plumbing lives in PathfindingAgent (shared
	with any future pathfinding NPC service); everything below is
	egg-guard-specific decision logic layered on top of it.
]]

--//Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local PathfindingAgent = require(script.Parent.PathfindingAgent)

--//Configs
local EggGuardsConfig = require(ReplicatedStorage.Shared.Configs.EggGuardsConfig)

--//Modules
local ReplicatedTween = require(ReplicatedStorage.Shared.Modules.ReplicatedTween)

--//Services
local AnimationService = require(ServerScriptService.Server.Animation.AnimationService)
local AreaEggsService = require(ServerScriptService.Server.Eggs.AreaEggsService)
local CarryEggsService = require(ServerScriptService.Server.Eggs.CarryEggsService)

local EggGuardAssets = ReplicatedStorage.Shared.Assets.EggGuards

local EggGuardsService = {}

local eggGuardsFolder: Folder?

-- Ignores Y - a guard's root sits at a different height than a player's, so
-- raw Vector3 distance stays large even when they're standing right next to
-- each other.
local function horizontalDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

-- Stops the outgoing mode's animation and resumes the incoming one, via the
-- per-mode animation names built once in state.animations at spawn time
-- (state.animations.Idle = "<GuardName>Sleep", etc.) - a plain lookup instead
-- of special-casing "moving vs idle" now that each of the 4 modes has its own
-- animation. Idle also owns a facing tween (see below), started/cancelled
-- here alongside the animation swap so both always agree on current mode.
local function setMode(state, newMode: string)
	if state.mode == newMode then return end

	local previousMode = state.mode
	local previousAnimation = state.animations[previousMode]
	local nextAnimation = state.animations[newMode]
	state.mode = newMode

	if previousAnimation and previousAnimation ~= nextAnimation then
		AnimationService.Stop(state.model, previousAnimation)
	end
	if nextAnimation then
		AnimationService.Resume(state.model, nextAnimation)
	end

	-- Leaving Idle (e.g. a new carrier shows up mid-tween) cancels any
	-- still-running facing tween instead of letting it keep steering the rig
	-- while it's supposed to be chasing/returning.
	if previousMode == "Idle" and state.facingTween then
		ReplicatedTween.Cancel(state.facingTween)
		state.facingTween = nil
	end

	-- Turns the guard to match its spawn point's original facing instead of
	-- leaving it stuck facing whichever way it happened to be walking when
	-- it arrived. Only rotation is tweened - the goal CFrame shares the
	-- guard's current position, so TweenService only slerps the orientation.
	if newMode == "Idle" then
		local root = state.root
		local targetCFrame = CFrame.new(root.Position) * (state.spawnCFrame - state.spawnCFrame.Position)
		state.facingTween = ReplicatedTween.Tween(
			root,
			TweenInfo.new(EggGuardsConfig.RETURN_FACING_TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ CFrame = targetCFrame }
		)
	end
end

-- Every alive player currently carrying an egg tagged with this guard's Area.
local function getCarriersInArea(state): { { player: Player, root: BasePart } }
	local result = {}
	for _, plr in Players:GetPlayers() do
		local character = plr.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (humanoid and root) or humanoid.Health <= 0 then
			continue
		end

		local egg = AreaEggsService.CarriedEggs[character]
		if not egg or egg:GetAttribute("Area") ~= state.area then
			continue
		end

		table.insert(result, { player = plr, root = root })
	end
	return result
end

-- Closest alive matching-area carrier - no detection range, this guard will
-- path toward a carrier from anywhere on the map.
local function getClosestCarrierRoot(state): BasePart?
	local bestRoot: BasePart? = nil
	local bestDist = math.huge

	for _, entry in getCarriersInArea(state) do
		local dist = horizontalDistance(entry.root.Position, state.root.Position)
		if dist < bestDist then
			bestDist = dist
			bestRoot = entry.root
		end
	end

	return bestRoot
end

-- Ragdolls the player (PlatformStand - physics take over instead of the
-- humanoid holding them upright) and knocks them away from the guard for
-- EggGuardsConfig.STUN_DURATION, then restores their original movement.
local function ragdollAndKnockback(rig: Model, guardRoot: BasePart)
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local rootPart = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return
	end

	local away = rootPart.Position - guardRoot.Position
	away = Vector3.new(away.X, 0, away.Z)
	away = if away.Magnitude > 0 then away.Unit else rootPart.CFrame.LookVector

	local originalWalkSpeed = humanoid.WalkSpeed
	local originalJumpPower = humanoid.JumpPower
	local originalJumpHeight = humanoid.JumpHeight

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.PlatformStand = true

	-- Lands them flat on their back: feet-to-head points along "away" (head
	-- ends up further from the guard than their feet), chest facing straight
	-- up. Built directly from basis vectors rather than composing rotations,
	-- so it doesn't depend on whichever way they happened to be facing.
	local chestUp = Vector3.new(0, 1, 0)
	local rightVector = chestUp:Cross(away)
	rootPart.CFrame = CFrame.fromMatrix(rootPart.Position, rightVector, away)

	rootPart.AssemblyLinearVelocity = away * EggGuardsConfig.KNOCKBACK_FORCE
		+ Vector3.new(0, EggGuardsConfig.KNOCKBACK_UPWARD_FORCE, 0)

	task.delay(EggGuardsConfig.STUN_DURATION, function()
		if humanoid.Parent then
			humanoid.PlatformStand = false
			humanoid.WalkSpeed = originalWalkSpeed
			humanoid.JumpPower = originalJumpPower
			humanoid.JumpHeight = originalJumpHeight
		end
	end)
end

-- Force-drops the egg, ragdolls/knocks the target back, and sends the guard
-- straight home - called once a Chasing guard gets within CATCH_DISTANCE.
local function catchTarget(state, target: BasePart)
	local rig = target.Parent :: Model
	local egg = AreaEggsService.CarriedEggs[rig]
	if not egg or egg:GetAttribute("Area") ~= state.area then return end

	CarryEggsService.ForceDropEgg(rig)
	ragdollAndKnockback(rig, state.root)

	state.target = nil
	setMode(state, "ReturningToSpawn")
end

------------------------------------------------------------------------
-- THINK: pick target + decide state
------------------------------------------------------------------------

local function think(state)
	local root = state.root
	if not root or not root.Parent then return end

	-- Rebuilt every think so newly-joined players are excluded from LOS
	-- blocking, same as the crowd-exclude reasoning in PathfindingAgent.
	state._losParams = PathfindingAgent.BuildLosParams(state.model, { eggGuardsFolder })

	-- Holding the one-shot Wakeup animation - stand still until it's done,
	-- then fall through below to actually start chasing (or stand down, if
	-- the target vanished mid-wake-up).
	if state.mode == "WakingUp" and os.clock() < state.wakeUntil then
		return
	end

	local target = getClosestCarrierRoot(state)
	if target then
		state.target = target
		if state.mode == "Idle" then
			-- Only a freshly-idle guard needs the wake-up beat; one already
			-- moving (ReturningToSpawn) or mid-wake-up-timeout is already awake.
			setMode(state, "WakingUp")
			state.wakeUntil = os.clock() + EggGuardsConfig.WAKEUP_DURATION
			if state.humanoid then
				state.humanoid.Jump = true -- one hop, timed with the Wakeup animation
			end
		else
			setMode(state, "Chasing")
		end
	elseif horizontalDistance(root.Position, state.spawnPosition) <= EggGuardsConfig.ARRIVE_EPSILON then
		setMode(state, "Idle")
		state.target = nil
	else
		setMode(state, "ReturningToSpawn")
		state.target = nil
	end
end

------------------------------------------------------------------------
-- LOCOMOTE: move (runs more often than think)
------------------------------------------------------------------------

local function locomote(state)

	local root = state.root
	if not root or not root.Parent then return end
	local humanoid = state.humanoid
	if not humanoid or humanoid.Health <= 0 then return end

	if state.mode == "Chasing" then
		local target = state.target
		if not (target and target.Parent) then return end

		if horizontalDistance(target.Position, root.Position) <= EggGuardsConfig.CATCH_DISTANCE then
			catchTarget(state, target)
			return
		end

		PathfindingAgent.MoveToward(state, target.Position, { repathDistance = EggGuardsConfig.REPATH_DISTANCE })
	elseif state.mode == "ReturningToSpawn" then
		PathfindingAgent.MoveToward(state, state.spawnPosition, { repathDistance = EggGuardsConfig.REPATH_DISTANCE })
	else -- Idle or WakingUp: hold position (Idle's facing tween is handled in setMode, not here)
		PathfindingAgent.StopPath(state)
	end
end

------------------------------------------------------------------------
-- SPAWN
------------------------------------------------------------------------

local function getAgentRadius(model: Model)
	return model:GetExtentsSize().X / 2
end

local function getAgentHeight(model: Model)
	return model:GetExtentsSize().Y
end

local function spawnEggGuardAt(part: BasePart)
	local template = EggGuardAssets:FindFirstChild(part.Name)
	if not template or not template:IsA("Model") then
		warn(`EggGuardsService: "{part.Name}" has no matching template under Assets.EggGuard - skipping`)
		return
	end

	local area = part:GetAttribute("Area")
	if not area then
		warn(`EggGuardsService: "{part.Name}" has no Area attribute set - skipping`)
		return
	end

	local params = {
		AgentRadius = getAgentRadius(template),
		AgentHeight = getAgentHeight(template),
		AgentCanJump = true,
		AgentCanClimb = false,
		WaypointSpacing = 4,
	}

	local state = PathfindingAgent.SpawnNPC({
		template = template,
		name = part.Name,
		parent = eggGuardsFolder,
		spawnCFrame = part.CFrame,
		agentParams = params,
	})

	state.mode = "Idle"
	state.target = nil
	state.spawnPosition = part.Position
	state.spawnCFrame = part.CFrame
	state.area = area
	state.animations = {
		Idle = state.model.Name .. "Sleep",
		WakingUp = state.model.Name .. "Wakeup",
		Chasing = state.model.Name .. "Run",
		ReturningToSpawn = state.model.Name .. "Walk",
	}
	local thinkInterval = EggGuardsConfig.THINK_INTERVAL_MIN
		+ math.random() * (EggGuardsConfig.THINK_INTERVAL_MAX - EggGuardsConfig.THINK_INTERVAL_MIN)

	-- Warm up all 4 tracks once (forces them to load, and lets late joiners
	-- replay them correctly) then immediately silence them; explicitly resume
	-- Idle to match the starting state.mode - setMode only fires Play/Stop
	-- calls on an actual transition, so without this nothing would be
	-- playing at all until the first state change.
	local ANIMATION_LOOPED = { Idle = true, WakingUp = false, Chasing = true, ReturningToSpawn = true }
	local ANIMATION_PRIORITY = {
		Idle = Enum.AnimationPriority.Idle,
		WakingUp = Enum.AnimationPriority.Action,
		Chasing = Enum.AnimationPriority.Movement,
		ReturningToSpawn = Enum.AnimationPriority.Movement,
	}
	for mode, animationName in state.animations do
		AnimationService.Play(state.model, animationName, ANIMATION_LOOPED[mode], ANIMATION_PRIORITY[mode])
		AnimationService.Stop(state.model, animationName)
	end
	AnimationService.Resume(state.model, state.animations.Idle)

	pcall(think, state) -- set a correct initial state before the loop starts
	task.spawn(PathfindingAgent.RunLoop, state, think, locomote, thinkInterval, EggGuardsConfig.LOCOMOTION_STEP)
end

function EggGuardsService.Start()
	eggGuardsFolder = workspace.Functional.Spawns:FindFirstChild("EggGuards")
	if not eggGuardsFolder then
		eggGuardsFolder = Instance.new("Folder")
		eggGuardsFolder.Name = "EggGuards"
		eggGuardsFolder.Parent = workspace.Functional.Spawns
	end

	local spawnPositions = workspace.Functional:FindFirstChild("EggGuardsSpawnPositions")
	if not spawnPositions then
		warn("EggGuardsService: workspace.Functional.EggGuardsSpawnPositions not found - no guards spawned")
		return
	end

	for _, part in spawnPositions:GetChildren() do
		if part:IsA("BasePart") then
			spawnEggGuardAt(part)
		end
	end
end

return EggGuardsService
