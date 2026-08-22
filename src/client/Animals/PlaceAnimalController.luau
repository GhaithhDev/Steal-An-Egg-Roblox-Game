--//Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

--//Configs
local RemoteConfig = require(ReplicatedStorage.Shared.Configs.RemoteConfig)

--//Packages
local Net = require(ReplicatedStorage.Shared.Packages.Net)
local Trove = require(ReplicatedStorage.Shared.Packages.Trove)

local localPlayer = Players.LocalPlayer

local PlaceAnimalController = {}

-- reused across spawns: :Clean()'d at the start of every ListenToCharacter
-- call so only the current character's connections are ever live
local characterTrove = Trove.new()
local equippedAnimalTool: Tool? = nil

local function IsAnimalTool(instance: Instance): boolean
	return instance:IsA("Tool") and instance:GetAttribute("AnimalId") ~= nil
end

local function OnInputBegan(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent or not equippedAnimalTool then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local camera = Workspace.CurrentCamera
	local character = localPlayer.Character
	if not camera or not character then
		return
	end

	local ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if not result then
		return
	end

	Net:RemoteEvent(RemoteConfig.Animals.PlaceAnimal.Name):FireServer(result.Position)
end

local function ListenToCharacter(character: Model)
	characterTrove:Clean()
	equippedAnimalTool = nil

	for _, child in character:GetChildren() do
		if IsAnimalTool(child) then
			equippedAnimalTool = child :: Tool
		end
	end

	characterTrove:Connect(character.ChildAdded, function(child)
		if IsAnimalTool(child) then
			equippedAnimalTool = child :: Tool
		end
	end)
	characterTrove:Connect(character.ChildRemoved, function(child)
		if child == equippedAnimalTool then
			equippedAnimalTool = nil
		end
	end)
end

function PlaceAnimalController.Start()
	UserInputService.InputBegan:Connect(OnInputBegan)

	if localPlayer.Character then
		ListenToCharacter(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(ListenToCharacter)
end

return PlaceAnimalController
