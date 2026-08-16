--[[
	One-time generator for the Satchel backpack chrome + slot template.

	HOW TO USE
	1. In Roblox Studio, make sure you're in EDIT mode (not Play mode) — instances created
	   here only stick around permanently if built in Edit mode and then saved.
	2. Open the Command Bar (View tab > Command Bar).
	3. Paste this entire script in and press Enter.
	4. Save the place (Ctrl+S / Publish). The GUI now exists as real, editable instances:
	     StarterGui.BackpackGui        -- the hotbar/inventory panel chrome
	     ReplicatedStorage.Shared.Assets.CategoryButtonTemplate
	5. Re-running this script is safe — it replaces whatever it created last time, so you
	   can regenerate the base structure without losing nothing else in StarterGui/Assets.
	   Any hand styling you've done ON TOP of these instances (colors, extra decoration,
	   fonts) will be lost on a re-run, since this only rebuilds the base shapes/names
	   Satchel's code looks up — treat it as a starting point, not something to re-run
	   casually once designers have styled it.

	See src/shared/Packages/Satchel/SatchelInit.luau for the code that reads this tree,
	and the Inventory Style Guide artifact for what's safe to restyle afterward.
]]

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function corner(radius: number, parent: Instance): UICorner
	local c = Instance.new("UICorner")
	c.Name = "Corner"
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

--============================================================
-- BackpackGui
--============================================================

local existing = StarterGui:FindFirstChild("BackpackGui")
if existing then
	existing:Destroy()
end

local BackpackGui = Instance.new("ScreenGui")
BackpackGui.Name = "BackpackGui"
BackpackGui.DisplayOrder = 120
BackpackGui.IgnoreGuiInset = true
BackpackGui.ResetOnSpawn = false

-- Backpack (MainFrame) --------------------------------------------------

local Backpack = Instance.new("Frame")
Backpack.Name = "Backpack"
Backpack.BackgroundTransparency = 1
Backpack.Size = UDim2.fromScale(1, 1)
Backpack.Visible = false
Backpack.Parent = BackpackGui

local Hotbar = Instance.new("Frame")
Hotbar.Name = "Hotbar"
Hotbar.BackgroundTransparency = 1
Hotbar.Size = UDim2.fromScale(1, 1)
Hotbar.Parent = Backpack

-- Inventory ("All Items" panel) -----------------------------------------

local Inventory = Instance.new("Frame")
Inventory.Name = "Inventory"
Inventory.Size = UDim2.fromScale(1, 1)
Inventory.BackgroundColor3 = Color3.fromRGB(25, 27, 29)
Inventory.BackgroundTransparency = 0.3
Inventory.Active = true
Inventory.Visible = false
Inventory.Parent = Backpack
corner(8, Inventory)

local VRInventorySelector = Instance.new("TextButton")
VRInventorySelector.Name = "VRInventorySelector"
VRInventorySelector.Size = UDim2.fromScale(1, 1)
VRInventorySelector.BackgroundTransparency = 1
VRInventorySelector.Text = ""
VRInventorySelector.Parent = Inventory

local Selector = Instance.new("ImageLabel")
Selector.Name = "Selector"
Selector.BackgroundTransparency = 1
Selector.Size = UDim2.fromScale(1, 1)
Selector.Image = "rbxasset://textures/ui/Keyboard/key_selection_9slice.png"
Selector.ScaleType = Enum.ScaleType.Slice
Selector.SliceCenter = Rect.new(12, 12, 52, 52)
Selector.Visible = false
Selector.Parent = VRInventorySelector

local ScrollingFrame = Instance.new("ScrollingFrame")
ScrollingFrame.Name = "ScrollingFrame"
ScrollingFrame.BackgroundTransparency = 1
ScrollingFrame.Selectable = false
ScrollingFrame.ScrollingDirection = Enum.ScrollingDirection.Y
ScrollingFrame.BorderSizePixel = 0
ScrollingFrame.ScrollBarThickness = 8
ScrollingFrame.ScrollBarImageColor3 = Color3.new(1, 1, 1)
ScrollingFrame.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
ScrollingFrame.Size = UDim2.fromScale(1, 1)
ScrollingFrame.Parent = Inventory

