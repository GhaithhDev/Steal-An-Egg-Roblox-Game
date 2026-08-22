--This service will keep track of what eggs are spawned in each area and their states

--//Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local SpawnsEggsService = require(ServerScriptService.Server.Eggs.SpawnsEggsService)

--//Configs
local EggsConfig = require(ReplicatedStorage.Shared.Configs.EggsConfig)

--//Cache
local AreaEggsService = {}
-- [areaName] = { { eggModel = Model?, nestModel = Model, position = Vector3, radius = number }, ... }
-- One permanent slot per nest - eggModel is nil while the slot is empty (egg
-- carried away). Slots are never removed once created (see Place/RestockNest)
-- so a slot's index into this array is a stable id an egg can carry forward
-- as its "NestSlotIndex" attribute across carry/drop/re-spawn.
AreaEggsService.EggsInNests = {}
AreaEggsService.CarriedEggs = {} -- rig carrying it (player character or NPC)
AreaEggsService.DroppedEggs = {}

type PlacedEgg = { eggModel: Model?, nestModel: Model, position: Vector3, radius: number }

local AreaEndAtFolder: Folder

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
        local eggModel = SpawnsEggsService.SpawnEgg(eggName, eggScale, position, true, area.Name, EggsConfig.BABY_SCALE_FRACTION)
        if eggModel then
            -- SpawnEgg(addNest = true) reparents eggModel into a nest Model
            -- before returning - grab that as the slot's permanent nest.
            local nestModel = eggModel.Parent :: Model
            table.insert(placedEggs, { eggModel = eggModel, nestModel = nestModel, position = position, radius = radius })
            eggModel:SetAttribute("NestSlotIndex", #placedEggs)
        end
    end

    -- Slot 1's radius is picked before spawning either seed egg, so the pair can be
    -- built symmetrically around area.Position (see slot 2 below).
    local firstName, firstScale = EggsConfig.GetRandomEgg(area.Name)
    local firstRadius = SpawnsEggsService.GetEggFootprintRadius(firstName, firstScale, EggsConfig.BABY_SCALE_FRACTION)
    if not firstRadius then
        return
    end
    firstRadius *= EggsConfig.NEST_SCALE_MULTIPLIER

    if EggsConfig.EggsInEachArea == 1 then
        Place(Vector3.new(math.clamp(area.Position.X, minX, maxX), groundY, area.Position.Z), firstName, firstScale, firstRadius)
        return
    end

    local secondName, secondScale = EggsConfig.GetRandomEgg(area.Name)
    local secondRadius = SpawnsEggsService.GetEggFootprintRadius(secondName, secondScale, EggsConfig.BABY_SCALE_FRACTION)
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
        local eggRadius = SpawnsEggsService.GetEggFootprintRadius(eggName, eggScale, EggsConfig.BABY_SCALE_FRACTION)
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
            placed.nestModel:Destroy() -- cascades to the egg too, if occupied
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

-- Which area (by name) a ground position currently falls in, judged purely by
-- Z against workspace.Functional.AreaEndAt's per-area boundary Parts - walks
-- EggsConfig.AreaOrder (closest-to-spawn first) and returns the first area
-- whose boundary the position is still short of. Independent of any egg's
-- own "Area" attribute (that tracks origin, not current location).
function AreaEggsService.GetAreaAtPosition(position: Vector3): string?
    for _, areaName in EggsConfig.AreaOrder do
        local boundary = AreaEndAtFolder:FindFirstChild(areaName)
        if boundary and position.Z > boundary.Position.Z then
            return areaName
        end
    end
    return nil
end

-- Places a fresh egg back into the nest slot it originally came from (see
-- the NestSlotIndex attribute threaded through CarryEggsService's carry/drop
-- handling). No-ops if the slot can't be found - a rare edge case, not worth
-- a fallback that could reintroduce a retrieval loop.
function AreaEggsService.RestockNest(area: string, nestSlotIndex: number?, eggName: string, eggScale: number)
    local slots = AreaEggsService.EggsInNests[area]
    local slot = slots and nestSlotIndex and slots[nestSlotIndex]
    if not (slot and slot.nestModel and slot.nestModel.Parent) then
        return
    end

    local eggModel = SpawnsEggsService.SpawnEgg(eggName, eggScale, slot.position, false, area, EggsConfig.BABY_SCALE_FRACTION)
    if not eggModel then
        return
    end

    eggModel.Parent = slot.nestModel
    eggModel:SetAttribute("NestSlotIndex", nestSlotIndex)
    slot.eggModel = eggModel
end

function AreaEggsService.Start(Services)
    SpawnsEggsService = Services.SpawnsEggsService
    AreaEndAtFolder = workspace.Functional.AreaEndAt
    SpawnEggsInAllAreas()
end

return AreaEggsService