--[[
	PathfindingAgent

	Generic, decision-free NPC movement/lifecycle primitives shared by every
	pathfinding NPC service (BaseZombieService, WaiterService, ...): agent
	params, a global pathfinding-compute budget, LOS-aware steering, generic
	spawn/despawn, and a cadence-driven think/locomote loop runner.

	Callers own all decision logic (what state to be in, who to target, when
	to attack) — this module only owns "how to move" and "how to come and go".
]]

--//Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

--//Packages
local Packages = ReplicatedStorage.Shared.Packages
local SimplePath = require(Packages.SimplePath)
local Trove = require(Packages.Trove)

local PathfindingAgent = {}

--//Configs
local BasePathFindingConfig = require(ReplicatedStorage.Shared.Configs.BasePathFindingConfig)
local DEBUG = false
PathfindingAgent.DEFAULT_AGENT_PARAMS = {
	AgentRadius = 2,
	AgentHeight = 5,
	AgentCanJump = true,
	AgentCanClimb = false,
	WaypointSpacing = 4,
}

------------------------------------------------------------------------
-- GLOBAL COMPUTE BUDGET (soft, refilled each Heartbeat)
------------------------------------------------------------------------

local function debugPrint(...)
	if DEBUG then
		print(...)
	end
end
-- Horde safety valve: soft cap on heavy path computes per frame across every
-- NPC drawing from this module, regardless of which service spawned them.
local GLOBAL_COMPUTE_BUDGET = 8
local computeTokens = GLOBAL_COMPUTE_BUDGET

RunService.Heartbeat:Connect(function()
	computeTokens = GLOBAL_COMPUTE_BUDGET
end)

function PathfindingAgent.TakeComputeToken(): boolean
	if computeTokens > 0 then
		computeTokens -= 1
		return true
	end
	return false
end

------------------------------------------------------------------------
-- LINE OF SIGHT
------------------------------------------------------------------------

-- The two NPC folders every pathfinding NPC service currently wants excluded
-- from its own LOS checks, so a dense crowd doesn't block its own sight.
-- Centralized here (rather than each service re-deriving the same list) so
-- adding a third NPC folder later only needs one edit, not one per service.
function PathfindingAgent.BuildDefaultExcludeList(): { Instance }
	local exclude = {}
	local spawns = workspace:FindFirstChild("Spawns")
	local zombiesFolder = spawns and spawns:FindFirstChild("Zombies")
	if zombiesFolder then
		table.insert(exclude, zombiesFolder)
	end
	local allies = spawns and spawns:FindFirstChild("Allies")
	if allies then
		table.insert(exclude, allies)
	end
	return exclude
end