local UIGridFrame = Instance.new("Frame")
UIGridFrame.Name = "UIGridFrame"
UIGridFrame.BackgroundTransparency = 1
UIGridFrame.Selectable = false
UIGridFrame.Parent = ScrollingFrame

local UIGridLayout = Instance.new("UIGridLayout")
UIGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIGridLayout.Parent = UIGridFrame

-- Search bar --------------------------------------------------------------
-- Position/size/colors here are a starting point; SatchelInit.luau no longer
-- overwrites them, so hand-tune freely.

local Search = Instance.new("Frame")
Search.Name = "Search"
Search.BackgroundColor3 = Color3.fromRGB(25, 27, 29)
Search.BackgroundTransparency = 0.2
Search.Size = UDim2.fromOffset(190, 30)
Search.Position = UDim2.new(1, -195, 0, 5)
Search.Parent = Inventory
corner(3, Search)

local searchBorder = Instance.new("UIStroke")
searchBorder.Name = "Border"
searchBorder.Color = Color3.new(1, 1, 1)
searchBorder.Thickness = 1
searchBorder.Transparency = 0.8
searchBorder.Parent = Search

local SearchBox = Instance.new("TextBox")
SearchBox.Name = "TextBox"
SearchBox.BackgroundTransparency = 1
SearchBox.Text = ""
SearchBox.Size = UDim2.new(1, -46, 1, -16)
SearchBox.AnchorPoint = Vector2.new(0, 0.5)
SearchBox.Position = UDim2.new(0, 8, 0.5, 0)
SearchBox.Parent = Search

local XButton = Instance.new("TextButton")
XButton.Name = "X"
XButton.Text = ""
XButton.BackgroundTransparency = 1
XButton.Size = UDim2.fromOffset(30, 30)
XButton.AnchorPoint = Vector2.new(1, 0.5)
XButton.Position = UDim2.new(1, 0, 0.5, 0)
XButton.Visible = false
XButton.Parent = Search

local XImage = Instance.new("ImageButton")
XImage.Name = "X"
XImage.Image = "rbxasset://textures/ui/InspectMenu/x.png"
XImage.BackgroundTransparency = 1
XImage.BorderSizePixel = 0
XImage.AnchorPoint = Vector2.new(0.5, 0.5)
XImage.Position = UDim2.fromScale(0.5, 0.5)
XImage.Size = UDim2.fromOffset(20, 20)
XImage.Parent = XButton

--============================================================
-- SlotTemplate (one item slot; cloned per Tool by MakeSlot)
--============================================================

local SlotTemplate = Instance.new("TextButton")
SlotTemplate.Name = "SlotTemplate"
SlotTemplate.Text = ""
SlotTemplate.BorderSizePixel = 0
SlotTemplate.Size = UDim2.fromOffset(60, 60)
SlotTemplate.Visible = false
SlotTemplate.Parent = BackpackGui
corner(8, SlotTemplate)

local SelectionObjectClipper = Instance.new("Frame")
SelectionObjectClipper.Name = "SelectionObjectClipper"
SelectionObjectClipper.BackgroundTransparency = 1
SelectionObjectClipper.Visible = false
SelectionObjectClipper.Parent = SlotTemplate

local SlotSelector = Instance.new("ImageLabel")
SlotSelector.Name = "Selector"
SlotSelector.BackgroundTransparency = 1
SlotSelector.Size = UDim2.fromScale(1, 1)
SlotSelector.Image = "rbxasset://textures/ui/Keyboard/key_selection_9slice.png"
SlotSelector.ScaleType = Enum.ScaleType.Slice
SlotSelector.SliceCenter = Rect.new(12, 12, 52, 52)
SlotSelector.Parent = SelectionObjectClipper

local Icon = Instance.new("ImageLabel")
Icon.Name = "Icon"
Icon.BackgroundTransparency = 1
Icon.Size = UDim2.fromScale(1, 1)
Icon.Parent = SlotTemplate
corner(8, Icon)

