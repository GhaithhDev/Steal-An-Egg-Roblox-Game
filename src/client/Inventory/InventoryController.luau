local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryConfig = require(ReplicatedStorage.Shared.Configs.InventoryConfig)
local Net = require(ReplicatedStorage.Shared.Packages.Net)

local TAB_ICONS = {
	[InventoryConfig.Categories.Pets] = "rbxassetid://4871217186",
	[InventoryConfig.Categories.Eggs] = "rbxassetid://11637882493",
}
local TAB_ORDER = { InventoryConfig.Categories.Pets, InventoryConfig.Categories.Eggs }

local ICON_SIZE = UDim2.fromOffset(64, 64)
local LABEL_SIZE = UDim2.fromOffset(64, 22)
local ACTIVE_COLOR = Color3.fromRGB(0, 162, 255)
local INACTIVE_COLOR = Color3.fromRGB(25, 27, 29)

local localPlayer = Players.LocalPlayer

local InventoryController = {}

local tabIcons: { [string]: ImageLabel } = {}

local function RefreshTabs()
	local activeCategory = localPlayer:GetAttribute(InventoryConfig.ACTIVE_CATEGORY_ATTRIBUTE)
	for category, icon in tabIcons do
		icon.BackgroundColor3 = (category == activeCategory) and ACTIVE_COLOR or INACTIVE_COLOR
	end
end

-- Cloned from the designer-authored CategoryButtonTemplate (see
-- tools/GenerateBackpackGui.lua) instead of being hand-built here, so the look of a tab
-- (label pill + icon square) is something the design team can restyle in Studio.
local function CreateTabButton(template: Frame, category: string, layoutOrder: number): Frame
	local tab = template:Clone()
	tab.Name = category
	tab.LayoutOrder = layoutOrder

	local label = tab:WaitForChild("Label") :: TextLabel
	label.Text = category
	label.Size = LABEL_SIZE

	local button = tab:WaitForChild("Icon") :: TextButton
	button.Size = ICON_SIZE
	local icon = button:WaitForChild("IconImage") :: ImageLabel
	icon.Image = TAB_ICONS[category]

	button.Activated:Connect(function()
		Net:RemoteEvent("SwitchCategory"):FireServer(category)
	end)

	tabIcons[category] = button

	return tab
end

-- Docked as a child of Satchel's own Inventory panel (BackpackGui.Backpack.Inventory) so it
-- inherits that panel's Visible toggle for free, and sticks to its left edge like the reference.
local function DockTabs(inventoryFrame: Frame)
	local template = ReplicatedStorage.Shared.Assets:WaitForChild("CategoryButtonTemplate") :: Frame

	local container = Instance.new("Frame")
	container.Name = "CategoryTabs"
	container.AnchorPoint = Vector2.new(1, 0)
	container.Position = UDim2.new(0, -6, 0, 24)
	container.AutomaticSize = Enum.AutomaticSize.XY
	container.BackgroundTransparency = 1
	container.Parent = inventoryFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 14)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	for index, category in TAB_ORDER do
		CreateTabButton(template, category, index).Parent = container
	end
end

-- The hotbar never changes with category (Satchel places tools there purely by fill
-- order/capacity, independent of us). Only the grid is category-filtered: a grid slot's
-- Category attribute (mirrored from its Tool by SatchelInit.luau) is compared against the
-- active category, and hidden on mismatch. Uncategorized tools never reach the grid at all
-- (SatchelInit.luau's MoveToInventory guard blocks that), so this never needs to hide those.
local function SetupGridCategoryFilter(inventoryFrame: Frame)
	local uiGridFrame = inventoryFrame:WaitForChild("ScrollingFrame"):WaitForChild("UIGridFrame")

	local function ApplyFilter(instance: Instance)
		if not instance:IsA("GuiObject") or instance.Name == "FakeSlot" then
			return
		end
		local slotFrame = instance :: GuiObject

		local activeCategory = localPlayer:GetAttribute(InventoryConfig.ACTIVE_CATEGORY_ATTRIBUTE)
		local slotCategory = slotFrame:GetAttribute(InventoryConfig.CATEGORY_ATTRIBUTE)
		local shouldShow = slotCategory ~= nil and slotCategory == activeCategory

		if slotFrame.Visible ~= shouldShow then
			slotFrame.Visible = shouldShow
		end
	end

	local function WatchSlot(instance: Instance)
		if not instance:IsA("GuiObject") or instance.Name == "FakeSlot" then
			return
		end

		ApplyFilter(instance)
		instance:GetPropertyChangedSignal("Visible"):Connect(function()
			ApplyFilter(instance)
		end)
		instance:GetAttributeChangedSignal(InventoryConfig.CATEGORY_ATTRIBUTE):Connect(function()
			ApplyFilter(instance)
		end)
	end

	for _, slotFrame in uiGridFrame:GetChildren() do
		WatchSlot(slotFrame)
	end
	uiGridFrame.ChildAdded:Connect(WatchSlot)

	localPlayer:GetAttributeChangedSignal(InventoryConfig.ACTIVE_CATEGORY_ATTRIBUTE):Connect(function()
		for _, slotFrame in uiGridFrame:GetChildren() do
			ApplyFilter(slotFrame)
		end
	end)
end

function InventoryController.Start()
	require(ReplicatedStorage.Shared.Packages.Satchel.SatchelInit)

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local inventoryFrame = playerGui
		:WaitForChild("BackpackGui")
		:WaitForChild("Backpack")
		:WaitForChild("Inventory") :: Frame

	DockTabs(inventoryFrame)
	SetupGridCategoryFilter(inventoryFrame)
	RefreshTabs()

	localPlayer:GetAttributeChangedSignal(InventoryConfig.ACTIVE_CATEGORY_ATTRIBUTE):Connect(RefreshTabs)
end

return InventoryController