-- Excludes the NPC itself, every player character, and whatever extra
-- instances the caller supplies (e.g. a Zombies or Allies folder) so a dense
-- crowd of NPCs doesn't block its own LOS.
function PathfindingAgent.BuildLosParams(model: Model, extraExcludeInstances: { Instance }?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local exclude = { model }
	if extraExcludeInstances then
		for _, inst in extraExcludeInstances do
			table.insert(exclude, inst)
		end
	end

	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(exclude, plr.Character)
		end
	end

	params.FilterDescendantsInstances = exclude
	return params
end

local function getLosSamplePoints(fromCFrame: CFrame, modelSize: Vector3): { Vector3 }

	local center = fromCFrame.Position
	local right = (modelSize.X/2 - BasePathFindingConfig.LOS_OFFSET_FROM_EDGE) * fromCFrame.RightVector
	local up = (modelSize.Y/2 - BasePathFindingConfig.LOS_OFFSET_FROM_EDGE) * fromCFrame.UpVector
	--[[return {
		center - right - up, -- bottom left
		center + right - up, -- bottom right
		center,              -- center
		center + right + up, -- top right
		center - right + up, -- top left
	}]]
	return {
		center + right, -- center right
		center,              -- center
		center - right, -- center left
	}
end

function PathfindingAgent.HasLineOfSight(fromCFrame: CFrame, toPos: Vector3, params: RaycastParams, modelSize: Vector3): boolean
	for _, fromPoint in getLosSamplePoints(fromCFrame,modelSize) do
		local result = workspace:Raycast(fromPoint, toPos - fromPoint, params)
		if result and result.Instance.Parent.Parent.Name ~= "Keycaps" then
			return false
		end
	end
	return true
end

------------------------------------------------------------------------
-- MOVEMENT
------------------------------------------------------------------------

function PathfindingAgent.StopPath(state)
	if state.path.Status == "Active" then
		pcall(function()
			state.path:Stop()
		end)
	end
end

-- LOS clear -> steer straight (cheap, tracks moving targets);
-- LOS blocked -> SimplePath, recomputed only when stale or inactive.
function PathfindingAgent.MoveToward(state, toPos: Vector3, opts: { computeBudget: (() -> boolean)?, repathDistance: number? }?)
	opts = opts or {}
	local computeBudget = opts.computeBudget or PathfindingAgent.TakeComputeToken
	local repathDistance = opts.repathDistance or 6

	local losParams = state._losParams or PathfindingAgent.BuildLosParams(state.model)
	if PathfindingAgent.HasLineOfSight(state.root.CFrame, toPos, losParams, state.model:GetExtentsSize()) then
		
		PathfindingAgent.StopPath(state)
		state.humanoid:MoveTo(toPos)
		print(`MoveTo called on {state.humanoid.Parent.Name}`)
	else
		local targetMoved = (toPos - (state.lastPathTarget or Vector3.zero)).Magnitude
		local npcMoved = state.lastNPCPosition and (state.root.Position - state.lastNPCPosition).Magnitude or 0
		local isStuck = npcMoved < BasePathFindingConfig.STUCK_DISTANCE
		if isStuck then
			debugPrint( "[" .. state.model.Name .. "]" .. "NPC appears stuck; forcing a new path")
		end
		state.lastNPCPosition = state.root.Position
		if state.path.Status ~= "Active" or targetMoved > repathDistance or isStuck then
			debugPrint( "[" .. state.model.Name .. "]" .. "computing new path to: ", toPos, "targetMoved: ", targetMoved, "lastPathTarget: ", state.lastPathTarget)
			if computeBudget() then
				state.lastPathTarget = toPos
				pcall(function()
					state.path:Run(toPos)
				end)
			end
		else
			debugPrint( "[" .. state.model.Name .. "]" .. "continuing existing path to: ", state.lastPathTarget, "targetMoved: ", targetMoved)
		end
	end
end

------------------------------------------------------------------------
-- SPAWN / DESPAWN
------------------------------------------------------------------------

--[[
	opts:
		model: Model?      -- use this existing instance as-is (no clone)
		template: Model?   -- clone this instead (exactly one of model/template required)
		name: string?      -- renames the model
		tag: string?       -- logging tag (defaults to the model's name)
		parent: Instance?  -- reparent into this; omit to leave wherever it already is
		spawnCFrame: CFrame?
		agentParams: table? -- defaults to PathfindingAgent.DEFAULT_AGENT_PARAMS
		setNetworkOwnerNil: boolean? -- defaults to true (server-authoritative movement)
		needsMeasurePath: boolean? -- defaults to false; only path-length-comparing callers (e.g. BaseZombieService's target selection) need this extra Path object
		registry: table?   -- [Model] = state; populated here, cleared by DespawnNPC
		onDied: ((state) -> ())? -- service-specific death bookkeeping; despawn always follows

	Returns the generic movement/lifecycle state table. Callers attach their
	own decision-logic fields (mode, target, etc.) to the returned table.
]]
function PathfindingAgent.SpawnNPC(opts): { [string]: any }
	local model = opts.model
	if not model then
		assert(opts.template, "PathfindingAgent.SpawnNPC requires opts.model or opts.template")
		model = opts.template:Clone()
	end

	if opts.name then
		model.Name = opts.name
	end

	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChild("HumanoidRootPart") :: BasePart
	end

	if opts.parent then
		model.Parent = opts.parent
	end

	if opts.spawnCFrame then
		model:PivotTo(opts.spawnCFrame)
	end

	local root = model.PrimaryPart :: BasePart
	if opts.setNetworkOwnerNil ~= false then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end

	local agentParams = opts.agentParams or PathfindingAgent.DEFAULT_AGENT_PARAMS

	local trove = Trove.new()
	local path = SimplePath.new(model, agentParams)
	trove:Add(path)
	local measurePath = nil
	if opts.needsMeasurePath then
		measurePath = PathfindingService:CreatePath(agentParams)
		trove:Add(measurePath)
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("Humanoid wasn't found in " .. model.Name )
	end
	local state = {
		model = model,
		tag = opts.tag or model.Name,
		humanoid = humanoid,
		root = root,
		path = path,
		measurePath = measurePath,
		trove = trove,

		lastPathTarget = nil,
		_losParams = nil,
		_alive = true,
	}

	-- in-progress path got obstructed -> force a fresh path next move
	trove:Connect(path.Blocked, function()
		state.lastPathTarget = nil
	end)

	if state.humanoid then
		trove:Connect(state.humanoid.Died, function()
			if opts.onDied then
				local ok, err = pcall(opts.onDied, state)
				if not ok then
					warn("[PathfindingAgent] onDied error:", err)
				end
			end
			PathfindingAgent.DespawnNPC(state, opts.registry)
		end)
	end

	if opts.registry then
		opts.registry[model] = state
	end

	return state
end

-- Idempotent: safe to call once from a manual removal and again if
-- Humanoid.Died also fires around the same time.
function PathfindingAgent.DespawnNPC(state, registry: { [Model]: any }?)
	if not state._alive then
		return
	end
	state._alive = false
	if registry then
		registry[state.model] = nil
	end
	state.trove:Destroy() -- destroys SimplePath, measurePath; disconnects events
	if state.model.Parent then
		state.model:Destroy()
	end
end

------------------------------------------------------------------------
-- LOOP RUNNER
------------------------------------------------------------------------

-- Alternates thinkFn (slow: target/state decisions) and locomoteFn (fast:
-- steering/attacks) on independent cadences, with a random initial phase so
-- a batch spawned on the same frame doesn't think in lockstep.
function PathfindingAgent.RunLoop(state, thinkFn: (any) -> (), locomoteFn: (any) -> (), thinkInterval: number, locomoteStep: number)
	state._lastThink = os.clock() - math.random() * thinkInterval

	while state._alive do
		if not state.model.Parent then
			break
		end

		local now = os.clock()
		if now - state._lastThink >= thinkInterval then
			state._lastThink = now
			local ok, err = pcall(thinkFn, state)
			if not ok then
				warn("[PathfindingAgent] think error:", err)
			end
		end

		local ok2, err2 = pcall(locomoteFn, state)
		if not ok2 then
			warn("[PathfindingAgent] locomote error:", err2)
		end

		task.wait(locomoteStep)
	end
end

return PathfindingAgent
