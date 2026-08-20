--//Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--//Configs
local RemoteConfig = require(ReplicatedStorage.Shared.Configs.RemoteConfig)

--//Packages
local Net = require(ReplicatedStorage.Shared.Packages.Net)
local Trove = require(ReplicatedStorage.Shared.Packages.Trove)

--//Controllers
local DangerCornersController = require(script.Parent.Parent.UI.DangerCornersController)

local localPlayer = Players.LocalPlayer

local CarryEggsController = {}

local playerGui: PlayerGui
local mainGui: ScreenGui
local dropButton: TextButton

-- reused across spawns: :Clean()'d at the start of every ListenToCharacter
-- call so only the current character's connections are ever live
local characterTrove = Trove.new()

local function IsEgg(instance: Instance): boolean
	return instance:IsA("Model") and instance:GetAttribute("EggName") ~= nil and not instance:IsA("Tool")
end

local function FindCarriedEgg(character: Model): Model?
	for _, child in character:GetChildren() do
		if IsEgg(child) then
			return child
		end
	end
	return nil
end

local function SetCarrying(isCarrying: boolean)
	dropButton.Visible = isCarrying
	DangerCornersController.ToggleDangerCorners(isCarrying)
end

local function ListenToCharacter(character: Model)
	characterTrove:Clean()

	SetCarrying(FindCarriedEgg(character) ~= nil)

	characterTrove:Connect(character.ChildAdded, function(child)
		if IsEgg(child) then
			print(child)
			SetCarrying(true)
		end
	end)
	characterTrove:Connect(character.ChildRemoved, function(child)
		if IsEgg(child) then
			SetCarrying(false)
		end
	end)

	local humanoid = character:FindFirstChildWhichIsA("Humanoid") or character:WaitForChild("Humanoid")
	characterTrove:Connect(humanoid.Died, function()
		SetCarrying(false)
	end)

	characterTrove:Connect(localPlayer.CharacterRemoving, function()
		SetCarrying(false)
	end)
end

function CarryEggsController.Start()
	playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	mainGui = playerGui:WaitForChild("Main") :: ScreenGui
	dropButton = mainGui:WaitForChild("DropEgg") :: TextButton
	dropButton.Visible = false
	local dropTextButton = dropButton:WaitForChild("TextButton")
	if dropTextButton then
		dropTextButton.Activated:Connect(function()
			Net:RemoteEvent(RemoteConfig.Eggs.DropEgg.Name):FireServer()
		end)
	end

	if localPlayer.Character then
		ListenToCharacter(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(ListenToCharacter)
end

return CarryEggsController
