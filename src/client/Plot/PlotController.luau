local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local PlotConfig = require(ReplicatedStorage.Shared.Configs.PlotConfig)

local OWNER_ATTRIBUTE = PlotConfig.OWNER_ATTRIBUTE
local SHOW_ICON_DISTANCE = 25
local ICON_ACTION_DEBOUNCE = 0.5
local ICON_TWEEN_INFO = TweenInfo.new(0.4)
local ICON_IMAGE = "rbxassetid://105504781988292"
local ICON_SIZE = UDim2.fromOffset(80, 80)
local ICON_HIDDEN_SIZE = UDim2.fromOffset(0, 0)

local localPlayer = Players.LocalPlayer

local PlotController = {}

local playerPlot: Instance? = nil
local plotBase: Model? = nil
local plotIcon: BillboardGui? = nil
local isIconShown = false
local lastIconAction = 0

local function CreatePlotIcon(): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PlotIcon"
	billboard.Size = ICON_HIDDEN_SIZE
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 10, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 500

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.fromScale(1, 1)
	icon.BackgroundTransparency = 1
	icon.Image = ICON_IMAGE
	icon.Parent = billboard

	return billboard
end

local function ClearPlotIcon()
	if plotIcon then
		plotIcon:Destroy()
		plotIcon = nil
	end
	if plotBase then
		local highlight = plotBase:FindFirstChild("PlotHighlight")
		if highlight then
			highlight:Destroy()
		end
	end
	isIconShown = false
end

local function ShowIcon()
	if not plotIcon then
		return
	end
	TweenService:Create(plotIcon, ICON_TWEEN_INFO, { Size = ICON_SIZE }):Play()

	if plotBase and not plotBase:FindFirstChild("PlotHighlight") then
		local highlight = Instance.new("Highlight")
		highlight.Name = "PlotHighlight"
		highlight.FillTransparency = 1
		highlight.OutlineTransparency = 0.3
		highlight.OutlineColor = Color3.new(1, 1, 1)
		highlight.Parent = plotBase
	end
end

local function HideIcon()
	if not plotIcon then
		return
	end
	TweenService:Create(plotIcon, ICON_TWEEN_INFO, { Size = ICON_HIDDEN_SIZE }):Play()

	if plotBase then
		local highlight = plotBase:FindFirstChild("PlotHighlight")
		if highlight then
			highlight:Destroy()
		end
	end
end

local function SetupPlot(plotFolder: Instance)
	local isOwner = plotFolder:GetAttribute(OWNER_ATTRIBUTE) == localPlayer.UserId

	if not isOwner then
		if playerPlot == plotFolder then
			ClearPlotIcon()
			playerPlot = nil
			plotBase = nil
		end
		return
	end

	local base = plotFolder:FindFirstChildWhichIsA("Model")
	if not base then
		return
	end

	ClearPlotIcon()

	playerPlot = plotFolder
	plotBase = base

	local icon = CreatePlotIcon()
	icon.Adornee = base
	icon.Parent = base
	plotIcon = icon
end

local function Update()
	if not plotBase then
		return
	end

	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	if os.clock() - lastIconAction < ICON_ACTION_DEBOUNCE then
		return
	end

	local distance = (rootPart.Position - plotBase:GetPivot().Position).Magnitude
	if distance > SHOW_ICON_DISTANCE then
		if isIconShown then
			return
		end
		lastIconAction = os.clock()
		isIconShown = true
		ShowIcon()
	else
		if not isIconShown then
			return
		end
		lastIconAction = os.clock()
		isIconShown = false
		HideIcon()
	end
end

function PlotController.Start()
	local plotsFolder = Workspace:WaitForChild("Functional"):WaitForChild("Spawns"):WaitForChild("Plots")

	local function ListenToPlot(plotFolder: Instance)
		local function Refresh()
			SetupPlot(plotFolder)
		end

		Refresh()
		plotFolder:GetAttributeChangedSignal(OWNER_ATTRIBUTE):Connect(Refresh)
		-- The server clears and re-clones the base model on every (re)assignment,
		-- not just on Owner changing, so the icon must reattach to the new instance.
		plotFolder.ChildAdded:Connect(Refresh)
	end

	for _, plotFolder in plotsFolder:GetChildren() do
		ListenToPlot(plotFolder)
	end
	plotsFolder.ChildAdded:Connect(ListenToPlot)

	RunService.Heartbeat:Connect(Update)
end

return PlotController
