--//Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CarryEggsService =  nil

--//Configs
local EggsConfig = require(ReplicatedStorage.Shared.Configs.EggsConfig)
local GroundHeight = 2.138
local IsTesting = false
--//Packages
local ModelUtils = require(ReplicatedStorage.Shared.Packages.ModelUtils)
local Trove = require(ReplicatedStorage.Shared.Packages.Trove)

--//Assets
local EggModels = ReplicatedStorage.Shared.Assets.Eggs
local NestModel = ReplicatedStorage.Shared.Assets.NestModel:FindFirstChildWhichIsA("Model")

local SpawnsEggsService = {}

local SpawnedEggsFolder = workspace.Functional.Spawns.Eggs

local function SpawnNest(eggModel: Model)
    --Spawn nest NestModel and position it so that it's bottom is at the egg bottom
    -- nest model scale should be modified so that visible horizontal size should be 125% than the egg visible horizontal size
    local eggCFrame, eggSize = eggModel:GetBoundingBox()
    local eggHorizontalSize = math.max(eggSize.X, eggSize.Z)
    local eggBottom = Vector3.new(eggCFrame.Position.X, eggCFrame.Position.Y - eggSize.Y / 2, eggCFrame.Position.Z)

    local nest = NestModel:Clone()
    local _, nestSize = nest:GetBoundingBox()
    local nestHorizontalSize = math.max(nestSize.X, nestSize.Z)

    nest:ScaleTo((eggHorizontalSize * EggsConfig.NEST_SCALE_MULTIPLIER) / nestHorizontalSize)
    ModelUtils.AlignModelBottom(nest, eggBottom)

    nest.Parent = eggModel.Parent
    eggModel.Parent = nest
end

function SpawnsEggsService.GetEggFootprintRadius(eggName: string, eggScale: number): number?
    local template = EggModels:FindFirstChild(eggName)
    if not template or not template:IsA("Model") then
        return nil
    end

    local _, size = template:GetBoundingBox()
    return (math.max(size.X, size.Z) / 2) * eggScale
end

local function AddCarryPrompt(eggModel: Model)
    local part = eggModel.PrimaryPart or eggModel:FindFirstChildWhichIsA("BasePart", true)
    if not part then
        return
    end

    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "CarryPrompt"
    prompt.ActionText = EggsConfig.CARRY_PROMPT_ACTION_TEXT
    prompt.ObjectText = eggModel.Name
    prompt.HoldDuration = EggsConfig.CARRY_PROMPT_HOLD_DURATION
    prompt.MaxActivationDistance = EggsConfig.CARRY_PROMPT_MAX_DISTANCE
    prompt.RequiresLineOfSight = false
    prompt.Parent = part

    local carryPromptTrove = Trove.new()
    carryPromptTrove:Add(prompt.Triggered:Connect(function(player: Player)
        if CarryEggsService then
            CarryEggsService.ValidatePlayerCarryEgg(player, eggModel)
        end
    end))

    local function clearPromptTrove()
        carryPromptTrove:Destroy()
    end
    eggModel.Destroying:Connect(clearPromptTrove)
    prompt.Destroying:Connect(clearPromptTrove)
end

function SpawnsEggsService.SpawnEgg(eggName: string, eggScale: number, spawnPosition: Vector3, addNest: boolean?, area: string?): Model?
	--spawn egg model and position so that it's bottom is at the ground
    local template = EggModels:FindFirstChild(eggName)
    if not template or not template:IsA("Model") then
        return nil
    end

    local eggModel = template:Clone()
    eggModel:ScaleTo(eggScale)
    eggModel:SetAttribute("EggName", eggName)
    eggModel:SetAttribute("EggScale", eggScale)
    eggModel:SetAttribute("Area", area)
    ModelUtils.AlignModelBottom(eggModel, Vector3.new(spawnPosition.X,GroundHeight,spawnPosition.Z))
    eggModel.Parent = SpawnedEggsFolder

    if addNest then
        SpawnNest(eggModel)
    end

    AddCarryPrompt(eggModel)

    return eggModel
end

-- Converts an egg template into a Tool a player can carry in their Backpack -
-- every part becomes a direct child of the Tool (Roblox requires the grip
-- part to be named "Handle" and be a direct child, not nested in a Model) -
-- welded to the (renamed) primary part exactly like SpawnEgg does for the
-- carried-in-hand version.
function SpawnsEggsService.CreateEggTool(eggName: string, eggScale: number, eggId: string): Tool?
    local template = EggModels:FindFirstChild(eggName)
    if not template or not template:IsA("Model") then
        return nil
    end

    local eggModel = template:Clone()
    eggModel:ScaleTo(eggScale)

    local primaryPart = eggModel.PrimaryPart
    if not primaryPart then
        eggModel:Destroy()
        warn(`Egg {eggName} doesn't have a primary part therefore it can't be turned into a tool`)
        return nil
    end
    primaryPart.Name = "Handle"

    for _, part in eggModel:GetDescendants() do
        if not part:IsA("BasePart") then
            continue
        end
        part.Anchored = false
        part.CanCollide = false
        part.Massless = true
        if part ~= primaryPart then
            local weld = part:FindFirstChildWhichIsA("WeldConstraint") or Instance.new("WeldConstraint")
            weld.Part0 = primaryPart
            weld.Part1 = part
            weld.Parent = part
        end
    end

    local tool = Instance.new("Tool")
    tool.Name = eggName
    tool.RequiresHandle = true
    tool:SetAttribute("EggName", eggName)
    tool:SetAttribute("EggScale", eggScale)
    tool:SetAttribute("EggId", eggId)
    tool:SetAttribute("Category","Eggs")

    for _, child in eggModel:GetChildren() do
        child.Parent = tool
    end
    eggModel:Destroy()

    return tool
end

local function TestEggs()
    if not IsTesting then return end
    for i = -5,5,1 do
        local spawnPosition = Vector3.new(i * 10, GroundHeight, -10)
        local name, scale = EggsConfig.GetRandomEgg("Forest")
        SpawnsEggsService.SpawnEgg(name, scale, spawnPosition, true)
    end
end

function SpawnsEggsService.Start(Services)
    CarryEggsService = Services.CarryEggsService
    TestEggs()
end

return SpawnsEggsService
