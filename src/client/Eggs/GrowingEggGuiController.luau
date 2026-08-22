--//Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

--//Configs
local GrowingEggsConfig = require(ReplicatedStorage.Shared.Configs.GrowingEggsConfig)

local GrowingEggGuiTemplate = ReplicatedStorage.Shared.Assets.BillBoards.GrowingEggGui

local GrowingEggGuiController = {}

local trackedBillboards: { [Model]: BillboardGui } = {}

local function FormatCountdown(secondsLeft: number): string
	if secondsLeft <= 0 then
		return "Ready!"
	end
	return `{math.ceil(secondsLeft)}s`
end

local function TrackEgg(eggModel: Model)
	if trackedBillboards[eggModel] then
		return
	end

	local billboard = GrowingEggGuiTemplate:Clone()
	billboard.Adornee = eggModel
	billboard.Size = GrowingEggsConfig.GUI_SIZE
	billboard.Enabled = not eggModel:GetAttribute("IsHatching")
	billboard.Parent = eggModel
	trackedBillboards[eggModel] = billboard

	eggModel:GetAttributeChangedSignal("IsHatching"):Connect(function()
		billboard.Enabled = not eggModel:GetAttribute("IsHatching")
	end)

	eggModel.Destroying:Connect(function()
		trackedBillboards[eggModel] = nil
	end)
end

-- ReadyTime is set a moment after the egg model is parented (see
-- GrowingEggsService.SpawnGrowingEgg), so a DescendantAdded pass may see the
-- Model before the attribute exists - fall back to its changed signal.
local function OnDescendantAdded(descendant: Instance)
	if not descendant:IsA("Model") then
		return
	end

	if descendant:GetAttribute("ReadyTime") then
		TrackEgg(descendant)
		return
	end

	local connection: RBXScriptConnection
	connection = descendant:GetAttributeChangedSignal("ReadyTime"):Connect(function()
		if descendant:GetAttribute("ReadyTime") then
			connection:Disconnect()
			TrackEgg(descendant)
		end
	end)
end

local function Update()
	local now = Workspace:GetServerTimeNow()
	for eggModel, billboard in trackedBillboards do
		if not eggModel.Parent then
			trackedBillboards[eggModel] = nil
			continue
		end

		local textLabel = billboard:FindFirstChild("TextLabel") :: TextLabel?
		local readyTime = eggModel:GetAttribute("ReadyTime")
		if textLabel and readyTime then
			textLabel.Text = FormatCountdown(readyTime - now)
			textLabel.Visible = true
		end
	end
end

function GrowingEggGuiController.Start()
	local plotsFolder = Workspace:WaitForChild("Functional"):WaitForChild("Spawns"):WaitForChild("Plots")

	for _, descendant in plotsFolder:GetDescendants() do
		OnDescendantAdded(descendant)
	end
	plotsFolder.DescendantAdded:Connect(OnDescendantAdded)

	task.spawn(function()
		while true do
			task.wait(GrowingEggsConfig.GUI_REFRESH_INTERVAL)
			Update()
		end
	end)
end

return GrowingEggGuiController
