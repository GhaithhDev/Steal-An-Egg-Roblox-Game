--This service will keep track of what eggs are spawned in each area and their states

--//Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local SpawnsEggsService = require(ServerScriptService.Server.Eggs.SpawnsEggsService)

--//Configs
local EggsConfig = require(ReplicatedStorage.Shared.Configs.EggsConfig)

--//Cache
local AreaEggsService = {}
AreaEggsService.EggsInNests = {} -- [areaName] = { { model = Model, position = Vector3, radius = number }, ... } -- In nests waiting for a player to take it
AreaEggsService.CarriedEggs = {} -- rig carrying it (player character or NPC)
AreaEggsService.DroppedEggs = {}

type PlacedEgg = { model: Model, position: Vector3, radius: number }

local function SpawnEggsInArea(area: BasePart)
    local placedEggs: { PlacedEgg } = {}
    AreaEggsService.EggsInNests[area.Name] = placedEggs

    if EggsConfig.EggsInEachArea <= 0 then
        return
    end

    local minX = (area:FindFirstChild("MinX") :: NumberValue).Value
    local maxX = (area:FindFirstChild("MaxX") :: NumberValue).Value
    local groundY = area.Position.Y

    local function IsFree(position: Vector3, radius: number): boolean
        for _, placed in placedEggs do
            local minDistance = radius + placed.radius + EggsConfig.EGG_PLACEMENT_PADDING
            local distance = (Vector2.new(position.X, position.Z) - Vector2.new(placed.position.X, placed.position.Z)).Magnitude
            if distance < minDistance then
                return false
            end
        end
        return true
    end

    local function Place(position: Vector3, eggName: string, eggScale: number, radius: number)
        local eggModel = SpawnsEggsService.SpawnEgg(eggName, eggScale, position, true, area.Name)
        if eggModel then
            table.insert(placedEggs, { model = eggModel, position = position, radius = radius })
        end
    end

    -- Slot 1's radius is picked before spawning either seed egg, so the pair can be
    -- built symmetrically around area.Position (see slot 2 below).
    local firstName, firstScale = EggsConfig.GetRandomEgg(area.Name)
    local firstRadius = SpawnsEggsService.GetEggFootprintRadius(firstName, firstScale)
    if not firstRadius then
        return
    end
    firstRadius *= EggsConfig.NEST_SCALE_MULTIPLIER

    if EggsConfig.EggsInEachArea == 1 then
        Place(Vector3.new(math.clamp(area.Position.X, minX, maxX), groundY, area.Position.Z), firstName, firstScale, firstRadius)
        return
    end

    local secondName, secondScale = EggsConfig.GetRandomEgg(area.Name)
    local secondRadius = SpawnsEggsService.GetEggFootprintRadius(secondName, secondScale)
    if not secondRadius then
        return
    end
    secondRadius *= EggsConfig.NEST_SCALE_MULTIPLIER

    -- Split the pair along X (the area's bounded axis) so they touch each other
    -- exactly at area.Position:
    -- (spot1 + directionToCenter1 * radius1 + spot2 + directionToCenter2 * radius2) / 2
    --   == area.Position, with directionToCenter1 = +X and directionToCenter2 = -X.
    local touchGap = EggsConfig.EGG_PLACEMENT_PADDING
    local unclampedFirstX = area.Position.X - firstRadius - touchGap / 2
    local unclampedSecondX = area.Position.X + secondRadius + touchGap / 2

    -- Clamping each side independently could pull them closer than touchGap allows
    -- (e.g. if area.Position sits right at MinX/MaxX instead of centered between them).
    -- Shift the whole pair together instead, so their separation - and the no-overlap
    -- guarantee - is preserved even if that means the seam isn't exactly on area.Position.
    local shift = 0
    if unclampedFirstX < minX then
        shift = minX - unclampedFirstX
    elseif unclampedSecondX > maxX then
        shift = maxX - unclampedSecondX
    end

    local firstPosition = Vector3.new(unclampedFirstX + shift, groundY, area.Position.Z)
    local secondPosition = Vector3.new(unclampedSecondX + shift, groundY, area.Position.Z)

    Place(firstPosition, firstName, firstScale, firstRadius)
    Place(secondPosition, secondName, secondScale, secondRadius)

    -- Every egg after the seed pair just touches a random already-placed egg: pick an
    -- anchor, pick a random angle around it, and sit right up against it. Retry with a
    -- different anchor/angle if that spot bumps into some other already-placed egg.
    for _ = 3, EggsConfig.EggsInEachArea do
        local eggName, eggScale = EggsConfig.GetRandomEgg(area.Name)
        local eggRadius = SpawnsEggsService.GetEggFootprintRadius(eggName, eggScale)
        if not eggRadius then
            continue
        end
        local nestRadius = eggRadius * EggsConfig.NEST_SCALE_MULTIPLIER

        local placed = false
        for _ = 1, EggsConfig.EGG_PLACEMENT_MAX_ATTEMPTS do
            local anchor = placedEggs[math.random(1, #placedEggs)]
            local angle = math.random() * math.pi * 2
            local distance = anchor.radius + nestRadius + touchGap
            local candidate = Vector3.new(
                math.clamp(anchor.position.X + math.cos(angle) * distance, minX, maxX),
                groundY,
                anchor.position.Z + math.sin(angle) * distance
            )
            if IsFree(candidate, nestRadius) then
                Place(candidate, eggName, eggScale, nestRadius)
                placed = true
                break
            end
        end

        if not placed then
            warn(`AreaEggsService: couldn't find a free spot for a {eggName} in {area.Name} after {EggsConfig.EGG_PLACEMENT_MAX_ATTEMPTS} attempts - skipped`)
        end
    end
end

local function ClearEggsInAllAreas()
    for _, placedEggs in AreaEggsService.EggsInNests do
        for _, placed in placedEggs do
            placed.model:Destroy()
        end
    end
    table.clear(AreaEggsService.EggsInNests)
end

local function SpawnEggsInAllAreas()
    ClearEggsInAllAreas()
    for _, area in workspace.Functional.EggsAreas:GetChildren() do
        if area:IsA("BasePart") then
            SpawnEggsInArea(area)
        end
    end
end

function AreaEggsService.Start(Services)
    SpawnsEggsService = Services.SpawnsEggsService
    SpawnEggsInAllAreas()
end

return AreaEggsService