local ToolName = Instance.new("TextLabel")
ToolName.Name = "ToolName"
ToolName.BackgroundTransparency = 1
ToolName.Text = ""
ToolName.TextWrapped = true
ToolName.TextTruncate = Enum.TextTruncate.AtEnd
ToolName.Size = UDim2.fromScale(1, 1)
ToolName.Parent = SlotTemplate

local ToolTip = Instance.new("TextLabel")
ToolTip.Name = "ToolTip"
ToolTip.Text = ""
ToolTip.ZIndex = 2
ToolTip.TextWrapped = false
ToolTip.TextYAlignment = Enum.TextYAlignment.Center
ToolTip.AnchorPoint = Vector2.new(0.5, 1)
ToolTip.BorderSizePixel = 0
ToolTip.Visible = false
ToolTip.AutomaticSize = Enum.AutomaticSize.X
ToolTip.Size = UDim2.fromOffset(0, 16)
ToolTip.Position = UDim2.new(0.5, 0, 0, -5)
ToolTip.Parent = SlotTemplate
corner(3, ToolTip)

local ToolTipPadding = Instance.new("UIPadding")
ToolTipPadding.PaddingLeft = UDim.new(0, 4)
ToolTipPadding.PaddingRight = UDim.new(0, 4)
ToolTipPadding.PaddingTop = UDim.new(0, 4)
ToolTipPadding.PaddingBottom = UDim.new(0, 4)
ToolTipPadding.Parent = ToolTip

local Number = Instance.new("TextLabel")
Number.Name = "Number"
Number.BackgroundTransparency = 1
Number.Text = ""
Number.Size = UDim2.fromScale(0.4, 0.4)
Number.Visible = false
Number.Parent = SlotTemplate

BackpackGui.Parent = StarterGui

--============================================================
-- CategoryButtonTemplate (one Pets/Eggs tab; cloned per category)
--============================================================

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = Shared:FindFirstChild("Assets") or Instance.new("Folder")
Assets.Name = "Assets"
Assets.Parent = Shared

local existingTab = Assets:FindFirstChild("CategoryButtonTemplate")
if existingTab then
	existingTab:Destroy()
end

local CategoryButtonTemplate = Instance.new("Frame")
CategoryButtonTemplate.Name = "CategoryButtonTemplate"
CategoryButtonTemplate.AutomaticSize = Enum.AutomaticSize.Y
CategoryButtonTemplate.Size = UDim2.fromOffset(64, 0)
CategoryButtonTemplate.BackgroundTransparency = 1
CategoryButtonTemplate.Parent = Assets

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Vertical
tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
tabLayout.Padding = UDim.new(0, 4)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = CategoryButtonTemplate

local Label = Instance.new("TextLabel")
Label.Name = "Label"
Label.LayoutOrder = 1
Label.Size = UDim2.fromOffset(64, 22)
Label.BackgroundColor3 = Color3.fromRGB(25, 27, 29)
Label.TextColor3 = Color3.new(1, 1, 1)
Label.Font = Enum.Font.GothamBold
Label.TextSize = 14
Label.Text = "Category"
Label.Parent = CategoryButtonTemplate
corner(6, Label)

local TabButton = Instance.new("TextButton")
TabButton.Name = "Icon"
TabButton.LayoutOrder = 2
TabButton.Size = UDim2.fromOffset(64, 64)
TabButton.BackgroundColor3 = Color3.fromRGB(25, 27, 29)
TabButton.Text = ""
TabButton.Parent = CategoryButtonTemplate
corner(12, TabButton)

local IconImage = Instance.new("ImageLabel")
IconImage.Name = "IconImage"
IconImage.AnchorPoint = Vector2.new(0.5, 0.5)
IconImage.Position = UDim2.fromScale(0.5, 0.5)
IconImage.Size = UDim2.fromScale(0.65, 0.65)
IconImage.BackgroundTransparency = 1
IconImage.Parent = TabButton

print("GenerateBackpackGui: done. StarterGui.BackpackGui and ReplicatedStorage.Shared.Assets.CategoryButtonTemplate are ready to hand-style. Save the place to keep them.")
